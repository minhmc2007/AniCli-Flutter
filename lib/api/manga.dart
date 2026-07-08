import 'dart:convert';
import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// Debug logging toggle — set to true to see AllManga API flow
bool _mangaDebug = true;
void _log(String msg) {
  if (_mangaDebug) debugPrint('[AllMangaCore] $msg');
}

// ════════════════════════════════════════════════════════════════════════════
// SHARED MODEL
// ════════════════════════════════════════════════════════════════════════════

class AnimeModel {
  final String id;
  final String name;
  String? thumbnail;
  final bool isManga;
  final String sourceId;

  AnimeModel({
    required this.id,
    required this.name,
    this.thumbnail,
    this.isManga = false,
    this.sourceId = 'en',
  });

  factory AnimeModel.fromJson(Map<String, dynamic> json) => AnimeModel(
        id: json['_id'] ?? json['id'] ?? '',
        name: json['name'] ?? 'Unknown',
        thumbnail: json['thumbnail'],
        isManga: json['isManga'] ?? false,
        sourceId: json['sourceId'] ?? 'en',
      );

  factory AnimeModel.fromMangaDex(Map<String, dynamic> json) {
    final attr = json['attributes'];
    String? coverFileName;
    for (final rel in (json['relationships'] as List? ?? [])) {
      if (rel['type'] == 'cover_art') {
        coverFileName = rel['attributes']?['fileName'];
      }
    }
    final String id = json['id'];
    String thumbUrl = 'https://via.placeholder.com/150';
    if (coverFileName != null) {
      thumbUrl =
          'https://uploads.mangadex.org/covers/$id/$coverFileName.256.jpg';
    }
    String title = 'Unknown';
    if (attr['title'] is Map) {
      final Map t = attr['title'];
      title = t['en'] ?? (t.isNotEmpty ? t.values.first : 'Unknown');
    }
    return AnimeModel(
        id: id,
        name: title,
        thumbnail: thumbUrl,
        isManga: true,
        sourceId: 'mangadex');
  }

  factory AnimeModel.fromZetTruyen(Map<String, dynamic> json) {
    return AnimeModel(
      id: json['slug'] ?? '',
      name: json['name'] ?? 'Unknown',
      thumbnail: json['thumbnail'],
      isManga: true,
      sourceId: 'zettruyen',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'thumbnail': thumbnail,
        'isManga': isManga,
        'sourceId': sourceId,
      };

  String get fullImageUrl {
    if (thumbnail == null || thumbnail!.isEmpty) {
      return 'https://via.placeholder.com/300x450';
    }
    if (thumbnail!.startsWith('http')) return thumbnail!;
    return 'https://wp.youtube-anime.com/aln.youtube-anime.com/$thumbnail?w=250';
  }
}

// ════════════════════════════════════════════════════════════════════════════
// MANGA SOURCE PROVIDER
// ════════════════════════════════════════════════════════════════════════════

enum MangaSource { mangadex, allanime, zettruyen }

class MangaSourceProvider extends ChangeNotifier {
  static const _key = 'manga_source';
  MangaSource _source = MangaSource.allanime;

  MangaSource get source => _source;
  bool get isAllManga => _source == MangaSource.allanime;
  bool get isZetTruyen => _source == MangaSource.zettruyen;

  MangaSourceProvider() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == 'mangadex') {
      _source = MangaSource.mangadex;
    } else if (raw == 'zettruyen') {
      _source = MangaSource.zettruyen;
    } else {
      _source = MangaSource.allanime;
    }
    notifyListeners();
  }

  Future<void> setSource(MangaSource s) async {
    _source = s;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, s.name);
    notifyListeners();
  }
}

// ════════════════════════════════════════════════════════════════════════════
// ZETTRUYEN CORE
// ════════════════════════════════════════════════════════════════════════════

class ZetTruyenCore {
  static const String _baseUrl = 'https://www.zettruyen.africa';

