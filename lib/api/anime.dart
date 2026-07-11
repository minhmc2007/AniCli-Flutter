import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;

import 'manga.dart' show AnimeModel;
import 'providers/provider_base.dart';
import 'providers/senshi_provider.dart';
import 'providers/anipub_provider.dart';
import 'providers/anineko_provider.dart';
import 'providers/allanime_provider.dart';
import 'providers/animepahe_provider.dart';

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
  static const String referer = 'https://hentaivietsub.com/';
  static const String userAgent =
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36';

  static const Map<String, String> baseHeaders = {
    'User-Agent': userAgent,
    'Accept':
        'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
    'Accept-Language': 'vi,en-US;q=0.9,en;q=0.8',
  };

  static Future<List<AnimeModel>> getTrending({int page = 1}) async {
    final url = page == 1 ? baseUrl : '$baseUrl/?page=$page';
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
      if (res.statusCode != 200) return [];

      final List<AnimeModel> items = [];
      final parts =
          res.body.split(RegExp(r'''class=["']item-box["'][^>]*>'''));

      for (int i = 1; i < parts.length; i++) {
        final block = parts[i];
        final aMatch =
            RegExp(r'''<a[^>]+href=["']([^"']+)["']''').firstMatch(block);
        final imgMatch =
            RegExp(r'''<img[^>]+src=["']([^"']+)["']''').firstMatch(block);
        final h3Match =
            RegExp(r'''<h3[^>]*>([\s\S]*?)<\/h3>''').firstMatch(block);

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
      return [];
    }
  }

  static Future<List<String>> getEpisodes(String id) async {
    return ['1'];
  }

  static Future<String?> getStreamUrl(String url, String episodeNum) async {
    try {
      final res = await http.get(Uri.parse(url), headers: baseHeaders);
      if (res.statusCode != 200) return null;

      String? videoId;
      final srcMatches =
          RegExp(r'''data-source=["']([^"']*videos/([a-fA-F0-9]{24}))["']''')
              .allMatches(res.body);
      for (final m in srcMatches) {
        videoId = m.group(2);
        if (videoId != null) break;
      }

      if (videoId == null) {
        final fallback = RegExp(r'videos/([a-fA-F0-9]{24})').firstMatch(res.body);
        if (fallback != null) videoId = fallback.group(1);
      }

      if (videoId == null) return null;

      const cdnHosts = ['e.streamforester.com', 'byzamlan.top'];
      const configHeaders = <String, String>{
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Content-Type': 'application/json',
        'Referer': 'https://hentaivietsub.com/',
        'Origin': 'https://hentaivietsub.com',
        'Accept': 'application/json, text/plain, */*',
      };
      for (final host in cdnHosts) {
        try {
          final configUrl =
              'https://$host/videos/$videoId/config?d=hentaivietsub.com';
          final client = http.Client();
          try {
            var res = await client.post(Uri.parse(configUrl), headers: configHeaders);
            var body = res.body;
            var code = res.statusCode;
            for (var i = 0; i < 5 && (code == 301 || code == 302 || code == 303 || code == 307 || code == 308); i++) {
              final loc = res.headers['location'];
              if (loc == null) break;
              res = await client.post(Uri.parse(loc), headers: configHeaders);
              body = res.body;
              code = res.statusCode;
            }
            if (code == 200) {
              final data = jsonDecode(body);
              final sources = data['sources'] as List?;
              if (sources != null && sources.isNotEmpty) {
                final file = sources[0]['file'] as String?;
                if (file != null) return file;
              }
            }
          } finally {
            client.close();
          }
        } catch (_) {
          continue;
        }
      }
    } catch (e) {
      debugPrint('HentaiVietsubCore stream error: $e');
    }
    return null;
  }
}

// ════════════════════════════════════════════════════════════════════════════
// ANICORE (allanime.day — English sub/dub)
// ════════════════════════════════════════════════════════════════════════════

class AniCore {
  static const String baseUrl = 'https://api.allanime.day/api';
  static const String referer = 'https://youtu-chan.com';
  static const String agent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  static const String _aesKeySource = 'Xot36i3lK3:v1';

