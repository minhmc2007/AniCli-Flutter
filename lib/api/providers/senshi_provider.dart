import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'provider_base.dart';

class SenshiProvider extends AnimeProvider {
  @override
  String get name => 'senshi';

  @override
  String get providerId => 'senshi';

  static const String _baseUrl = 'https://senshi.live';
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  Map<String, String> get _headers => {
        'User-Agent': _userAgent,
        'Referer': '$_baseUrl/',
        'Content-Type': 'application/json',
      };

  @override
  Future<List<SelectionOption>> searchAnime(String query, String mode) async {
    query = query.trim();

    final res = await http.post(
      Uri.parse('$_baseUrl/anime/filter'),
      headers: _headers,
      body: jsonEncode({
        'searchTerm': query,
        'page': 1,
        'limit': 25,
      }),
    );
    debugPrint('[Senshi] search response: ${res.statusCode}');
    if (!isHttpOk(res.statusCode)) throw Exception('Senshi search failed: ${res.statusCode}');

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final items = (data['data'] as List?) ?? [];
    debugPrint('[Senshi] search items count=${items.length}');
    if (items.isEmpty) throw Exception('No results for "$query"');

    return items.map<SelectionOption>((item) {
      final malId = item['id'] as int? ?? 0;
      final title = (item['title_english'] as String? ?? '').trim();
      final mainTitle = (item['title'] as String? ?? '').trim();
      final displayTitle = title.isNotEmpty ? title : mainTitle;
      final episodes = item['ani_episodes'] as String? ?? '';
      final epCount = int.tryParse(episodes) ?? 0;
      final year = item['ani_year'] as int? ?? 0;
      final type = item['type'] as String? ?? '';

      final parts = [displayTitle];
      if (type.isNotEmpty) parts.add(type);
      if (year > 0) parts.add(year.toString());
      if (epCount > 0) parts.add('$epCount eps');

      return SelectionOption(
        key: malId.toString(),
        label: parts.join(' · '),
        title: displayTitle,
        thumbnail: malId > 0 ? '$_baseUrl/posters/$malId.webp' : null,
        extraData: {
          'mal_id': malId,
          'public_id': item['public_id'],
          'title': mainTitle,
          'type': type,
          'episodes': epCount,
          'year': year,
          'score': item['score'],
          'status': item['ani_status'],
        },
      );
    }).toList();
  }

  @override
  Future<List<String>> episodesList(String showId, String mode) async {
    final malId = int.tryParse(showId.trim());
    debugPrint('[Senshi] episodesList showId=$showId malId=$malId');
    if (malId == null || malId <= 0) throw Exception('Invalid Senshi MAL ID: "$showId"');

    final res = await http.get(
      Uri.parse('$_baseUrl/episodes/$malId'),
      headers: {'User-Agent': _userAgent, 'Referer': '$_baseUrl/'},
    );
    debugPrint('[Senshi] episodes response: ${res.statusCode}');
    if (!isHttpOk(res.statusCode)) throw Exception('Senshi episodes failed: ${res.statusCode}');

    final items = jsonDecode(res.body) as List;
    debugPrint('[Senshi] episodes count=${items.length}');
    if (items.isEmpty) throw Exception('No episodes found for MAL ID $malId');

    final seen = <int>{};
    for (final item in items) {
      final epNo = item['ep_id'] as int? ?? item['id'] as int?;
      if (epNo != null && epNo > 0) seen.add(epNo);
    }
    if (seen.isEmpty) throw Exception('No valid episode numbers found');

    final sorted = seen.toList()..sort();
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
    final malId = int.tryParse(id.trim());
    if (malId == null || malId <= 0) throw Exception('Invalid Senshi MAL ID: "$id"');
    if (epNo <= 0) throw Exception('Invalid episode number $epNo');

    final lang = normalizeTranslationType(mode);
    final wantStatus = lang == 'dub' ? 'Dub' : 'HardSub';

    final res = await http.get(
      Uri.parse('$_baseUrl/episode-embeds/$malId/$epNo'),
      headers: {'User-Agent': _userAgent, 'Referer': '$_baseUrl/'},
    );
    if (!isHttpOk(res.statusCode)) {
      debugPrint('[Senshi] embeds fetch failed: ${res.statusCode}');
      throw Exception('Senshi embeds failed: ${res.statusCode}');
    }

    final embeds = jsonDecode(res.body) as List;
    debugPrint('[Senshi] ep-embeds response count=${embeds.length}');
    if (embeds.isEmpty) throw Exception('No streams found for episode $epNo');

    for (final item in embeds) {
      final status = (item['status'] as String? ?? '').trim();
      debugPrint('[Senshi] embed item status=$status want=$wantStatus');
      if (!status.toLowerCase().contains(wantStatus.toLowerCase())) continue;

      final streamUrl = (item['url'] as String? ?? '').trim();
      debugPrint('[Senshi] matched embed url=$streamUrl');
      if (streamUrl.isEmpty) continue;

      String? subtitle;
      if (lang == 'sub') subtitle = await _resolveSubtitle(item);

      return {
        streamUrl: StreamPlaybackHint(
          referrer: '$_baseUrl/',
          subtitle: subtitle,
          extraHeaders: {
            'User-Agent': _userAgent,
            'Origin': _baseUrl,
          },
        ),
      };
    }

    throw Exception('No $lang streams found for episode $epNo');
  }

  Future<String?> _resolveSubtitle(Map<String, dynamic> item) async {
    final manifestUrl = _subtitleManifestUrl(item);
    debugPrint('[Senshi] subtitle manifestUrl=$manifestUrl');
    if (manifestUrl == null || manifestUrl.isEmpty) return null;

    try {
      final res = await http.get(
        Uri.parse(manifestUrl),
        headers: {'User-Agent': _userAgent, 'Referer': '$_baseUrl/'},
      );
      if (!isHttpOk(res.statusCode)) {
        debugPrint('[Senshi] subtitle manifest fetch failed: ${res.statusCode}');
        return null;
      }

      final tracks = jsonDecode(res.body) as List;
      debugPrint('[Senshi] subtitle tracks count=${tracks.length}');
      String? fallback;
      for (final track in tracks) {
        final file = (track['src'] as String? ?? '').trim();
        if (file.isEmpty) continue;
        final label = (track['label'] as String? ?? '').toLowerCase().trim();
        if (track['default'] == true || label.contains('eng')) return file;
        fallback ??= file;
      }
      return fallback;
    } catch (e) {
      debugPrint('[Senshi] subtitle resolve error: $e');
      return null;
    }
  }

  String? _subtitleManifestUrl(Map<String, dynamic> item) {
    final serverFm = item['serverFM'] as String?;
    if (serverFm != null && serverFm.trim().isNotEmpty) {
      try {
        final parsed = Uri.parse(serverFm.trim());
        final subInfo = parsed.queryParameters['sub.info'];
        if (subInfo != null && subInfo.isNotEmpty) {
          debugPrint('[Senshi] subtitle manifest from serverFM: $subInfo');
          return subInfo;
        }
      } catch (_) {}
    }

    final maskedBase = (item['masked_base_url'] as String? ?? '').trim();
    if (maskedBase.isEmpty) return null;
    final url = '${maskedBase.endsWith('/') ? maskedBase : '$maskedBase/'}sub_filemoon.json';
    debugPrint('[Senshi] subtitle manifest from maskedBase: $url');
    return url;
  }
}