  static const Map<String, String> _apiHeaders = {
    'accept': 'application/json, text/javascript, */*; q=0.01',
    'accept-language': 'vi,en-US;q=0.9,en;q=0.8',
    'referer': '$_baseUrl/',
    'user-agent':
        'Mozilla/5.0 (Linux; Android 6.0; Nexus 5 Build/MRA58N) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Mobile Safari/537.36',
    'x-requested-with': 'XMLHttpRequest',
  };

  static const Map<String, String> _htmlHeaders = {
    'accept':
        'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
    'accept-language': 'vi,en-US;q=0.9,en;q=0.8',
    'referer': '$_baseUrl/',
    'user-agent':
        'Mozilla/5.0 (Linux; Android 6.0; Nexus 5 Build/MRA58N) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Mobile Safari/537.36',
  };

  /// Returns a merged trending list from top_day + top_week + top_month,
  /// deduplicated by slug, then padded with the first page of the browse
  /// endpoint so the UI always has plenty of cards to show.
  ///
  /// Why: /api/comics/top only has ~5 entries per period bucket. The Python
  /// CLI sliced to [:5] for terminal display — a Flutter UI should show all
  /// available content with a scroll.
  static Future<List<AnimeModel>> getTrending() async {
    final seen = <String>{};
    final result = <AnimeModel>[];

    // 1. Merge all three top-period buckets from /api/comics/top
    try {
      final res = await http.get(
          Uri.parse('$_baseUrl/api/comics/top'), headers: _apiHeaders);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body)?['data'] ?? {};
        for (final key in ['top_day', 'top_week', 'top_month']) {
          for (final e in (data[key] as List? ?? [])) {
            final slug = (e['slug'] ?? '') as String;
            if (slug.isNotEmpty && seen.add(slug)) {
              result.add(AnimeModel.fromZetTruyen(e));
            }
          }
        }
      }
    } catch (_) {}

    // 2. Pad with the latest-updated comics page so there is always more content
    try {
      final res = await http.get(
          Uri.parse('$_baseUrl/api/comics?page=1&per_page=20&order=latest'),
          headers: _apiHeaders);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List items = data['data']?['comics'] ?? data['data'] ?? [];
        for (final e in items) {
          final slug = (e['slug'] ?? '') as String;
          if (slug.isNotEmpty && seen.add(slug)) {
            result.add(AnimeModel.fromZetTruyen(e));
          }
        }
      }
    } catch (_) {}

    return result;
  }

  /// Fetch a specific page of comics (for infinite-scroll / load-more UIs).
  /// [page] is 1-based. Returns an empty list on error or end of data.
  static Future<List<AnimeModel>> browse({int page = 1, int perPage = 20}) async {
    try {
      final res = await http.get(
          Uri.parse(
              '$_baseUrl/api/comics?page=$page&per_page=$perPage&order=latest'),
          headers: _apiHeaders);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List items = data['data']?['comics'] ?? data['data'] ?? [];
        return items.map((e) => AnimeModel.fromZetTruyen(e)).toList();
      }
    } catch (_) {}
    return [];
  }

  static Future<List<AnimeModel>> search(String query) async {
    if (query.trim().isEmpty) return getTrending();
    try {
      final res = await http.get(
          Uri.parse(
              '$_baseUrl/api/quick-search?q=${Uri.encodeQueryComponent(query.trim())}'),
          headers: _apiHeaders);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List results = data['data'] ?? [];
        return results.map((e) => AnimeModel.fromZetTruyen(e)).toList();
      }
    } catch (_) {}
    return [];
  }

  static Future<List<String>> getChapters(String mangaSlug) async {
    try {
      final res = await http.get(
          Uri.parse(
              '$_baseUrl/api/comics/$mangaSlug/chapters?per_page=-1&order=desc'),
          headers: _apiHeaders);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List chapters = data['data']?['chapters'] ?? [];
        return chapters.map((c) {
          final views = c['view'] ?? 0;
          return '${c['chapter_slug']}|${c['chapter_name']} (Views: $views)|${c['chapter_num']}';
        }).toList();
      }
    } catch (_) {}
    return [];
  }

  static Future<List<String>> getPages(
      String mangaSlug, String chapterString) async {
    final parts = chapterString.split('|');
    final String chapterSlug = parts[0];
    final String chapterNum = parts.length > 2 ? parts[2] : '1';

    String url = '$_baseUrl/truyen-tranh/$mangaSlug/$chapterSlug';
    List<String> pageUrls = [];

    try {
      var res = await http.get(Uri.parse(url), headers: _htmlHeaders);

      // FIX: handle 404 caused by 'chapter-' vs 'chuong-' slug mismatch
      // (matches Python fallback logic exactly)
      if (res.statusCode == 404) {
        String altSlug = chapterSlug;
        if (altSlug.contains('chapter-')) {
          altSlug = altSlug.replaceAll('chapter-', 'chuong-');
        } else if (altSlug.contains('chuong-')) {
          altSlug = altSlug.replaceAll('chuong-', 'chapter-');
        }
        url = '$_baseUrl/truyen-tranh/$mangaSlug/$altSlug';
        res = await http.get(Uri.parse(url), headers: _htmlHeaders);
      }

      if (res.statusCode == 200) {
        final html = res.body;
        final regExp =
            RegExp(r'(https?://[^"' "'" r' ]*(?:zetimage\.com)[^"' "'" r' ]*)');
        final matches = regExp.allMatches(html);

        for (final match in matches) {
          String u = match.group(1) ?? '';
          u = u.replaceAll('\\/', '/');
          if (!u.contains('thumb') &&
              !u.contains('avatar') &&
              (u.contains('.jpg') ||
                  u.contains('.png') ||
                  u.contains('.webp') ||
                  u.contains('.jpeg'))) {
            if (!pageUrls.contains(u)) pageUrls.add(u);
          }
        }
      }

      // Fallback: sequential brute-force up to 200 pages (aligned with Python)
      if (pageUrls.isEmpty) {
        for (int page = 1; page <= 200; page++) {
          final fallbackUrl =
              'https://cdn4.zetimage.com/$mangaSlug/$chapterNum/$page.jpg';
          try {
            final headRes = await http.head(Uri.parse(fallbackUrl),
                headers: {'accept': 'image/*', 'referer': '$_baseUrl/'});
            if (headRes.statusCode == 200) {
              pageUrls.add(fallbackUrl);
            } else {
              break;
            }
          } catch (_) {
            break;
          }
        }
      }
    } catch (_) {}
    return pageUrls;
  }
}

