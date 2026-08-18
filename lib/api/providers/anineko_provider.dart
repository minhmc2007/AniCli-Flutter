import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'provider_base.dart';

class AninekoProvider extends AnimeProvider {
  @override
  String get name => 'anineko';

  @override
  String get providerId => 'anineko';

  static const String _baseUrl = 'https://anineko.to';
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  Map<String, String> get _headers => {
        'User-Agent': _userAgent,
        'Referer': '$_baseUrl/',
        'X-Requested-With': 'XMLHttpRequest',
      };

  @override
  Future<List<SelectionOption>> getTrending(String mode) async {
    final res = await http.get(
      Uri.parse('$_baseUrl/browse'),
      headers: {'User-Agent': _userAgent, 'Referer': '$_baseUrl/'},
    );
    if (!isHttpOk(res.statusCode)) {
      throw Exception('Anineko browse failed: ${res.statusCode}');
    }

    final items = <SelectionOption>[];
    final thumbMatches = RegExp(
      r'<a class="nv-anime-thumb[^"]*" href="/watch/([^"]+)"[^>]*>(.*?)</a>',
      dotAll: true,
    ).allMatches(res.body);

    for (final m in thumbMatches) {
      final slug = m.group(1)!.trim();
      if (slug.isEmpty) continue;
      final block = m.group(2)!;
      final imgMatch = RegExp(
        r'<img[^>]*src="([^"]+)"[^>]*alt="([^"]*)"',
      ).firstMatch(block);
      final title = imgMatch?.group(2) ?? slug;
      final epMatch = RegExp(r'nv-stat-cc">CC\s*(\d+)').firstMatch(block);
      final epCount = epMatch?.group(1);

      final parts = <String>[title];
      if (epCount != null) parts.add('$epCount eps');

      items.add(SelectionOption(
        key: slug,
        label: parts.join(' · '),
        title: title,
        thumbnail: imgMatch?.group(1),
        extraData: {'slug': slug, 'title': title},
      ));
    }

    if (items.isEmpty) throw Exception('No trending results');
    return items;
  }

  @override
  Future<List<SelectionOption>> searchAnime(String query, String mode) async {
    query = query.trim();
    if (query.isEmpty) throw Exception('Empty search query');

    final res = await http.get(
      Uri.parse('$_baseUrl/ajax/search?q=${Uri.encodeComponent(query)}'),
      headers: _headers,
    );
    if (!isHttpOk(res.statusCode)) throw Exception('Anineko search failed: ${res.statusCode}');

    final decoded = jsonDecode(res.body);
    final body = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    final items = body['results'] is List ? body['results'] as List : [];
    if (items.isEmpty) throw Exception('No results for "$query"');

    return items.map<SelectionOption>((item) {
      final title = (item['title'] as String? ?? '').trim();
      final url = (item['url'] as String? ?? '').trim();
      final slug = url.replaceAll(RegExp(r'^/watch/'), '');
      final meta = (item['meta'] as String? ?? '');
      final epMatch = RegExp(r'(\d+)\s*Episodes?').firstMatch(meta);
      final epCount = epMatch?.group(1) ?? '';

      final parts = <String>[title];
      if (epCount.isNotEmpty) parts.add('$epCount eps');

      return SelectionOption(
        key: slug,
        label: parts.join(' · '),
        title: title,
        thumbnail: item['image'] as String?,
        extraData: {
          'slug': slug,
          'title': title,
          'meta': meta,
        },
      );
    }).toList();
  }

