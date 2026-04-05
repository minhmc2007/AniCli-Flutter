import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'manga.dart' show AnimeModel;

// ════════════════════════════════════════════════════════════════════════════
// ANIME SOURCE ENUM + PROVIDER
// ════════════════════════════════════════════════════════════════════════════

enum AnimeSource { en, vi, hentaivietsub }

extension AnimeSourceX on AnimeSource {
  String get label {
    if (this == AnimeSource.en) return 'English';
    if (this == AnimeSource.vi) return 'Tiếng Việt';
    return 'NSFW (18+)';
  }

  String get description {
    if (this == AnimeSource.en) return 'AllAnime · Sub';
    if (this == AnimeSource.vi) return 'PhimAPI · Vietsub';
    return 'HentaiVietsub · Vietsub';
  }
}

class SourceProvider extends ChangeNotifier {
  static const _key = 'anime_source';
  AnimeSource _source = AnimeSource.en;

  AnimeSource get source => _source;
  bool get isVi => _source == AnimeSource.vi;
  bool get isNSFW => _source == AnimeSource.hentaivietsub;

  SourceProvider() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    if (saved == 'vi') {
      _source = AnimeSource.vi;
    } else if (saved == 'hentaivietsub') {
      _source = AnimeSource.hentaivietsub;
    } else {
      _source = AnimeSource.en;
    }
    notifyListeners();
  }

  Future<void> setSource(AnimeSource s) async {
    _source = s;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, s.name);
    notifyListeners();
  }
}

// ════════════════════════════════════════════════════════════════════════════
// HENTAIVIETSUB CORE (NSFW 18+)
// ════════════════════════════════════════════════════════════════════════════

class HentaiVietsubCore {
  static const String baseUrl = 'https://hentaivietsub.com';
  static const String searchUrl = 'https://hentaivietsub.com/tim-kiem';
  static const String referer = 'https://p1.spexliu.top/';
  static const String userAgent =
  'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36';

  // Match Python headers exactly to prevent blocks
  static const Map<String, String> baseHeaders = {
    'User-Agent': userAgent,
    'Accept':
    'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
    'Accept-Language': 'vi,en-US;q=0.9,en;q=0.8',
  };

  static Future<List<AnimeModel>> getTrending({int page = 1}) async {
    String url = page == 1 ? baseUrl : '$baseUrl/?page=$page';
    return _parseList(url);
  }

  static Future<List<AnimeModel>> search(String query, {int page = 1}) async {
    if (query.trim().isEmpty) return getTrending(page: page);
    String url = '$searchUrl/${Uri.encodeComponent(query.trim())}';
    if (page > 1) url += '?page=$page';
    return _parseList(url);
  }

  static Future<List<AnimeModel>> _parseList(String url) async {
    try {
      final res = await http.get(Uri.parse(url), headers: baseHeaders);
      if (res.statusCode != 200) return[];

      final List<AnimeModel> items =[];
      final parts = res.body.split(RegExp(r'''class=["\']item-box["\'][^>]*>'''));

      for (int i = 1; i < parts.length; i++) {
        final block = parts[i];
        final aMatch =
        RegExp(r'''<a[^>]+href=["\']([^"\']+)["\']''').firstMatch(block);
        final imgMatch =
        RegExp(r'''<img[^>]+src=["\']([^"\']+)["\']''').firstMatch(block);
        final h3Match = RegExp(r'''<h3[^>]*>([\s\S]*?)<\/h3>''').firstMatch(block);

        if (aMatch != null && h3Match != null) {
          String link = aMatch.group(1)!;
          String title =
          h3Match.group(1)!.replaceAll(RegExp(r'<[^>]+>'), '').trim();
          String thumb = imgMatch != null ? imgMatch.group(1)! : '';

          if (!link.startsWith('http')) link = baseUrl + link;

          items.add(AnimeModel(
            id: link,
            name: title,
            thumbnail: thumb.isNotEmpty ? thumb : null,
            isManga: false,
            sourceId: 'hentaivietsub',
          ));
        }
      }
      return items;
    } catch (e) {
      print('HentaiVietsub Parse Error: $e');
      return[];
    }
  }

  // Treat as 1 single video (ignoring episodes as requested)
  static Future<List<String>> getEpisodes(String id) async {
    return ["1"];
  }