// ════════════════════════════════════════════════════════════════════════════
// MANGADEX CORE
// ════════════════════════════════════════════════════════════════════════════

class MangaCore {
  static const String _baseUrl = 'https://api.mangadex.org';
  static const Map<String, String> _headers = {
    'User-Agent': 'AniCli-Flutter/2.3.0'
  };

  static Future<List<AnimeModel>> getTrending() => search('');

  static Future<List<AnimeModel>> search(String query) async {
    final sb = StringBuffer('$_baseUrl/manga?limit=20&offset=0');
    if (query.trim().isNotEmpty) {
      sb.write('&title=${Uri.encodeQueryComponent(query.trim())}');
    }
    sb.write('&order[followedCount]=desc&includes[]=cover_art');
    for (final r in ['safe', 'suggestive', 'erotica', 'pornographic']) {
      sb.write('&contentRating[]=$r');
    }
    try {
      final res =
          await http.get(Uri.parse(sb.toString()), headers: _headers);
      if (res.statusCode == 200) {
        final List results = jsonDecode(res.body)['data'];
        return results.map((e) => AnimeModel.fromMangaDex(e)).toList();
      }
    } catch (_) {}
    return [];
  }

  static Future<List<String>> getChapters(String mangaId) async {
    Future<List<dynamic>> fetch(List<String>? langs) async {
      final sb = StringBuffer(
          '$_baseUrl/manga/$mangaId/feed?limit=500&order[chapter]=desc');
      for (final r in ['safe', 'suggestive', 'erotica', 'pornographic']) {
        sb.write('&contentRating[]=$r');
      }
      if (langs != null) {
        for (final l in langs) {
          sb.write('&translatedLanguage[]=$l');
        }
      }
      try {
        final res =
            await http.get(Uri.parse(sb.toString()), headers: _headers);
        if (res.statusCode == 200) return jsonDecode(res.body)['data'];
      } catch (_) {}
      return [];
    }

    var chapters = await fetch(['en']);
    if (chapters.isEmpty) chapters = await fetch(null);
    final results = <String>[];
    for (final c in chapters) {
      final attr = c['attributes'];
      if (attr['externalUrl'] != null) continue;
      results.add(
          '${c['id']}|${attr['chapter'] ?? 'Oneshot'} [${attr['translatedLanguage'] ?? '??'}]');
    }
    return _numericSort(results);
  }

