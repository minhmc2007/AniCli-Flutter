import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

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

  factory AnimeModel.fromTruyenQQ(Map<String, dynamic> json) {
    return AnimeModel(
      id: json['slug'] ?? '',
      name: json['name'] ?? 'Unknown',
      thumbnail: json['thumbnail'],
      isManga: true,
      sourceId: 'truyenqq',
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
// HELPERS
// ════════════════════════════════════════════════════════════════════════════

String _decodeHtmlEntities(String text) {
  return text
      .replaceAll('&#39;', "'")
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#x27;', "'")
      .replaceAll('&#x2F;', '/')
      .replaceAllMapped(RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m.group(1)!)));
}

// ════════════════════════════════════════════════════════════════════════════
// MANGA SOURCE PROVIDER
// ════════════════════════════════════════════════════════════════════════════

enum MangaSource { mangadex, zettruyen, weebcentral, truyenqq, en, vi }

class MangaSourceProvider extends ChangeNotifier {
  static const _key = 'manga_source';
  MangaSource _source = MangaSource.mangadex;
  bool _loaded = false;

  MangaSource get source => _source;
  bool get isMangaDex => _source == MangaSource.mangadex;
  bool get isZetTruyen => _source == MangaSource.zettruyen;
  bool get isWeebCentral => _source == MangaSource.weebcentral;
  bool get isTruyenQQ => _source == MangaSource.truyenqq;
  bool get isEn => _source == MangaSource.en;
  bool get isVi => _source == MangaSource.vi;

  MangaSourceProvider() {
    _load();
  }

  Future<void> _load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    if (_loaded) return;
    final raw = prefs.getString(_key);
    if (_loaded) return;
    if (raw == 'zettruyen') {
      _source = MangaSource.zettruyen;
    } else if (raw == 'weebcentral') {
      _source = MangaSource.weebcentral;
    } else if (raw == 'truyenqq') {
      _source = MangaSource.truyenqq;
    } else if (raw == 'en') {
      _source = MangaSource.en;
    } else if (raw == 'vi') {
      _source = MangaSource.vi;
    } else {
      _source = MangaSource.mangadex;
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> setSource(MangaSource s) async {
    _source = s;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, s.name);
    notifyListeners();
  }
}

// ════════════════════════════════════════════════════════════════════════════
// ZETTRUYEN CORE
// ════════════════════════════════════════════════════════════════════════════

class ZetTruyenCore {
  static const String _baseUrl = 'https://www.zettruyen.ink';

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

  static Future<List<AnimeModel>> getTrending() async {
    final results = <AnimeModel>[];
    try {
      final res = await http.get(Uri.parse(_baseUrl), headers: _htmlHeaders);
      if (res.statusCode == 200) {
        final html = res.body;
        final topWeekStart = html.indexOf('data-category="top_week"');
        if (topWeekStart == -1) return results;
        final topMonthStart = html.indexOf('data-category="top_month"', topWeekStart);
        final section = topMonthStart > topWeekStart
            ? html.substring(topWeekStart, topMonthStart)
            : html.substring(topWeekStart);
        final entryPattern = RegExp(
            r'href="/truyen-tranh/([^"]+)"\s*title="([^"]*)"[^>]*>'
            r'\s*<img\s+alt="[^"]*"\s+[^>]*src="([^"]+)"',
            caseSensitive: false);
        for (final m in entryPattern.allMatches(section)) {
          final slug = m.group(1)!;
          final name = _decodeHtmlEntities(m.group(2)!.trim());
          var cover = m.group(3)!;
          if (cover.startsWith('/')) cover = '$_baseUrl$cover';
          results.add(AnimeModel(
            id: slug,
            name: name,
            thumbnail: cover,
            isManga: true,
            sourceId: 'zettruyen',
          ));
        }
      }
    } catch (_) {}
    return results;
  }

