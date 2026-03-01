import 'dart:convert';
import 'package:flutter/foundation.dart';
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

  /// 'en' | 'vi' | 'allanime' | 'mangadex'
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
      thumbUrl = 'https://uploads.mangadex.org/covers/$id/$coverFileName.256.jpg';
    }
    String title = 'Unknown';
    if (attr['title'] is Map) {
      final Map t = attr['title'];
      title = t['en'] ?? (t.isNotEmpty ? t.values.first : 'Unknown');
    }
    return AnimeModel(id: id, name: title, thumbnail: thumbUrl, isManga: true, sourceId: 'mangadex');
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'thumbnail': thumbnail,
    'isManga': isManga,
    'sourceId': sourceId,
  };

  String get fullImageUrl {
    if (thumbnail == null || thumbnail!.isEmpty) return 'https://via.placeholder.com/300x450';
      if (thumbnail!.startsWith('http')) return thumbnail!;
      // Fallback for any legacy data
      return 'https://wp.youtube-anime.com/aln.youtube-anime.com/$thumbnail?w=250';
  }
}

// ════════════════════════════════════════════════════════════════════════════
// MANGA SOURCE PROVIDER
// ════════════════════════════════════════════════════════════════════════════

enum MangaSource { mangadex, allanime }

class MangaSourceProvider extends ChangeNotifier {
  static const _key = 'manga_source';
  MangaSource _source = MangaSource.allanime;

  MangaSource get source => _source;
  bool get isAllManga => _source == MangaSource.allanime;

  MangaSourceProvider() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    _source = raw == 'mangadex' ? MangaSource.mangadex : MangaSource.allanime;
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
// MANGADEX CORE
// ════════════════════════════════════════════════════════════════════════════

class MangaCore {
  static const String _baseUrl = 'https://api.mangadex.org';
  static const Map<String, String> _headers = {'User-Agent': 'AniCli-Flutter/2.3.0'};

  static Future<List<AnimeModel>> getTrending() => search('');

  // Fallback: If AllManga image 404s, try finding a cover on MangaDex
  static Future<String?> findMangaDexCover(String title) async {
    try {
      final results = await search(title);
      if (results.isNotEmpty) return results.first.fullImageUrl;
    } catch (_) {}
    return null;
  }

  static Future<List<AnimeModel>> search(String query) async {
    final sb = StringBuffer('$_baseUrl/manga?limit=20&offset=0');
    if (query.trim().isNotEmpty) sb.write('&title=${Uri.encodeQueryComponent(query.trim())}');
    sb.write('&order[followedCount]=desc&includes[]=cover_art');
    for (final r in ['safe', 'suggestive', 'erotica', 'pornographic']) {
      sb.write('&contentRating[]=$r');
    }
    try {
      final res = await http.get(Uri.parse(sb.toString()), headers: _headers);
      if (res.statusCode == 200) {
        final List results = jsonDecode(res.body)['data'];
        return results.map((e) => AnimeModel.fromMangaDex(e)).toList();
      }
    } catch (_) {}
    return [];
  }

