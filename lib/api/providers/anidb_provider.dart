import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'provider_base.dart';

/// AniDB.app provider — mirrors upstream ani-cli v5 (anidb.app source).
/// Replaces the dead AllAnime source.
class AnidbProvider extends AnimeProvider {
  @override
  String get name => 'anidb';

  @override
  String get providerId => 'anidb';

  static const String _baseUrl = 'https://anidb.app';
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  Map<String, String> get _headers => {
        'User-Agent': _userAgent,
        'Referer': '$_baseUrl/',
      };

  static const List<String> _browserHeaderArgs = [
    '-H', 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
    '-H', 'Accept-Language: en-US,en;q=0.9',
    '-H', 'Sec-CH-UA: "Chromium";v="124", "Google Chrome";v="124", "Not-A.Brand";v="99"',
    '-H', 'Sec-CH-UA-Mobile: ?0',
    '-H', 'Sec-CH-UA-Platform: "Windows"',
    '-H', 'Sec-Fetch-Dest: document',
    '-H', 'Sec-Fetch-Mode: navigate',
    '-H', 'Sec-Fetch-Site: none',
    '-H', 'Sec-Fetch-User: ?1',
    '-H', 'Upgrade-Insecure-Requests: 1',
  ];

  bool get _useCurl =>
      !kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS);

  /// anidb.app is Cloudflare-protected and blocks Dart's BoringSSL TLS
  /// fingerprint (JA3) with a 403 challenge, while curl/real browsers pass.
  /// Desktop shells out to curl; mobile falls back to dart:io http (and the
  /// provider just fails over to the next source if CF keeps blocking).
  Future<http.Response> _fetch(String url) async {
    if (_useCurl) {
      try {
        final res = await Process.run('curl', [
          '-s', '--http2', '-L', '--compressed', '--max-time', '20',
          '-A', _userAgent,
          '-H', 'Referer: $_baseUrl/',
          ..._browserHeaderArgs,
          url,
        ], stdoutEncoding: null);
        if (res.exitCode == 0) {
          final bytes = res.stdout as List<int>;
          if (bytes.isNotEmpty) {
            return http.Response.bytes(bytes, 200);
          }
        }
      } catch (_) {}
    }
    return http.get(Uri.parse(url), headers: _headers);
  }

  String _decodeEntities(String s) {
    return s
        .replaceAll('&#039;', "'")
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');
  }

  List<SelectionOption> _parseBrowse(String html) {
    final items = <SelectionOption>[];
    final cardRe = RegExp(
      r'<a[^>]*href="https://anidb\.app/anime/([a-z0-9-]+)-(\d+)"[^>]*>(.*?)</a>',
      dotAll: true,
      caseSensitive: false,
    );

    for (final m in cardRe.allMatches(html)) {
      final slug = m.group(1)!;
      final id = m.group(2)!;
      final block = m.group(3)!;

      final imgMatch = RegExp(
        r'<img[^>]*src="([^"]+)"[^>]*alt="([^"]*)"',
      ).firstMatch(block);
      final titleAttr = RegExp(
        r'title="([^"]*)"',
      ).firstMatch(m.group(0)!);
      final title = _decodeEntities(titleAttr?.group(1) ?? imgMatch?.group(2) ?? slug);
      final thumb = imgMatch?.group(1);

      items.add(SelectionOption(
        key: id,
        label: title,
        title: title,
        thumbnail: thumb,
        extraData: {'slug': slug, 'title': title, 'id': int.tryParse(id) ?? 0},
      ));
    }
    return items;
  }

  @override
  Future<List<SelectionOption>> searchAnime(String query, String mode) async {
    query = query.trim();
    if (query.isEmpty) throw Exception('Empty search query');

    final res = await _fetch(
      '$_baseUrl/browse?q=${Uri.encodeComponent(query)}',
    );
    if (!isHttpOk(res.statusCode)) {
      throw Exception('AniDB search failed: ${res.statusCode}');
    }

    final items = _parseBrowse(res.body);
    if (items.isEmpty) throw Exception('No results for "$query"');
    return items;
  }

  @override
  Future<List<SelectionOption>> getTrending(String mode) async {
    final res = await _fetch('$_baseUrl/browse');
    if (!isHttpOk(res.statusCode)) {
      throw Exception('AniDB trending failed: ${res.statusCode}');
    }

    final items = _parseBrowse(res.body);
    if (items.isEmpty) throw Exception('No trending results');
    return items;
  }

  @override
  Future<List<String>> episodesList(String showId, String mode) async {
    final id = showId.trim();
    if (id.isEmpty) throw Exception('Empty AniDB anime ID');

    final res = await _fetch('$_baseUrl/api/frontend/anime/$id/episodes');
    if (!isHttpOk(res.statusCode)) {
      throw Exception('AniDB episodes failed: ${res.statusCode}');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final eps = data['episodes'] as List? ?? [];

    final numbers = <int>{};
    for (final e in eps) {
      if (e is! Map) continue;
      final n = e['number'];
      if (n is int && n > 0) numbers.add(n);
    }
    if (numbers.isEmpty) throw Exception('No episodes found for ID $id');

    final sorted = numbers.toList()..sort();
    return sorted.map((e) => e.toString()).toList();
  }

  @override
  Future<List<String>> getEpisodeUrl(PlaybackConfig config, String id, int epNo) async {
    final result = await getEpisodeUrlForModeWithHints(config, id, epNo, config.subOrDub);
    return result.keys.toList();
  }

  @override
  Future<Map<String, StreamPlaybackHint>> getEpisodeUrlForModeWithHints(
    PlaybackConfig config,
    String id,
    int epNo,
    String mode,
  ) async {
    final showId = id.trim();
    if (showId.isEmpty) throw Exception('Empty AniDB anime ID');
    if (epNo <= 0) throw Exception('Invalid episode number $epNo');

    final epId = await _episodeIdForNumber(showId, epNo);
    if (epId == null) throw Exception('Episode $epNo not found');

    final lang = normalizeTranslationType(mode) == 'dub' ? 'eng' : 'jpn';

    final langsRes = await _fetch('$_baseUrl/api/frontend/episode/$epId/languages');
    if (!isHttpOk(langsRes.statusCode)) {
      throw Exception('AniDB languages failed: ${langsRes.statusCode}');
    }

    final langsData = jsonDecode(langsRes.body) as Map<String, dynamic>;
    final langs = langsData['languages'] as List? ?? [];

    String? embedUrl;
    for (final l in langs) {
      if (l is! Map) continue;
      if (l['code'] == lang) {
        embedUrl = (l['embed_url'] as String? ?? '').trim();
        if (embedUrl.isNotEmpty) break;
      }
    }
    if (embedUrl == null) throw Exception('No $lang stream for episode $epNo');

    final embedRes = await _fetch(embedUrl);
    if (!isHttpOk(embedRes.statusCode)) {
      throw Exception('AniDB embed failed: ${embedRes.statusCode}');
    }

    final fileMatch = RegExp(
      r'''file\s*:\s*['"]([^'"]+\.m3u8[^'"]*)['"]''',
    ).firstMatch(embedRes.body);
    if (fileMatch == null) throw Exception('No m3u8 found in AniDB embed');

    final streamUrl = fileMatch.group(1)!;
    return {
      streamUrl: StreamPlaybackHint(
        referrer: '$_baseUrl/',
        extraHeaders: {'User-Agent': _userAgent},
      ),
    };
  }

  Future<int?> _episodeIdForNumber(String showId, int epNo) async {
    final res = await _fetch('$_baseUrl/api/frontend/anime/$showId/episodes');
    if (!isHttpOk(res.statusCode)) return null;

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final eps = data['episodes'] as List? ?? [];
    for (final e in eps) {
      if (e is! Map) continue;
      if (e['number'] == epNo) {
        final eid = e['id'];
        if (eid is int) return eid;
      }
    }
    return null;
  }
}