  static const String _showQuery = r'''
query($search: SearchInput, $limit: Int, $page: Int, $translationType: VaildTranslationTypeEnumType, $countryOrigin: VaildCountryOriginEnumType) {
  shows(search: $search, limit: $limit, page: $page, translationType: $translationType, countryOrigin: $countryOrigin) {
    edges { _id name thumbnail }
  }
}
''';

  static Future<List<AnimeModel>> getTrending({int page = 1}) async {
    final variables = {
      'search': {'allowAdult': true, 'allowUnknown': true, 'sortBy': 'Top'},
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
      return [];
    }
  }

  static Future<List<AnimeModel>> search(String query, {int page = 1}) async {
    final variables = {
      'search': {'allowAdult': true, 'allowUnknown': true, 'query': query},
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
      return [];
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
      final List details = d['sub'] ?? d['dub'] ?? d['raw'] ?? [];
      return details.reversed.map((e) => e.toString()).toList();
    } catch (e) {
      return [];
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

      var dataObj = res['data'];
      if (dataObj == null) return null;

      if (dataObj is Map && dataObj.containsKey('tobeparsed')) {
        final blob = dataObj['tobeparsed'] as String;
        final decryptedStr = _decodeTobeparsed(blob);
        try {
          dataObj = jsonDecode(decryptedStr);
        } catch (_) {}
      }

      var episodeData = dataObj['episode'];
      if (episodeData == null &&
          dataObj is Map &&
          dataObj.containsKey('sourceUrls')) {
        episodeData = dataObj;
      }
      if (episodeData == null) return null;

      final rawSources = episodeData['sourceUrls'];
      List<dynamic> sources = [];
      if (rawSources is List) {
        sources = rawSources;
      } else if (rawSources is String) {
        try {
          sources = jsonDecode(rawSources);
        } catch (_) {}
      }

      List<dynamic> parsedSources = [];
      for (final s in sources) {
        if (s is Map && s.containsKey('tobeparsed')) {
          final blob = s['tobeparsed'] as String;
          final decrypted = _decodeTobeparsed(blob);
          try {
            final decSources = jsonDecode(decrypted);
            if (decSources is List) {
              parsedSources.addAll(decSources);
            } else if (decSources is Map) {
              parsedSources.add(decSources);
            }
          } catch (_) {}
        } else {
          parsedSources.add(s);
        }
      }

      // First pass: try clock URLs (best quality, multi-resolution HLS)
      for (final source in parsedSources) {
        if (source is! Map) continue;
        String? url = source['sourceUrl'] as String?;
        if (url == null) continue;
        if (url.startsWith('--')) url = decrypt(url.substring(2));
        if (!url.contains('/clock')) continue;

        final clockUrl = url.replaceFirst('/clock?', '/clock.json?');
        try {
          final clockRes = await http.get(Uri.parse(clockUrl), headers: {
            'User-Agent': agent,
            'Referer': 'https://youtu-chan.com',
          });
          if (clockRes.statusCode == 200) {
            final clockData = jsonDecode(clockRes.body);
            final links = clockData['links'] as List?;
            if (links != null && links.isNotEmpty) {
              final link = links[0]['link'] as String?;
              if (link != null) return link;
            }
          }
        } catch (e) {
          debugPrint('AniCore clock.json error: $e');
        }
      }

      // Second pass: return first direct HTTP URL
      for (final source in parsedSources) {
        if (source is! Map) continue;
        String? url = source['sourceUrl'] as String?;
        if (url == null) continue;
        if (url.startsWith('--')) url = decrypt(url.substring(2));
        if (url.startsWith('http')) return url;
      }
    } catch (e) {
      debugPrint('AniCore.getStreamUrl error: $e');
    }
    return null;
  }