  static Future<String?> getStreamUrl(String url, String episodeNum) async {
    try {
      final res = await http.get(Uri.parse(url), headers: baseHeaders);
      if (res.statusCode != 200) return null;

      final videoIdMatch =
      RegExp(r'videos/([a-fA-F0-9]{24})').firstMatch(res.body);
      String? videoId;

      if (videoIdMatch != null) {
        videoId = videoIdMatch.group(1);
      } else {
        final iframeMatch =
        RegExp(r'''<iframe[^>]+src=["\']([^"\']+)["\']''').firstMatch(res.body);
        if (iframeMatch != null) {
          final subMatch =
          RegExp(r'/([a-fA-F0-9]{24})').firstMatch(iframeMatch.group(1)!);
          if (subMatch != null) videoId = subMatch.group(1);
        }
      }

      if (videoId == null) return null;

      final configUrl = 'https://p1.spexliu.top/videos/$videoId/config';

      final apiHeaders = Map<String, String>.from(baseHeaders);
      apiHeaders.addAll({
        'Origin': 'https://p1.spexliu.top',
        'Referer': 'https://p1.spexliu.top/videos/$videoId/play',
        'Content-Type': 'application/json',
      });

      final apiRes = await http.post(Uri.parse(configUrl), headers: apiHeaders);

      if (apiRes.statusCode == 200) {
        final data = jsonDecode(apiRes.body);
        final sources = data['sources'] as List?;
        if (sources != null && sources.isNotEmpty) {
          return sources[0]['file'] as String?;
        }
      }
    } catch (e) {
      print('HentaiVietsub Stream Error: $e');
    }
    return null;
  }
}

// ════════════════════════════════════════════════════════════════════════════
// ANICORE  (allanime.day — English sub/dub)
// ════════════════════════════════════════════════════════════════════════════