  @override
  Future<List<String>> episodesList(String showId, String mode) async {
    final slug = showId.trim();
    if (slug.isEmpty) throw Exception('Empty Anineko slug');

    final res = await http.get(
      Uri.parse('$_baseUrl/watch/$slug'),
      headers: _headers,
    );
    if (!isHttpOk(res.statusCode)) {
      throw Exception('Anineko watch page failed: ${res.statusCode}');
    }

    final html = res.body;
    final epMatches = RegExp(
      r'/watch/[^/]+/ep-(\d+)',
      caseSensitive: false,
    ).allMatches(html);

    final eps = epMatches.map((m) => int.parse(m.group(1)!)).toSet().toList()..sort();
    if (eps.isEmpty) throw Exception('No episodes found');

    return eps.map((e) => e.toString()).toList();
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
    final slug = id.trim();
    if (slug.isEmpty) throw Exception('Empty Anineko slug');
    if (epNo <= 0) throw Exception('Invalid episode number $epNo');

    final watchRes = await http.get(
      Uri.parse('$_baseUrl/watch/$slug/ep-$epNo'),
      headers: _headers,
    );
    if (!isHttpOk(watchRes.statusCode)) {
      throw Exception('Anineko watch page failed: ${watchRes.statusCode}');
    }

    final html = watchRes.body;

    final serverBtns = RegExp(
      r'data-video="([^"]+)"',
    ).allMatches(html);

    final results = <String, StreamPlaybackHint>{};

    for (final m in serverBtns) {
      final embedUrl = m.group(1)!;
      if (results.containsKey(embedUrl)) continue;

      String? subtitle = _subtitleFromEmbedUrl(embedUrl);

      try {
        final embedRes = await http.get(
          Uri.parse(embedUrl),
          headers: {'User-Agent': _userAgent, 'Referer': '$_baseUrl/watch/$slug'},
        );
        if (!isHttpOk(embedRes.statusCode)) continue;

        final embedBody = embedRes.body;

        final m3u8Matches = RegExp(
          "(https?://[^\"';<>&\\s]+\\.m3u8[^\"';<>&\\s]*)",
        ).allMatches(embedBody);

        for (final m3u8Match in m3u8Matches) {
          final streamUrl = m3u8Match.group(1)!;
          if (!results.containsKey(streamUrl)) {
            results[streamUrl] = StreamPlaybackHint(
              referrer: embedUrl,
              subtitle: subtitle,
              extraHeaders: {'User-Agent': _userAgent},
            );
          }
        }

        final bodySub = await _resolveAninekoSubtitle(embedBody);
        if (bodySub != null && results.isNotEmpty) {
          results.updateAll((k, v) => StreamPlaybackHint(
                referrer: v.referrer,
                subtitle: bodySub,
                extraHeaders: v.extraHeaders,
              ));
        }
      } catch (e) {
        debugPrint('Anineko embed fetch error: $e');
      }

      if (results.length >= 3) break;
    }

    final directLinks = RegExp(
      "(https?://[^\"';<>&\\s]+\\.m3u8)",
    ).allMatches(html);
    for (final m in directLinks) {
      final url = m.group(1)!;
      if (!results.containsKey(url)) {
        results[url] = StreamPlaybackHint(extraHeaders: {'User-Agent': _userAgent});
      }
    }

    if (results.isEmpty) throw Exception('No playable streams found');
    return results;
  }

  String? _subtitleFromEmbedUrl(String embedUrl) {
    try {
      final params = Uri.parse(embedUrl).queryParameters;
      final sub = params['sub'] ?? params['caption_1'] ?? params['caption'];
      if (sub != null && sub.trim().isNotEmpty) return sub.trim();
    } catch (_) {}
    return null;
  }

  Future<String?> _resolveAninekoSubtitle(String embedBody) async {
    final candidateUrls = RegExp(
      "(https?://[^\"';<>&\\s]+\\.(?:vtt|srt|ass)[^\"';<>&\\s]*)",
    ).allMatches(embedBody);

    for (final m in candidateUrls) {
      final url = m.group(1)!;
      try {
        final head = await http.head(Uri.parse(url));
        if (head.statusCode == 200) return url;
      } catch (_) {}
    }

    final subApi = RegExp(
      '["\']subtitle["\'][^:]*:\\s*["\']([^"\']+)["\']',
    ).firstMatch(embedBody);
    return subApi?.group(1);
  }
}
