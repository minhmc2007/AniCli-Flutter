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
      };

  @override
  Future<List<SelectionOption>> searchAnime(String query, String mode) async {
    query = query.trim();
    if (query.isEmpty) throw Exception('Empty search query');

    final res = await http.get(
      Uri.parse('$_baseUrl/search?keyword=${Uri.encodeComponent(query)}'),
      headers: {
        ..._headers,
        'X-Requested-With': 'XMLHttpRequest',
      },
    );
    if (!isHttpOk(res.statusCode)) throw Exception('Anineko search failed: ${res.statusCode}');

    List items;
    try {
      final data = jsonDecode(res.body);
      if (data is List) {
        items = data;
      } else if (data is Map<String, dynamic> && data['results'] is List) {
        items = data['results'] as List;
      } else if (data is Map<String, dynamic> && data['data'] is List) {
        items = data['data'] as List;
      } else {
        items = [];
      }
    } catch (_) {
      final anchors = RegExp(
        r'<a[^>]*class="[^"]*anime-link[^"]*"[^>]*href="/anime/([^"]+)"[^>]*>([\s\S]*?)</a>',
      ).allMatches(res.body);

      items = anchors.map((m) {
        final slug = m.group(1)!.trim();
        final inner = m.group(2)!;
        final titleMatch = RegExp(r'>([^<]+)<').firstMatch(inner);
        final title = titleMatch?.group(1)?.trim() ?? slug;
        final imgMatch = RegExp(r'<img[^>]*src="([^"]+)"').firstMatch(inner);

        return {
          'slug': slug,
          'title': title,
          'poster': imgMatch?.group(1),
        };
      }).toList();
    }

    if (items.isEmpty) throw Exception('No results for "$query"');

    return items.map<SelectionOption>((item) {
      final slug = (item['slug'] as String? ?? item['id'] as String? ?? '').trim();
      final title = (item['title'] as String? ?? '').trim();
      final subbed = item['sub_ep_count'] as int? ?? 0;
      final dubbed = item['dub_ep_count'] as int? ?? 0;
      final total = subbed + dubbed;

      final parts = <String>[title];
      if (total > 0) parts.add('$total eps');
      if (subbed > 0 && dubbed > 0) {
        parts.add('Sub: $subbed · Dub: $dubbed');
      }

      return SelectionOption(
        key: slug,
        label: parts.join(' · '),
        title: title,
        thumbnail: item['poster'] as String? ?? item['image'] as String?,
        extraData: {
          'slug': slug,
          'title': title,
          'sub_ep_count': subbed,
          'dub_ep_count': dubbed,
          'type': item['type'],
          'status': item['status'],
          'score': item['score'],
        },
      );
    }).toList();
  }

  @override
  Future<List<String>> episodesList(String showId, String mode) async {
    final slug = showId.trim();
    if (slug.isEmpty) throw Exception('Empty Anineko slug');

    final res = await http.get(
      Uri.parse('$_baseUrl/anime/$slug'),
      headers: _headers,
    );
    if (!isHttpOk(res.statusCode)) {
      throw Exception('Anineko anime page failed: ${res.statusCode}');
    }

    final html = res.body;

    final epListMatch =
        RegExp(r'<ul[^>]*class="[^"]*episode-list[^"]*"[^>]*>(.*?)</ul>', dotAll: true)
            .firstMatch(html);

    String epSection;
    if (epListMatch != null) {
      epSection = epListMatch.group(1)!;
    } else {
      epSection = html;
    }

    final epAnchors = RegExp(
      r'<a[^>]*href="[^"]*episode[=/](\d+)[^"]*"[^>]*>',
      dotAll: true,
    ).allMatches(epSection);

    final eps = epAnchors.map((m) => int.parse(m.group(1)!)).toSet().toList()..sort();
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

    final serversRes = await http.get(
      Uri.parse('$_baseUrl/anime/$slug/episode/$epNo'),
      headers: {
        ..._headers,
        'X-Requested-With': 'XMLHttpRequest',
        'Accept': 'text/plain, */*; q=0.01',
      },
    );
    if (!isHttpOk(serversRes.statusCode)) {
      throw Exception('Anineko episode fetch failed: ${serversRes.statusCode}');
    }

    String html;
    try {
      final data = jsonDecode(serversRes.body);
      html = data is Map<String, dynamic> ? (data['html'] as String? ?? '') : '';
    } catch (_) {
      html = serversRes.body;
    }

    if (html.isEmpty) throw Exception('No episode data returned');

    final serverBlocks = RegExp(
      r'<div[^>]*class="[^"]*server-item[^"]*"[^>]*>([\s\S]*?)</div>',
      dotAll: true,
    ).allMatches(html);

    final results = <String, StreamPlaybackHint>{};

    for (final block in serverBlocks) {
      final serverHtml = block.group(1) ?? '';

      final embedMatch = RegExp(
        r'(?:src|data-src|href)\s*=\s*"([^"]*bibiemb[^"]*|embed[^"]*)"',
        dotAll: true,
        caseSensitive: false,
      ).firstMatch(serverHtml);

      if (embedMatch == null) continue;

      final embedUrl = embedMatch.group(1)!;

      try {
        final embedRes = await http.get(
          Uri.parse(embedUrl),
          headers: {'User-Agent': _userAgent, 'Referer': '$_baseUrl/anime/$slug'},
        );
        if (!isHttpOk(embedRes.statusCode)) continue;

        final embedBody = embedRes.body;

        final m3u8Matches = RegExp(
          "(https?://[^\"';<>&\\s]+\\.m3u8[^\"';<>&\\s]*)",
        ).allMatches(embedBody);

        String? subtitle;

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

        final subUrl = await _resolveAninekoSubtitle(embedBody);
        if (subUrl != null && results.isNotEmpty) {
          results.updateAll((k, v) => StreamPlaybackHint(
                referrer: v.referrer,
                subtitle: subUrl,
                extraHeaders: v.extraHeaders,
              ));
        }
      } catch (e) {
        debugPrint('Anineko embed fetch error: $e');
      }
    }

    final vibeIframes = RegExp(
      r'<iframe[^>]*src="([^"]*vibeplayer[^"]*)"',
      dotAll: true,
      caseSensitive: false,
    ).allMatches(html);
    for (final m in vibeIframes) {
      results[m.group(1)!] = StreamPlaybackHint(referrer: '$_baseUrl/anime/$slug', extraHeaders: {'User-Agent': _userAgent});
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