class AniCore {
  static const String baseUrl = 'https://api.allanime.day/api';
  static const String referer = 'https://allmanga.to';
  static const String agent =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
  '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  static const String _showQuery = r'''
  query($search: SearchInput, $limit: Int, $page: Int, $translationType: VaildTranslationTypeEnumType, $countryOrigin: VaildCountryOriginEnumType) {
  shows(search: $search, limit: $limit, page: $page, translationType: $translationType, countryOrigin: $countryOrigin) {
  edges { _id name thumbnail }
}
}
''';

static Future<List<AnimeModel>> getTrending({int page = 1}) async {
  final variables = {
    'search': {'allowAdult': false, 'allowUnknown': false, 'sortBy': 'Top'},
    'limit': 40,
    'page': page,
    'translationType': 'sub',
    'countryOrigin': 'ALL',
  };
  try {
    final res = await _post(_showQuery, variables);
    final List edges = res['data']['shows']['edges'];
    return edges.map((e) => AnimeModel.fromJson(e)).toList();
  } catch (e) {
    return[];
  }
}

static Future<List<AnimeModel>> search(String query, {int page = 1}) async {
  final variables = {
    'search': {'allowAdult': false, 'allowUnknown': false, 'query': query},
    'limit': 40,
    'page': page,
    'translationType': 'sub',
    'countryOrigin': 'ALL',
  };
  try {
    final res = await _post(_showQuery, variables);
    final List edges = res['data']['shows']['edges'];
    return edges.map((e) => AnimeModel.fromJson(e)).toList();
  } catch (e) {
    return[];
  }
}

static Future<List<String>> getEpisodes(String animeId) async {
  const String gql = r'''
  query ($showId: String!) {
  show(_id: $showId) { _id availableEpisodesDetail }
}
''';
try {
  final res = await _post(gql, {'showId': animeId});
  final d = res['data']['show']['availableEpisodesDetail'];
  final List details = d['sub'] ?? d['dub'] ?? d['raw'] ??[];
  return details.reversed.map((e) => e.toString()).toList();
} catch (e) {
  return[];
}
}

static Future<String?> getStreamUrl(String animeId, String episodeNum) async {
  const String gql = r'''
  query ($showId: String!, $translationType: VaildTranslationTypeEnumType!, $episodeString: String!) {
  episode(showId: $showId translationType: $translationType episodeString: $episodeString) {
  episodeString sourceUrls
}
}
''';
try {
  final res = await _post(gql, {
    'showId': animeId,
    'translationType': 'sub',
    'episodeString': episodeNum,
  });
  final List sources = res['data']['episode']['sourceUrls'];
  for (final source in sources) {
    String url = source['sourceUrl'] as String;
    if (url.startsWith('--')) {
      final decrypted = _decrypt(url.substring(2));
      if (decrypted.startsWith('http')) {
        return decrypted.replaceFirst('/clock', '/clock.json');
      }
    }
  }
} catch (e) {}
return null;
}

// Changed to use POST with JSON body to bypass Cloudflare block
static Future<Map<String, dynamic>> _post(
  String query, Map<String, dynamic> vars) async {
    final uri = Uri.parse(baseUrl);
    final res = await http.post(
      uri,
      headers: {
        'User-Agent': agent,
        'Referer': referer,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'variables': vars,
        'query': query,
      }),
    );
    if (res.statusCode == 200) return jsonDecode(res.body);
    throw Exception('AniCore API Error ${res.statusCode}');
  }

  static String _decrypt(String input) {
    const Map<String, String> map = {
      '01': '9', '08': '0', '09': '1', '0a': '2', '0b': '3', '0c': '4',
      '0d': '5', '0e': '6', '0f': '7', '00': '8',
      '50': 'h', '51': 'i', '52': 'j', '53': 'k', '54': 'l', '55': 'm',
      '56': 'n', '57': 'o', '58': 'p', '59': 'a', '5a': 'b', '5b': 'c',
      '5c': 'd', '5d': 'e', '5e': 'f', '5f': 'g',
      '60': 'X', '61': 'Y', '62': 'Z', '63': '[', '64': r'\', '65': ']',
      '66': '^', '67': '_', '68': 'P', '69': 'Q', '6a': 'R', '6b': 'S',
      '6c': 'T', '6d': 'U', '6e': 'V', '6f': 'W',
      '70': 'H', '71': 'I', '72': 'J', '73': 'K', '74': 'L', '75': 'M',
      '76': 'N', '77': 'O', '78': '@', '79': 'A', '7a': 'B', '7b': 'C',
      '7c': 'D', '7d': 'E', '7e': 'F', '7f': 'G',
      '40': 'x', '41': 'y', '42': 'z', '48': 'p', '49': 'q', '4a': 'r',
      '4b': 's', '4c': 't', '4d': 'u', '4e': 'v', '4f': 'w',
      '15': '-', '16': '.', '02': ':', '17': '/', '07': '?', '05': '=',
      '12': '*', '13': '+', '14': ',', '03': ';',
    };
    final buf = StringBuffer();
    for (int i = 0; i + 2 <= input.length; i += 2) {
      buf.write(map[input.substring(i, i + 2).toLowerCase()] ?? '');
    }
    return buf.toString();
  }
}

// ════════════════════════════════════════════════════════════════════════════
// VI ANIME CORE  (PhimAPI — Vietsub)
// ════════════════════════════════════════════════════════════════════════════

class ViAnimeCore {
  static const String baseUrl = 'https://phimapi.com';
  static const String cdnImage = 'https://phimimg.com';
  static const String referer = 'https://phimapi.com';

  static const Map<String, String> _headers = {
    'User-Agent': 'AniCli-Flutter/2.0'
  };

  static Future<List<AnimeModel>> getTrending({int page = 1}) => _fetchList(
    '$baseUrl/v1/api/danh-sach/hoat-hinh'
  '?page=$page&country=nhat-ban&limit=40'
  '&sort_field=modified.time&sort_type=desc',
  );

  static Future<List<AnimeModel>> search(String query, {int page = 1}) async {
    if (query.trim().isEmpty) return getTrending(page: page);
    return _fetchList(
      '$baseUrl/v1/api/tim-kiem?keyword=${Uri.encodeQueryComponent(query.trim())}&limit=40&page=$page');
  }

  static Future<List<String>> getEpisodes(String slug) async {
    try {
      final res = await http
      .get(Uri.parse('$baseUrl/phim/$slug'), headers: _headers)
      .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return[];
      final sd = _serverData(jsonDecode(res.body));
      if (sd == null) return[];
      return List.generate(sd.length, (i) => '${i + 1}');
    } catch (e) {
      return[];
    }
  }

  static Future<String?> getStreamUrl(String slug, String episodeNum) async {
    try {
      final idx = int.tryParse(episodeNum) ?? 1;
      final res = await http
      .get(Uri.parse('$baseUrl/phim/$slug'), headers: _headers)
      .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      final sd = _serverData(jsonDecode(res.body));
      if (sd == null) return null;
      return sd[(idx - 1).clamp(0, sd.length - 1)]['link_m3u8'] as String?;
    } catch (e) {
      return null;
    }
  }

  static Future<List<AnimeModel>> _fetchList(String url) async {
    try {
      final res = await http
      .get(Uri.parse(url), headers: _headers)
      .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return [];
      final root = jsonDecode(res.body);
      final inner = root['data'] ?? root;
      final items = inner['items'];
      if (items == null || items is! List) return [];
      final cdn = (inner['APP_DOMAIN_CDN_IMAGE'] as String?) ?? cdnImage;
      return items.map<AnimeModel>((item) {
        String thumb = item['poster_url'] ?? item['thumb_url'] ?? '';
      if (thumb.isNotEmpty && !thumb.startsWith('http')) {
        thumb = thumb.startsWith('/') ? '$cdn$thumb' : '$cdn/$thumb';
      }
      return AnimeModel(
        id: item['slug'] ?? '',
        name: item['name'] ?? 'Unknown',
        thumbnail: thumb.isEmpty ? null : thumb,
        isManga: false,
        sourceId: 'vi',
      );
      }).toList();
    } catch (e) {
      return[];
    }
  }

  static List? _serverData(Map<String, dynamic> data) {
    final episodes = data['episodes'] as List?;
    if (episodes == null || episodes.isEmpty) return null;
    return episodes[0]['server_data'] as List?;
  }
}