  static Future<List<AnimeModel>> browse({int page = 1, int perPage = 20}) async {
    try {
      final res = await http.get(
          Uri.parse('$_baseUrl/tim-kiem-nang-cao?page=$page&limit=$perPage'),
          headers: _htmlHeaders);
      if (res.statusCode == 200) {
        return _parseBrowse(res.body);
      }
    } catch (_) {}
    return [];
  }

  static List<AnimeModel> _parseBrowse(String html) {
    final results = <AnimeModel>[];
    final entryPattern = RegExp(
        r'href="/truyen-tranh/([^"]+)"\s*title="([^"]*)"[^>]*>'
        r'\s*<img\s+[^>]*src="([^"]+)"',
        caseSensitive: false);
    for (final m in entryPattern.allMatches(html)) {
      final slug = m.group(1)!;
      final name = _decodeHtmlEntities(m.group(2)!.trim());
      var cover = m.group(3)!;
      if (cover.startsWith('/')) cover = '$_baseUrl$cover';
      results.add(AnimeModel(
        id: slug,
        name: name,
        thumbnail: cover,
        isManga: true,
        sourceId: 'zettruyen',
      ));
    }
    return results;
  }

  static Future<List<AnimeModel>> search(String query) async {
    if (query.trim().isEmpty) return getTrending();
    try {
      debugPrint('[ZetTruyen] search q=$query');
      final res = await http.get(
          Uri.parse(
              '$_baseUrl/api/quick-search?q=${Uri.encodeQueryComponent(query.trim())}'),
          headers: _apiHeaders);
      debugPrint('[ZetTruyen] search status=${res.statusCode} body=${res.body.substring(0, res.body.length.clamp(0, 1000))}');
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
      debugPrint('[ZetTruyen] GET chapters $mangaSlug');
      final res = await http.get(
          Uri.parse(
              '$_baseUrl/api/comics/$mangaSlug/chapters?per_page=-1&order=desc'),
          headers: _apiHeaders);
      debugPrint('[ZetTruyen] chapters status=${res.statusCode}');
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
            RegExp("(https?://[^\"' ]*(?:zetimage\\.com)[^\"' ]*)");
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
    final url = sb.toString();
    debugPrint('[MangaCore] search url=$url');
    try {
      final res =
          await http.get(Uri.parse(url), headers: _headers);
      debugPrint('[MangaCore] search status=${res.statusCode}');
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final List results = body['data'] ?? [];
        debugPrint('[MangaCore] search got ${results.length} results');
        return results.map((e) => AnimeModel.fromMangaDex(e)).toList();
      } else {
        debugPrint('[MangaCore] search body=${res.body.substring(0, res.body.length.clamp(0, 300))}');
      }
    } catch (e) {
      debugPrint('[MangaCore] search error: $e');
    }
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

  static Future<int> countENChapters(String mangaId) async {
    try {
      final res = await http.get(
          Uri.parse(
              '$_baseUrl/manga/$mangaId/feed?limit=1&order[chapter]=desc&translatedLanguage[]=en'),
          headers: _headers);
      if (res.statusCode == 200) {
        return jsonDecode(res.body)['total'] ?? 0;
      }
    } catch (_) {}
    return 0;
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
// WEBCENTRAL CORE
// ════════════════════════════════════════════════════════════════════════════

class WeebCentralCore {
  static const String _baseUrl = 'https://weebcentral.com';

  static const Map<String, String> _headers = {
    'accept':
        'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8,application/json',
    'accept-language': 'en-US,en;q=0.5',
    'referer': 'https://google.com',
    'user-agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:133.0) Gecko/20100101 Firefox/133.0',
    'dnt': '1',
    'connection': 'keep-alive',
  };

  static Future<List<AnimeModel>> getTrending() async {
    try {
      debugPrint('[WeebCentral] GET $_baseUrl');
      final res = await http.get(Uri.parse(_baseUrl), headers: _headers);
      debugPrint('[WeebCentral] status=${res.statusCode}');
      if (res.statusCode == 200) {
        debugPrint('[WeebCentral] body=${res.body.substring(0, res.body.length.clamp(0, 500))}');
        final parsed = _parseHomepage(res.body);
        debugPrint('[WeebCentral] parsed ${parsed.length} results');
        return parsed;
      }
    } catch (e) {
      debugPrint('[WeebCentral] error: $e');
    }
    return [];
  }

  static Future<List<AnimeModel>> search(String query) async {
    if (query.trim().isEmpty) return getTrending();
    final url =
        '$_baseUrl/search/data?text=${Uri.encodeQueryComponent(query.trim())}&limit=24&offset=0&sort=Best+Match&order=Descending&official=Any&anime=Any&adult=Any&display_mode=Full+Display';
    try {
      debugPrint('[WeebCentral] search url=$url');
      final res = await http.get(Uri.parse(url), headers: _headers);
      debugPrint('[WeebCentral] search status=${res.statusCode}');
      if (res.statusCode == 200) {
        debugPrint('[WeebCentral] search body=${res.body.substring(0, res.body.length.clamp(0, 500))}');
        final parsed = _parseSearch(res.body);
        debugPrint('[WeebCentral] search parsed ${parsed.length} results');
        return parsed;
      }
    } catch (e) {
      debugPrint('[WeebCentral] search error: $e');
    }
    return [];
  }

  static List<AnimeModel> _parseHomepage(String html) {
    final results = <AnimeModel>[];
    // Split by article.bg-base-300 to get individual entries
    final articles = html.split('<article class="bg-base-300');
    for (int i = 1; i < articles.length; i++) {
      final article = articles[i];
      final idMatch = RegExp(r'/series/([^"/]+)').firstMatch(article);
      if (idMatch == null) continue;
      final id = idMatch.group(1)!;
      final altMatch = RegExp(r'alt="([^"]+)\s*cover"').firstMatch(article);
      final name = altMatch != null ? _decodeHtmlEntities(altMatch.group(1)!.trim()) : 'Unknown';
      final coverMatch = RegExp(r'<source\s+srcset="([^"]+)"').firstMatch(article);
      results.add(AnimeModel(
        id: id,
        name: name,
        thumbnail: coverMatch?.group(1),
        isManga: true,
        sourceId: 'weebcentral',
      ));
    }
    return results;
  }

  static List<AnimeModel> _parseSearch(String html) {
    final results = <AnimeModel>[];
    final articles = html.split('<article class="bg-base-300');
    for (int i = 1; i < articles.length; i++) {
      final article = articles[i];
      final idMatch = RegExp(r'/series/([^"/]+)').firstMatch(article);
      if (idMatch == null) continue;
      final id = idMatch.group(1)!;
      final altMatch = RegExp(r'alt="([^"]+)"').firstMatch(article);
      String name = 'Unknown';
      if (altMatch != null) {
        name = altMatch.group(1)!.replaceAll(RegExp(r'\s*cover$'), '').trim();
        name = _decodeHtmlEntities(name);
      }
      final coverMatch = RegExp(r'<source\s+srcset="([^"]+)"').firstMatch(article);
      results.add(AnimeModel(
        id: id,
        name: name,
        thumbnail: coverMatch?.group(1),
        isManga: true,
        sourceId: 'weebcentral',
      ));
    }
    return results;
  }

  static Future<List<String>> getChapters(String mangaId) async {
    final url = '$_baseUrl/series/$mangaId';
    try {
      debugPrint('[WeebCentral] chapters url=$url');
      final res = await http.get(Uri.parse(url), headers: _headers);
      debugPrint('[WeebCentral] chapters status=${res.statusCode}');
      if (res.statusCode == 200) {
        return _parseChapters(res.body);
      }
    } catch (e) {
      debugPrint('[WeebCentral] chapters error: $e');
    }
    return [];
  }

  static List<String> _parseChapters(String html) {
    final results = <String>[];
    final parts = html.split('chapters/');
    for (int i = 1; i < parts.length; i++) {
      final part = parts[i];
      final idMatch = RegExp(r'^([^"<>\s]+)').firstMatch(part);
      if (idMatch == null) continue;
      final id = idMatch.group(1)!.trim();
      final spanMatch = RegExp(r'<span[^>]*class="grow[^"]*"[^>]*>.*?<span[^>]*>([^<]+)</span>', dotAll: true).firstMatch(part);
      if (spanMatch == null) continue;
      final label = spanMatch.group(1)!.trim();
      final numMatch = RegExp(r'(\d+[\.\d]*)').firstMatch(label);
      if (numMatch == null) continue;
      final num = numMatch.group(1)!.trim();
      results.add('$id|$label|$num');
    }
    return results;
  }

  static Future<List<String>> getPages(String mangaId, String chapterString) async {
    final chapterId = chapterString.contains('|')
        ? chapterString.split('|')[0].trim()
        : chapterString.trim();
    final url =
        '$_baseUrl/chapters/$chapterId/images?is_prev=False&current_page=1&reading_style=long_strip';
    try {
      final res = await http.get(Uri.parse(url), headers: _headers);
      if (res.statusCode == 200) {
        return _parsePageImages(res.body);
      }
    } catch (_) {}
    return [];
  }

  static List<String> _parsePageImages(String html) {
    final results = <String>[];
    final imgRegex = RegExp(r'<img\s+[^>]*src="(https://[^"]+)"');
    for (final m in imgRegex.allMatches(html)) {
      final url = m.group(1)!;
      if (!results.contains(url)) results.add(url);
    }
    return results;
  }

  static Future<int> countChapters(String mangaId) async {
    try {
      final res = await http.get(
          Uri.parse('$_baseUrl/series/$mangaId'), headers: _headers);
      if (res.statusCode == 200) {
        return RegExp(r'chapters/').allMatches(res.body).length;
      }
    } catch (_) {}
    return 0;
  }
}

// ════════════════════════════════════════════════════════════════════════════
// EN MANGA AGGREGATOR (MangaDex + WeebCentral)
// ════════════════════════════════════════════════════════════════════════════

class EnMangaCore {
  static Future<List<AnimeModel>> getTrending() => _searchMangaDex('');

  static Future<List<AnimeModel>> search(String query) async {
    if (query.trim().isEmpty) return getTrending();
    final results = await Future.wait([
      _searchMangaDex(query.trim()),
      WeebCentralCore.search(query.trim()),
    ]);
    return _merge(results[0], results[1]);
  }

  static Future<List<AnimeModel>> _searchMangaDex(String query) async {
    final sb = StringBuffer(
        'https://api.mangadex.org/manga?limit=20&offset=0&availableTranslatedLanguage[]=en');
    if (query.isNotEmpty) {
      sb.write('&title=${Uri.encodeQueryComponent(query)}');
    }
    sb.write('&order[followedCount]=desc&includes[]=cover_art');
    for (final r in ['safe', 'suggestive', 'erotica', 'pornographic']) {
      sb.write('&contentRating[]=$r');
    }
    try {
      final res = await http
          .get(Uri.parse(sb.toString()), headers: MangaCore._headers);
      if (res.statusCode == 200) {
        final List items = jsonDecode(res.body)['data'] ?? [];
        return items.map((e) => AnimeModel.fromMangaDex(e)).toList();
      }
    } catch (_) {}
    return [];
  }

  static String _normalize(String s) {
    return s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  static List<AnimeModel> _merge(
      List<AnimeModel> dex, List<AnimeModel> wc) {
    final byKey = <String, List<AnimeModel>>{};
    for (final m in dex) {
      byKey.putIfAbsent(_normalize(m.name), () => []).add(m);
    }
    for (final m in wc) {
      final key = _normalize(m.name);
      if (!byKey.containsKey(key)) {
        byKey[key] = [m];
      } else {
        byKey[key]!.add(m);
      }
    }
    final result = <AnimeModel>[];
    for (final entry in byKey.entries) {
      final list = entry.value;
      if (list.length == 1) {
        result.add(list[0]);
      } else {
        final dexManga = list.firstWhere((m) => m.sourceId == 'mangadex',
            orElse: () => list[0]);
        result.add(dexManga);
      }
    }
      return result;
  }
}

// ════════════════════════════════════════════════════════════════════════════
// VI MANGA AGGREGATOR (ZetTruyen + TruyenQQ)
// ════════════════════════════════════════════════════════════════════════════

class ViMangaCore {
  static Future<List<AnimeModel>> getTrending() async {
    final results = await Future.wait([
      ZetTruyenCore.getTrending(),
      TruyenQQCore.getTrending(),
    ]);
    return _merge(results[0], results[1]);
  }

  static Future<List<AnimeModel>> search(String query) async {
    if (query.trim().isEmpty) return getTrending();
    final results = await Future.wait([
      ZetTruyenCore.search(query.trim()),
      TruyenQQCore.search(query.trim()),
    ]);
    return _merge(results[0], results[1]);
  }

  static String _normalize(String s) {
    return s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  static List<AnimeModel> _merge(
      List<AnimeModel> zet, List<AnimeModel> qq) {
    final byKey = <String, List<AnimeModel>>{};
    for (final m in zet) {
      byKey.putIfAbsent(_normalize(m.name), () => []).add(m);
    }
    for (final m in qq) {
      final key = _normalize(m.name);
      if (!byKey.containsKey(key)) {
        byKey[key] = [m];
      } else {
        byKey[key]!.add(m);
      }
    }
    final result = <AnimeModel>[];
    for (final entry in byKey.entries) {
      final list = entry.value;
      if (list.length == 1) {
        result.add(list[0]);
      } else {
        result.add(list.firstWhere((m) => m.sourceId == 'truyenqq',
            orElse: () => list[0]));
      }
    }
    return result;
  }
}

// ════════════════════════════════════════════════════════════════════════════
// TRUYENQQ CORE
// ════════════════════════════════════════════════════════════════════════════

class TruyenQQCore {
  static const String _baseUrl = 'https://truyenqq.com.vn';

  static const Map<String, String> _headers = {
    'accept':
        'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
    'accept-language': 'vi,en-US;q=0.9,en;q=0.8',
    'user-agent':
        'Mozilla/5.0 (Linux; Android 6.0; Nexus 5 Build/MRA58N) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Mobile Safari/537.36',
  };

  static Future<List<AnimeModel>> getTrending() async {
    final results = <AnimeModel>[];
    try {
      final res = await http.get(Uri.parse(_baseUrl), headers: _headers);
      if (res.statusCode == 200) {
        final html = res.body;
        final storyStart = html.indexOf('id="contentstory"');
        if (storyStart == -1) return results;
        final innerStart = html.indexOf('<div class="inner">', storyStart);
        if (innerStart == -1) return results;
        final section = html.substring(innerStart);
        final items = section.split('<div class="item">');
        for (int i = 1; i < items.length; i++) {
          final item = items[i];
          final slugMatch = RegExp(r'href="/([^"]+)"').firstMatch(item);
          if (slugMatch == null) continue;
          final slug = slugMatch.group(1)!;
          final srcMatch = RegExp(r'src="([^"]+)"').firstMatch(item);
          final nameMatch = RegExp(r'alt="([^"]*)"').firstMatch(item);
          final name = nameMatch != null ? _decodeHtmlEntities(nameMatch.group(1)!.trim()) : 'Unknown';
          var cover = srcMatch?.group(1) ?? '';
          if (cover.isNotEmpty && !cover.startsWith('http')) cover = '$_baseUrl$cover';
          results.add(AnimeModel(
            id: slug,
            name: name,
            thumbnail: cover.isNotEmpty ? cover : null,
            isManga: true,
            sourceId: 'truyenqq',
          ));
        }
      }
    } catch (_) {}
    return results;
  }

  static Future<List<AnimeModel>> search(String query) async {
    if (query.trim().isEmpty) return getTrending();
    final results = <AnimeModel>[];
    try {
      final res = await http.get(
          Uri.parse(
              '$_baseUrl/tim-kiem?s=${Uri.encodeQueryComponent(query.trim())}'),
          headers: _headers);
      if (res.statusCode == 200) {
        final html = res.body;
        final listingStart = html.indexOf('<div class="listing">');
        if (listingStart == -1) return results;
        final listingEnd = html.indexOf('<div class="pagination"', listingStart);
        final section = listingEnd > listingStart
            ? html.substring(listingStart, listingEnd)
            : html.substring(listingStart);
        final items = section.split('<div class="item">');
        for (int i = 1; i < items.length; i++) {
          final item = items[i];
          final slugMatch = RegExp(r'href="/([^"]+)"').firstMatch(item);
          if (slugMatch == null) continue;
          final slug = slugMatch.group(1)!;
          final srcMatch = RegExp(r'src="([^"]+)"').firstMatch(item);
          final nameMatch = RegExp(r'<h3>\s*<a[^>]*>([^<]+)</a>').firstMatch(item);
          final name = nameMatch != null ? _decodeHtmlEntities(nameMatch.group(1)!.trim()) : 'Unknown';
          var cover = srcMatch?.group(1) ?? '';
          if (cover.isNotEmpty && !cover.startsWith('http')) cover = '$_baseUrl$cover';
          results.add(AnimeModel(
            id: slug,
            name: name,
            thumbnail: cover.isNotEmpty ? cover : null,
            isManga: true,
            sourceId: 'truyenqq',
          ));
        }
      }
    } catch (_) {}
    return results;
  }

  static Future<List<String>> getChapters(String mangaSlug) async {
    final results = <String>[];
    try {
      final res = await http.get(
          Uri.parse('$_baseUrl/$mangaSlug'), headers: _headers);
      if (res.statusCode == 200) {
        final html = res.body;
        final listStart = html.indexOf('<div id="chapter-list"');
        if (listStart == -1) return results;
        final chapterRegex = RegExp(
            r'<a\s+href="/([^"]+)"\s+class="chapter-name[^"]*"[^>]*>([^<]+)</a>',
            caseSensitive: false);
        for (final m in chapterRegex.allMatches(html, listStart)) {
          final chapterSlug = m.group(1)!;
          final chapterName = _decodeHtmlEntities(m.group(2)!.trim());
          final numMatch = RegExp(r'[\d.]+').firstMatch(chapterName);
          final num = numMatch?.group(0) ?? '0';
          results.add('$chapterSlug|$chapterName|$num');
        }
      }
    } catch (_) {}
    return results;
  }

  static Future<List<String>> getPages(
      String mangaSlug, String chapterString) async {
    final chapterSlug = chapterString.contains('|')
        ? chapterString.split('|')[0].trim()
        : chapterString.trim();
    final results = <String>[];
    try {
      final res = await http.get(
          Uri.parse('$_baseUrl/$chapterSlug'), headers: _headers);
      if (res.statusCode == 200) {
        final html = res.body;
        final imgRegex = RegExp(r'<img\s+[^>]*src="(https://[^"]+\.(jpg|png|webp)[^"]*)"');
        for (final m in imgRegex.allMatches(html)) {
          final url = m.group(1)!;
          if (!results.contains(url)) results.add(url);
        }
      }
    } catch (_) {}
    return results;
  }
}

// ════════════════════════════════════════════════════════════════════════════
// THUMBNAIL CACHE
// ════════════════════════════════════════════════════════════════════════════

Future<void> precacheThumbnails(List<AnimeModel> items) async {
  final mgr = DefaultCacheManager();
  for (final item in items) {
    final url = item.fullImageUrl;
    if (!url.startsWith('http')) continue;
    try {
      Map<String, String>? headers;
      if (url.contains('zetimage.com')) {
        headers = {'referer': 'https://www.zettruyen.ink/'};
      } else if (url.contains('static3t.com')) {
        headers = {'referer': 'https://truyenqq.com.vn/'};
      }
      await mgr.getSingleFile(url, headers: headers);
    } catch (_) {}
  }
}