  static Future<List<String>> getPages(String chapterId) async {
    final realId =
        chapterId.contains('|') ? chapterId.split('|')[0] : chapterId;
    try {
      final res = await http.get(
          Uri.parse('$_baseUrl/at-home/server/$realId'), headers: _headers);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final String base = data['baseUrl'];
        final String hash = data['chapter']['hash'];
        final List files = data['chapter']['data'];
        return files.map((f) => '$base/data/$hash/$f').toList();
      }
    } catch (_) {}
    return [];
  }

  static Future<String?> findMangaDexCover(String title) async {
    try {
      final results = await search(title);
      if (results.isNotEmpty) return results.first.thumbnail;
    } catch (_) {}
    return null;
  }

  static List<String> _numericSort(List<String> list) {
    list.sort((a, b) {
      final numA = double.tryParse(a.split('|')[1].split(' ')[0]) ?? 0;
      final numB = double.tryParse(b.split('|')[1].split(' ')[0]) ?? 0;
      return numB.compareTo(numA);
    });
    return list;
  }
}

// ════════════════════════════════════════════════════════════════════════════
// ALLMANGA CORE
// ════════════════════════════════════════════════════════════════════════════

class AllMangaCore {
  static const String _apiUrl = 'https://api.allanime.day/api';
  static const String _coverServer =
      'https://wp.youtube-anime.com/aln.youtube-anime.com';
  static const String _searchHash =
      '2d48e19fb67ddcac42fbb885204b6abb0a84f406f15ef83f36de4a66f49f651a';
  static const String _detailHash =
      'd77781dcf964b97aea0be621dbde430e89e200b58526823ee6010dd11c3ca96a';

  static const String _chapterQuery =
      r'query($mangaId:String!,$translationType:VaildTranslationTypeMangaEnumType!,$chapterString:String!,$search:SearchInput){chapter(mangaId:$mangaId,translationType:$translationType,chapterString:$chapterString,search:$search){_id pictureUrls pictureUrlHead}}';

  static const Map<String, String> _apiHeaders = {
    'accept': '*/*',
    'origin': 'https://allmanga.to',
    'referer': 'https://allmanga.to/',
    'user-agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  };

  static const Map<String, String> pageHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Referer': 'https://allmanga.to/',
    'Origin': 'https://allmanga.to',
  };