  static String _decodeTobeparsed(String blob) {
    try {
      final keyHash = sha256.convert(utf8.encode(_aesKeySource)).bytes;
      final key = encrypt.Key(Uint8List.fromList(keyHash));

      final raw = base64.decode(blob);
      if (raw.length < 14) return '{}';

      // IV = bytes[1..12] (12 bytes, skip version byte at [0])
      final iv12 = raw.sublist(1, 13);
      // ciphertext = bytes[13..(length-16)] (skip 12-byte nonce + 16-byte GCM tag)
      final ctLen = raw.length - 13 - 16;
      if (ctLen <= 0) return '{}';
      final ciphertextBytes = raw.sublist(13, 13 + ctLen);

      final ctrIv = Uint8List(16);
      ctrIv.setAll(0, iv12);
      ctrIv[12] = 0;
      ctrIv[13] = 0;
      ctrIv[14] = 0;
      ctrIv[15] = 2;

      final iv = encrypt.IV(ctrIv);
      final encrypter = encrypt.Encrypter(
        encrypt.AES(key, mode: encrypt.AESMode.ctr, padding: null),
      );

      return encrypter.decrypt(
        encrypt.Encrypted(ciphertextBytes),
        iv: iv,
      );
    } catch (e) {
      debugPrint('_decodeTobeparsed error: $e');
      return '{}';
    }
  }

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

  static String decrypt(String input) {
    const Map<String, String> map = {
      '01': '9', '08': '0', '09': '1', '0a': '2', '0b': '3', '0c': '4',
      '0d': '5', '0e': '6', '0f': '7', '00': '8',
      '50': 'h', '51': 'i', '52': 'j', '53': 'k', '54': 'l', '55': 'm',
      '56': 'n', '57': 'o', '58': 'p', '59': 'a', '5a': 'b', '5b': 'c',
      '5c': 'd', '5d': 'e', '5e': 'f', '5f': 'g',
      '60': 'X', '61': 'Y', '62': 'Z', '63': '[', '64': r'\',
      '65': ']', '66': '^', '67': '_', '68': 'P', '69': 'Q',
      '6a': 'R', '6b': 'S', '6c': 'T', '6d': 'U', '6e': 'V', '6f': 'W',
      '70': 'H', '71': 'I', '72': 'J', '73': 'K', '74': 'L', '75': 'M',
      '76': 'N', '77': 'O', '78': '@', '79': 'A', '7a': 'B', '7b': 'C',
      '7c': 'D', '7d': 'E', '7e': 'F', '7f': 'G',
      '40': 'x', '41': 'y', '42': 'z', '48': 'p', '49': 'q', '4a': 'r',
      '4b': 's', '4c': 't', '4d': 'u', '4e': 'v', '4f': 'w',
      '15': '-', '16': '.', '02': ':', '17': '/', '07': '?', '05': '=',
      '12': '*', '13': '+', '14': ',', '03': ';',
      '1b': '#', '46': '~', '19': '!', '1c': r'$', '1e': '&',
      '10': '(', '11': ')', '1d': '%',
    };
    final buf = StringBuffer();
    for (int i = 0; i + 2 <= input.length; i += 2) {
      buf.write(map[input.substring(i, i + 2).toLowerCase()] ?? '');
    }
    return buf.toString();
  }
}

// ════════════════════════════════════════════════════════════════════════════
// VI ANIME CORE (OPhim — Vietsub, anime-focused)
// ════════════════════════════════════════════════════════════════════════════

class ViAnimeCore {
  static const String baseUrl = 'https://ophim1.com';
  static const String cdnImage = 'https://phimimg.com';
  static const String referer = 'https://ophim1.com';

  static const Map<String, String> _headers = {
    'User-Agent': 'AniCli-Flutter/2.0',
  };

  static Future<List<AnimeModel>> getTrending({int page = 1}) =>
      _fetchList(
        '$baseUrl/v1/api/danh-sach/hoat-hinh'
        '?page=$page&country=nhat-ban&limit=40'
        '&sort_field=modified.time&sort_type=desc',
      );

  static Future<List<AnimeModel>> search(String query,
      {int page = 1}) async {
    if (query.trim().isEmpty) return getTrending(page: page);
    return _fetchList(
      '$baseUrl/v1/api/tim-kiem'
      '?keyword=${Uri.encodeQueryComponent(query.trim())}&limit=40&page=$page',
    );
  }