  static Future<List<String>> getChapters(String mangaId) async {
    Future<List<dynamic>> fetch(List<String>? langs) async {
      final sb = StringBuffer('$_baseUrl/manga/$mangaId/feed?limit=500&order[chapter]=desc');
      for (final r in ['safe', 'suggestive', 'erotica', 'pornographic']) {
        sb.write('&contentRating[]=$r');
      }
      if (langs != null) {
        for (final l in langs) sb.write('&translatedLanguage[]=$l');
      }
      try {
        final res = await http.get(Uri.parse(sb.toString()), headers: _headers);
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
      results.add('${c['id']}|${attr['chapter'] ?? 'Oneshot'} [${attr['translatedLanguage'] ?? '??'}]');
    }
    return results;
  }

  static Future<List<String>> getPages(String chapterId) async {
    final realId = chapterId.contains('|') ? chapterId.split('|')[0] : chapterId;
    try {
      final res = await http.get(Uri.parse('$_baseUrl/at-home/server/$realId'), headers: _headers);
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
}

// ════════════════════════════════════════════════════════════════════════════
// ALLMANGA CORE
// ════════════════════════════════════════════════════════════════════════════

class AllMangaCore {
  static bool debugMode = false;

  static const String _apiUrl = 'https://api.allanime.day/api';
  static const String _imageServer = 'https://ytimgf.fast4speed.rsvp';
  static const String _coverServer = 'https://wp.youtube-anime.com/aln.youtube-anime.com';

  static const String _referer = 'https://allmanga.to/';
  static const String _readerRef = 'https://youtu-chan.com/';

  static const String _searchHash = '2d48e19fb67ddcac42fbb885204b6abb0a84f406f15ef83f36de4a66f49f651a';
  static const String _detailHash = 'd77781dcf964b97aea0be621dbde430e89e200b58526823ee6010dd11c3ca96a';
  static const String _pagesHash = 'a062f1b131dae3d17c1950fad14640d066b988ac10347ed49cfbe70f5e7f661b';

  static const Map<String, String> _apiHeaders = {
    'accept': '*/*',
    'origin': 'https://allmanga.to',
    'referer': _referer,
    'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  };

  static const Map<String, String> pageHeaders = {
    'Referer': 'https://youtu-chan.com/',
    'Origin': 'https://youtu-chan.com',
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  };

  static const Map<String, String> coverHeaders = {
    'Referer': 'https://allmanga.to/',
    'Origin': 'https://allmanga.to',
    'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36',
    'sec-ch-ua': '"Not:A-Brand";v="99", "Google Chrome";v="145", "Chromium";v="145"',
    'sec-ch-ua-mobile': '?0',
    'sec-ch-ua-platform': '"Linux"',
  };

  static Future<List<AnimeModel>> search(String query) async {
    final variables = {
      'search': {'query': query.trim(), 'isManga': true},
      'limit': 26,
      'page': 1,
      'translationType': 'sub',
      'countryOrigin': 'ALL',
    };
    try {
      final data = await _persistedGet(variables, _searchHash);
      final List edges = data['data']?['mangas']?['edges'] as List? ?? [];
      return edges.map((e) => _fromEdge(e)).toList();
    } catch (e) {
      if (debugMode) print('AllManga Search Error: $e');
      return [];
    }
  }

  static Future<List<AnimeModel>> getTrending() => search('');

  static Future<List<String>> getChapters(String mangaId) async {
    try {
      final data = await _persistedGet(
        {'_id': mangaId, 'search': {'allowAdult': false, 'allowUnknown': false}},
        _detailHash,
      );
      final detail = data['data']?['manga']?['availableChaptersDetail'];
      if (detail == null) return [];
      final List raw = (detail['sub'] ?? detail['raw'] ?? detail['dub'] ?? []) as List;
      return raw.map((c) => c.toString()).toList().reversed.toList();
    } catch (e) {
      if (debugMode) print('AllManga Chapters Error: $e');
      return [];
    }
  }

  static Future<List<String>> getPages(String mangaId, String chapterString) async {
    final allUrls = <String>[];
    int offset = 0;
    const limit = 50;
    final cleanChapter = chapterString.contains('|') ? chapterString.split('|')[1].trim() : chapterString.trim();

    while (true) {
      try {
        final data = await _persistedGet(
          {
            'mangaId': mangaId,
            'translationType': 'sub',
            'chapterString': cleanChapter,
            'limit': limit,
            'offset': offset
          },
          _pagesHash,
          headers: pageHeaders,
        );

        final allStrings = _extractAllStrings(data);
        final found = allStrings.where((s) => s.contains(mangaId) && s.contains('/') && !s.contains('mcovers')).toList();

        if (found.isEmpty) break;

        bool newAdded = false;
        for (final s in found) {
          String url = s.startsWith('http') ? s : '$_imageServer${s.startsWith('/') ? s : '/$s'}';
          if (!allUrls.contains(url)) {
            allUrls.add(url);
            newAdded = true;
          }
        }
        if (!newAdded) break;
        offset += limit;
      } catch (e) {
        if (debugMode) print('AllManga Pages Error (offset $offset): $e');
        break;
      }
    }
    return allUrls;
  }

  static Future<Map<String, dynamic>> _persistedGet(
    Map<String, dynamic> variables, String hash, {Map<String, String>? headers}) async {
      final extensions = {'persistedQuery': {'version': 1, 'sha256Hash': hash}};
      final uri = Uri.parse(_apiUrl).replace(queryParameters: {
        'variables': jsonEncode(variables),
        'extensions': jsonEncode(extensions),
      });

      final res = await http.get(uri, headers: headers ?? _apiHeaders);
      if (res.statusCode == 200) {
        return jsonDecode(utf8.decode(res.bodyBytes));
      }
      throw Exception('API Error ${res.statusCode}');
    }

    static AnimeModel _fromEdge(Map<String, dynamic> e) {
      String? thumb = e['thumbnail'] as String?;
      if (thumb != null && !thumb.startsWith('http')) {
        final cleanPath = thumb.replaceFirst(RegExp(r'^/+'), '');

        // FIX: Force filename to 001.jpg/png to get the front cover
        final adjustedPath = cleanPath.replaceFirst(RegExp(r'\d+(?=\.(jpg|png|webp))'), '001');

        thumb = '$_coverServer/$adjustedPath?w=250';
      }
      return AnimeModel(
        id: e['_id'] ?? '',
        name: e['name'] ?? e['englishName'] ?? 'Unknown',
        thumbnail: thumb,
        isManga: true,
        sourceId: 'allanime',
      );
    }

    static List<String> _extractAllStrings(dynamic data) {
      final strings = <String>[];
      if (data is Map) {
        for (final v in data.values) strings.addAll(_extractAllStrings(v));
      } else if (data is List) {
        for (final item in data) strings.addAll(_extractAllStrings(item));
      } else if (data is String) {
        strings.add(data);
      }
      return strings;
    }
}