  static const Map<String, String> coverHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Referer': 'https://allmanga.to/',
  };

  static Future<List<AnimeModel>> search(String query) async {
    final variables = {
      'search': {'query': query.trim(), 'isManga': true},
      'limit': 26,
      'page': 1,
      'translationType': 'sub',
      'countryOrigin': 'ALL'
    };
    try {
      _log('search query="$query"');
      final data = await _persistedGet(variables, _searchHash);
      final List edges = data['data']?['mangas']?['edges'] ?? [];
      _log('search returned ${edges.length} results');
      return edges.map((e) => _fromEdge(e)).toList();
    } catch (e) {
      _log('search error: $e');
      return [];
    }
  }

  static Future<List<AnimeModel>> getTrending() => search('');

  static Future<List<String>> getChapters(String mangaId) async {
    try {
      _log('getChapters mangaId=$mangaId');
      final data = await _persistedGet(
          {
            '_id': mangaId,
            'search': {'allowAdult': false, 'allowUnknown': false}
          },
          _detailHash);
      final detail = data['data']?['manga']?['availableChaptersDetail'];
      if (detail == null) {
        _log('getChapters availableChaptersDetail is null');
        return [];
      }
      _log('getChapters detail keys=${(detail as Map).keys.join(", ")}');
      final List raw =
          (detail['sub'] ?? detail['raw'] ?? detail['dub'] ?? []) as List;
      _log('getChapters raw has ${raw.length} chapters');
      final List<String> strList = raw.map((c) => c.toString()).toList();
      strList.sort((a, b) {
        double nA = double.tryParse(a) ?? 0;
        double nB = double.tryParse(b) ?? 0;
        return nB.compareTo(nA);
      });
      _log('getChapters returning ${strList.length} chapters: ${strList.take(5).join(", ")}');
      return strList;
    } catch (e) {
      _log('getChapters error: $e');
      return [];
    }
  }

  static Future<List<String>> getPages(
      String mangaId, String chapterString) async {
    _log('getPages mangaId=$mangaId chapterString=$chapterString');
    final cleanChapter = chapterString.contains('|')
        ? chapterString.split('|')[1].trim()
        : chapterString.trim();
    _log('getPages cleanChapter=$cleanChapter');

    _log('getPages calling _apqGet with translationType=sub');
    final data = await _apqGet({
      'mangaId': mangaId,
      'translationType': 'sub',
      'chapterString': cleanChapter,
      'search': {'allowAdult': true, 'allowUnknown': true},
    }, _chapterQuery);

    if (data == null) {
      _log('getPages _apqGet returned null — all paths failed');
      return [];
    }
    _log('getPages _apqGet returned ${jsonEncode(data).length} chars');

    final chapter = data['data']?['chapter'] as Map<String, dynamic>?;
    if (chapter == null) {
      _log('getPages data.data.chapter is null — response=${jsonEncode(data).substring(0, (jsonEncode(data).length).clamp(0, 500))}');
      return [];
    }
    _log('getPages chapter keys=${chapter.keys.join(", ")}');

    final pictureUrlHead = chapter['pictureUrlHead'] as String? ?? '';
    final pictureUrls = chapter['pictureUrls'] as List? ?? [];
    _log('getPages pictureUrlHead="$pictureUrlHead" pictureUrls.length=${pictureUrls.length}');
    if (pictureUrls.isNotEmpty) {
      _log('getPages first 3 pictureUrls=${pictureUrls.take(3).join(", ")}');
    }

    final allUrls = <String>[];
    for (final url in pictureUrls) {
      final urlStr = url.toString();
      if (urlStr.isEmpty) continue;
      final fullUrl = urlStr.startsWith('http')
          ? urlStr
          : '$pictureUrlHead$urlStr';
      if (!allUrls.contains(fullUrl)) {
        allUrls.add(fullUrl);
      }
    }
    _log('getPages returning ${allUrls.length} URLs');
    if (allUrls.isNotEmpty) {
      _log('getPages first URL=${allUrls.first}');
    }
    return allUrls;
  }

  static Future<Map<String, dynamic>> _persistedGet(
      Map<String, dynamic> variables, String hash) async {
    final extensions = {
      'persistedQuery': {'version': 1, 'sha256Hash': hash}
    };
    final uri = Uri.parse(_apiUrl).replace(queryParameters: {
      'variables': jsonEncode(variables),
      'extensions': jsonEncode(extensions)
    });
    _log('_persistedGet GET $uri');
    _log('_persistedGet variables=${jsonEncode(variables)}');
    final res = await http.get(uri, headers: _apiHeaders);
    _log('_persistedGet status=${res.statusCode}');
    if (res.statusCode == 200) {
      final body = utf8.decode(res.bodyBytes);
      _log('_persistedGet body=${body.substring(0, body.length.clamp(0, 800))}');
      return jsonDecode(body);
    }
    _log('_persistedGet FAILED status=${res.statusCode} body=${utf8.decode(res.bodyBytes)}');
    throw Exception('API Error');
  }

  static String _sha256hex(String input) =>
      sha256.convert(utf8.encode(input)).toString();

  static Future<Map<String, dynamic>?> _apqGet(
      Map<String, dynamic> variables, String queryString) async {
    final hash = _sha256hex(queryString);
    _log('_apqGet queryHash=$hash');
    _log('_apqGet queryString=$queryString');
    _log('_apqGet variables=${jsonEncode(variables)}');
    final extensions = {
      'persistedQuery': {'version': 1, 'sha256Hash': hash}
    };

    final uri = Uri.parse(_apiUrl).replace(queryParameters: {
      'variables': jsonEncode(variables),
      'extensions': jsonEncode(extensions)
    });
    _log('_apqGet GET $uri');

    try {
      final getRes = await http.get(uri, headers: _apiHeaders);
      _log('_apqGet GET status=${getRes.statusCode}');
      if (getRes.statusCode == 200) {
        final body = utf8.decode(getRes.bodyBytes);
        _log('_apqGet GET body=${body.substring(0, body.length.clamp(0, 800))}');
        final data = jsonDecode(body) as Map<String, dynamic>;
        final errors = data['errors'] as List?;
        if (errors != null) {
          _log('_apqGet GET returned errors=${jsonEncode(errors)}');
          for (final err in errors) {
            final ext = err['extensions'] as Map?;
            if (ext != null &&
                ext['code'] == 'PERSISTED_QUERY_NOT_FOUND') {
              _log('_apqGot PERSISTED_QUERY_NOT_FOUND → falling back to POST register');
              return await _apqRegister(variables, queryString, extensions);
            }
          }
          return data;
        }
        _log('_apqGet GET succeeded with data');
        return data;
      }
      _log('_apqGet GET non-200 — falling back to POST register');
    } catch (e) {
      _log('_apqGet GET exception: $e — falling back to POST register');
    }

    return await _apqRegister(variables, queryString, extensions);
  }

  static Future<Map<String, dynamic>?> _apqRegister(
      Map<String, dynamic> variables,
      String queryString,
      Map<String, dynamic> extensions) async {
    _log('_apqRegister POST to $_apiUrl');
    _log('_apqRegister body query=${queryString.substring(0, queryString.length.clamp(0, 300))}...');
    _log('_apqRegister body variables=${jsonEncode(variables)}');
    _log('_apqRegister body extensions=${jsonEncode(extensions)}');
    try {
      final postBody = {
        'query': queryString,
        'variables': variables,
        'extensions': extensions,
      };
      final postRes = await http.post(
        Uri.parse(_apiUrl),
        headers: {
          ..._apiHeaders,
          'Content-Type': 'application/json',
        },
        body: jsonEncode(postBody),
      );
      _log('_apqRegister POST status=${postRes.statusCode}');
      if (postRes.statusCode == 200) {
        final body = utf8.decode(postRes.bodyBytes);
        _log('_apqRegister POST body=${body.substring(0, body.length.clamp(0, 500))}');
        return jsonDecode(body) as Map<String, dynamic>;
      }
      _log('_apqRegister POST failed body="${utf8.decode(postRes.bodyBytes)}"');
    } catch (e) {
      _log('_apqRegister POST exception: $e');
    }
    return null;
  }

  static AnimeModel _fromEdge(Map<String, dynamic> e) {
    String? thumb = e['thumbnail'] as String?;
    if (thumb != null && !thumb.startsWith('http')) {
      thumb =
          '$_coverServer/${thumb.replaceFirst(RegExp(r'^/+'), '').replaceFirst(RegExp(r'\d+(?=\.(jpg|png|webp))'), '001')}?w=250';
    }
    return AnimeModel(
        id: e['_id'] ?? '',
        name: e['englishName'] ?? e['name'] ?? 'Unknown',
        thumbnail: thumb,
        isManga: true,
        sourceId: 'allanime');
  }}