import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'provider_base.dart';

class AnimepaheProvider extends AnimeProvider {
  @override
  String get name => 'animepahe';

  @override
  String get providerId => 'animepahe';

  static const String _baseUrl = 'https://animepahe.com';
  static const String _apiUrl = 'https://animepahe.com/api';
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
      Uri.parse('$_apiUrl?m=search&q=${Uri.encodeComponent(query)}'),
      headers: _headers,
    );
    if (!isHttpOk(res.statusCode)) {
      throw Exception('Animepahe search failed: ${res.statusCode}');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final items = data['data'] as List? ?? [];
    if (items.isEmpty) throw Exception('No results for "$query"');

    return items.map<SelectionOption>((item) {
      final id = item['id'] as int? ?? 0;
      final title = (item['title'] as String? ?? '').trim();
      final type = (item['type'] as String? ?? '').trim();
      final year = item['year'] as int? ?? 0;
      final episodes = item['episodes'] as int? ?? 0;
      final status = (item['status'] as String? ?? '').trim();

      final parts = <String>[title];
      if (type.isNotEmpty) parts.add(type);
      if (year > 0) parts.add(year.toString());
      if (episodes > 0) parts.add('$episodes eps');
      if (status.isNotEmpty) parts.add(status);

      return SelectionOption(
        key: id.toString(),
        label: parts.join(' · '),
        title: title,
        thumbnail: item['poster'] as String? ?? item['thumbnail'] as String?,
        extraData: {
          'id': id,
          'title': title,
          'type': type,
          'year': year,
          'episodes': episodes,
          'status': status,
          'session': item['session'],
          'slug': item['slug'],
        },
      );
    }).toList();
  }

  @override
  Future<List<String>> episodesList(String showId, String mode) async {
    final id = int.tryParse(showId.trim());
    if (id == null || id <= 0) throw Exception('Invalid Animepahe ID: "$showId"');

    final eps = <int>{};
    int page = 1;
    int? lastPage;

    while (lastPage == null || page <= lastPage) {
      final res = await http.get(
        Uri.parse('$_apiUrl?m=release&id=$id&sort=ep_asc&page=$page'),
        headers: _headers,
      );
      if (!isHttpOk(res.statusCode)) break;

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final items = data['data'] as List? ?? [];
      if (items.isEmpty) break;

      for (final item in items) {
        final ep = item['episode'] as int? ?? 0;
        if (ep > 0) eps.add(ep);
      }

      lastPage = data['last_page'] as int? ?? page;
      page++;
    }

    if (eps.isEmpty) throw Exception('No episodes found for ID $id');

    final sorted = eps.toList()..sort();
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
    final showId = int.tryParse(id.trim());
    if (showId == null || showId <= 0) throw Exception('Invalid Animepahe ID: "$id"');
    if (epNo <= 0) throw Exception('Invalid episode number $epNo');

    final res = await http.get(
      Uri.parse('$_apiUrl?m=release&id=$showId&sort=ep_asc&page=1'),
      headers: _headers,
    );
    if (!isHttpOk(res.statusCode)) {
      throw Exception('Animepahe release fetch failed: ${res.statusCode}');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final items = data['data'] as List? ?? [];

    Map<String, dynamic>? targetEp;
    for (final item in items) {
      final epNum = (item as Map)['episode'];
      if (epNum is int && epNum == epNo) {
        targetEp = item as Map<String, dynamic>;
        break;
      }
    }

    if (targetEp == null) throw Exception('Episode $epNo not found');

    final session = targetEp['session'] as String? ?? '';
    if (session.isEmpty) throw Exception('No session for episode $epNo');

    final kwikUrl = 'https://kwik.cx/f/$session';

    final kwikRes = await http.get(
      Uri.parse(kwikUrl),
      headers: {
        'User-Agent': _userAgent,
        'Referer': '$_baseUrl/',
      },
    );
    if (kwikRes.statusCode != 200) {
      throw Exception('Kwik fetch failed: ${kwikRes.statusCode}');
    }

    final kwikHtml = kwikRes.body;

    if (kwikHtml.contains('DDoS-Guard') || kwikHtml.contains('ddos') ||
        kwikHtml.contains('Just a moment') || kwikHtml.contains('cf-browser-verification') ||
        kwikHtml.contains('_cf_chl_opt')) {
      throw Exception(
        'Animepahe: DDoS-Guard challenge detected at kwik.cx. '
        'Cannot bypass without headless browser. Try a different provider.',
      );
    }

    final unpacked = _unpackKwikJs(kwikHtml);
    final m3u8Regex = RegExp("(https?://[^\"';<>&\\s]+\\.m3u8[^\"';<>&\\s]*)");
    final matches = m3u8Regex.allMatches(unpacked);

    final results = <String, StreamPlaybackHint>{};
    for (final m in matches) {
      final url = m.group(1)!;
      if (!results.containsKey(url)) {
        results[url] = StreamPlaybackHint(referrer: kwikUrl, extraHeaders: {'User-Agent': _userAgent});
      }
    }

    if (results.isEmpty) {
      final directM3u8 = RegExp(
        "(https?://[^\"';<>&\\s]+\\.m3u8)",
      ).allMatches(kwikHtml);
      for (final m in directM3u8) {
        final url = m.group(1)!;
        if (!results.containsKey(url)) {
          results[url] = StreamPlaybackHint(referrer: kwikUrl, extraHeaders: {'User-Agent': _userAgent});
        }
      }
    }

    if (results.isEmpty) throw Exception('No m3u8 found in Kwik response');
    return results;
  }

  String _unpackKwikJs(String html) {
    final scriptMatch = RegExp(
      r'<script[^>]*>([\s\S]*?)</script>',
      dotAll: true,
    ).allMatches(html);

    for (final m in scriptMatch) {
      final script = m.group(1)!;
      if (script.contains('eval') || script.contains('function(p,a,c,k,e,d)')) {
        final result = _packedJsUnpack(script);
        if (result != null && result.isNotEmpty) return result;
      }
    }
    return html;
  }

  String? _packedJsUnpack(String packed) {
    try {
      final payloadMatch = RegExp(
        r"'([^']+)'\.split\('([^']+)'\)",
        dotAll: true,
      ).firstMatch(packed);

      if (payloadMatch == null) return null;

      final payload = payloadMatch.group(1)!;
      final delimiter = payloadMatch.group(2)!;
      final elements = payload.split(delimiter);

      final flipMatch = RegExp(
        r"while\s*\((\w+)\s*--\s*\)\s*(\w+)\s*\+\=\s*(\w+)\s*=\s*(\w+)\s*=\s*",
        dotAll: true,
      ).firstMatch(packed);

      if (flipMatch == null) return null;

      final pVar = flipMatch.group(1)!;
      final aVar = flipMatch.group(2)!;

      final initialMatch = RegExp(
        r'\|\|' + RegExp.escape(pVar),
      ).firstMatch(packed);

      if (initialMatch == null) return null;

      final initValMatch = RegExp(
        r'=\s*(\d+)\s*;',
        dotAll: false,
      ).firstMatch(packed);
      if (initValMatch == null) return null;

      var result = packed;
      final replacePattern = RegExp(
        r'(?:' + RegExp.escape(aVar) + r'|' + RegExp.escape(pVar) + r')\[(\w+)\]',
      );

      for (final m in replacePattern.allMatches(packed).toList().reversed) {
        final key = m.group(1)!;
        if (key.length == 1) {
          final idx = key.codeUnitAt(0) - 97;
          if (idx >= 0 && idx < elements.length) {
            result = result.replaceRange(m.start, m.end, elements[idx]);
          }
        }
      }

      return result;
    } catch (e) {
      debugPrint('Animepahe JS unpack error: $e');
      return null;
    }
  }

}