  static Future<List<String>> getEpisodes(String slug) async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/phim/$slug'), headers: _headers)
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return [];
      final sd = _serverData(jsonDecode(res.body));
      if (sd == null) return [];
      return List.generate(sd.length, (i) => '${i + 1}');
    } catch (e) {
      return [];
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
      if (sd == null || sd.isEmpty) return null;
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
          if (thumb.startsWith('/')) {
            thumb = '$cdn$thumb';
          } else {
            thumb = thumb.contains('/') ? '$cdn/$thumb' : '$cdn/uploads/movies/$thumb';
          }
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
      return [];
    }
  }

  static List? _serverData(Map<String, dynamic> data) {
    final episodes = data['episodes'] as List?;
    if (episodes == null || episodes.isEmpty) return null;
    return episodes[0]['server_data'] as List?;
  }
}

// ════════════════════════════════════════════════════════════════════════════
// PROVIDER COORDINATOR (new provider stack — replaces old cores)
// ════════════════════════════════════════════════════════════════════════════

class ProviderCoordinator {
  static final ProviderRegistry _registry = ProviderRegistry()
    ..register(SenshiProvider())
    ..register(AnipubProvider())
    ..register(AninekoProvider())
    ..register(AllAnimeProvider())
    ..register(AnimepaheProvider());

  static ProviderRegistry get registry => _registry;

  static Future<List<SelectionOption>> searchAll(String query, String mode,
      {List<String>? providers}) async {
    final list = providers ?? _registry.defaultStack;
    final allResults = <SelectionOption>[];
    for (final id in list) {
      try {
        final p = _registry.provider(id);
        final r = query.isEmpty
            ? await p.getTrending(mode)
            : await p.searchAnime(query, mode);
        for (final opt in r) {
          allResults.add(SelectionOption(
            key: makeQualifiedId(opt.extraData, opt.key, id),
            label: opt.label,
            title: opt.title,
            thumbnail: opt.thumbnail,
            extraData: {...?opt.extraData, 'provider': id},
          ));
        }
      } catch (e) {
        debugPrint('$id ${query.isEmpty ? "trending" : "search"} error: $e');
      }
    }
    if (allResults.isEmpty) throw Exception('No results from any provider');
    return mergeResults(allResults);
  }

  static Future<List<AnimeModel>> searchAsAnimeModel(
    String query,
    String mode, {
    List<String>? providers,
  }) async {
    final options = await searchAll(query, mode, providers: providers);
    return options
        .map((opt) {
          final provider = (opt.extraData?['provider'] as String?) ?? providers?.first ?? _registry.defaultStack.first;
          final rawKey = opt.key.contains('::') ? opt.key.split('::').last : opt.key;
          final qid = '$provider::$rawKey';
          return AnimeModel(
            id: qid,
            name: opt.title,
            thumbnail: opt.thumbnail,
            isManga: false,
            sourceId: qid,
            provider: provider,
          );
        })
        .toList();
  }

  static Future<List<String>> episodesList(
    String qualifiedId,
    String mode,
  ) async {
    final (providerId, showId) = parseQualifiedIdUnsafe(qualifiedId);
    final p = _registry.provider(providerId);
    try {
      return await p.episodesList(showId, mode);
    } catch (e) {
      debugPrint('[$providerId] episodesList error: $e');
      rethrow;
    }
  }

  static Future<Map<String, StreamPlaybackHint>> getStreamsWithHints(
    String qualifiedId,
    int epNo,
    String mode, {
    PlaybackConfig? config,
  }) async {
    final (providerId, showId) = parseQualifiedIdUnsafe(qualifiedId);
    final p = _registry.provider(providerId);
    final cfg = config ?? PlaybackConfig(subOrDub: mode);
    return p.getEpisodeUrlForModeWithHints(cfg, showId, epNo, mode);
  }

  static Future<List<String>> getStreamUrls(
    String qualifiedId,
    int epNo,
    String mode,
  ) async {
    final hints = await getStreamsWithHints(qualifiedId, epNo, mode);
    return hints.keys.toList();
  }

  static Future<String?> getStreamUrl(
    String qualifiedId,
    String episodeNum,
    String mode,
  ) async {
    final epNo = int.tryParse(episodeNum);
    if (epNo == null) return null;
    try {
      final urls = await getStreamUrls(qualifiedId, epNo, mode);
      return urls.isNotEmpty ? urls.first : null;
    } catch (e) {
      debugPrint('ProviderCoordinator.getStreamUrl error: $e');
      return null;
    }
  }
}