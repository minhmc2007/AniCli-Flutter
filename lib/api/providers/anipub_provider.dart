import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'provider_base.dart';

class AnipubProvider extends AnimeProvider {
  @override
  String get name => 'anipub';

  @override
  String get providerId => 'anipub';

  static const String _baseUrl = 'https://anipub.xyz';
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

    final res = await http.post(
      Uri.parse('$_baseUrl/api/anime/search'),
      headers: {
        ..._headers,
        'Content-Type': 'application/json',
        'X-Requested-With': 'XMLHttpRequest',
      },
      body: jsonEncode({'search': query, 'page': '1', 'type': 'tv'}),
    );
    if (!isHttpOk(res.statusCode)) throw Exception('Anipub search failed: ${res.statusCode}');

    final data = jsonDecode(res.body);
    final items = (data is List)
        ? data
        : ((data as Map<String, dynamic>)['data'] as List? ??
            (data['results'] as List? ?? []));
    if (items.isEmpty) {
      throw Exception('No results for "$query"');
    }

    return items.map<SelectionOption>((item) {
      final slug = (item['slug'] as String? ?? '').trim();
      final title = (item['title'] as String? ?? '').trim();
      final altTitle1 = (item['alternativeTitle'] as String? ?? '').trim();
      final altTitle2 = (item['alt_title'] as String? ?? '').trim();
      final displayTitle = title.isNotEmpty ? title : (altTitle1.isNotEmpty ? altTitle1 : altTitle2);

      return SelectionOption(
        key: slug,
        label: displayTitle,
        title: displayTitle,
        thumbnail: item['poster'] as String? ?? item['image'] as String?,
        extraData: {
          'slug': slug,
          'title': title,
          'alt_title': altTitle1.isNotEmpty ? altTitle1 : altTitle2,
          'type': item['type'],
          'status': item['status'],
          'rating': item['rating'],
          'year': item['year'],
        },
      );
    }).toList();
  }

  @override
  Future<List<String>> episodesList(String showId, String mode) async {
    final slug = showId.trim();
    if (slug.isEmpty) throw Exception('Empty Anipub slug');

    final res = await http.get(
      Uri.parse('$_baseUrl/anime/$slug'),
      headers: _headers,
    );
    if (!isHttpOk(res.statusCode)) throw Exception('Anipub detail failed: ${res.statusCode}');

    final html = res.body;
    final epListRegex = RegExp(r'<ul[^>]*id="episodeList"[^>]*>(.*?)</ul>', dotAll: true);
    final match = epListRegex.firstMatch(html);
    if (match == null) throw Exception('Episode list not found');

    final epAnchors = RegExp(r'<a[^>]*href="[^"]*ep=(\d+)"[^>]*>').allMatches(match.group(1)!);
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
    if (slug.isEmpty) throw Exception('Empty Anipub slug');
    if (epNo <= 0) throw Exception('Invalid episode number $epNo');

    final lang = normalizeTranslationType(mode);
    final langQuery = lang == 'dub' ? 'dub' : 'sub';

    final serversRes = await http.get(
      Uri.parse('$_baseUrl/ajax/v2/episode/servers?ep=$epNo&lang=$langQuery&slug=$slug'),
      headers: {
        ..._headers,
        'X-Requested-With': 'XMLHttpRequest',
        'Accept': 'application/json',
      },
    );
    if (!isHttpOk(serversRes.statusCode)) {
      throw Exception('Anipub servers failed: ${serversRes.statusCode}');
    }

    final serversData = jsonDecode(serversRes.body);
    final servers = serversData is List ? serversData : ((serversData as Map<String, dynamic>)['data'] as List? ?? []);
    if (servers.isEmpty) {
      throw Exception('No servers available for $lang');
    }

    final results = <String, StreamPlaybackHint>{};
    for (final server in servers) {
      final serverId = server['id'] as int? ?? 0;
      if (serverId == 0) continue;

      final name = (server['name'] as String? ?? '').trim().toLowerCase();

      final srcRes = await http.get(
        Uri.parse('$_baseUrl/ajax/v2/episode/sources?serverId=$serverId&ep=$epNo'),
        headers: {
          ..._headers,
          'X-Requested-With': 'XMLHttpRequest',
          'Referer': '$_baseUrl/anime/$slug',
        },
      );
      if (!isHttpOk(srcRes.statusCode)) continue;

      final srcData = jsonDecode(srcRes.body);
      if (srcData is! Map<String, dynamic>) continue;

      final sourceUrl = (srcData['url'] as String? ?? srcData['src'] as String? ?? '').trim();
      if (sourceUrl.isEmpty) continue;

      if (name.contains('megacloud') || name.contains('megaclub')) {
        try {
          final megaUrls = await _extractMegaPlayUrls(sourceUrl, slug);
          for (final entry in megaUrls.entries) {
            results[entry.key] = entry.value;
          }
        } catch (e) {
          debugPrint('Anipub MegaPlay extract error: $e');
        }
      } else {
        results[sourceUrl] = StreamPlaybackHint(
          referrer: '$_baseUrl/anime/$slug',
          extraHeaders: {'User-Agent': _userAgent},
        );
      }
    }

    if (results.isEmpty) throw Exception('No playable streams found for $lang');
    return results;
  }

  Future<Map<String, StreamPlaybackHint>> _extractMegaPlayUrls(
    String megaUrl,
    String slug,
  ) async {
    final res = await http.get(
      Uri.parse(megaUrl),
      headers: {'User-Agent': _userAgent, 'Referer': '$_baseUrl/anime/$slug'},
    );
    if (!isHttpOk(res.statusCode)) throw Exception('MegaPlay fetch failed: ${res.statusCode}');

    final html = res.body;
    final packedMatch = RegExp(r'eval\s*\(\s*function\s*(?:p|hunk|\(\s*\))\s*\)').firstMatch(html);
    if (packedMatch == null) throw Exception('No packed JS found');

    final unpacked = _unpackHtml(html);
    final m3u8Regex = RegExp("(https?://[^\"';<>&\\s]+\\.m3u8[^\"';<>&\\s]*)");
    final matches = m3u8Regex.allMatches(unpacked);

    final results = <String, StreamPlaybackHint>{};
    for (final m in matches) {
      final url = m.group(1)!;
      if (!results.containsKey(url)) {
        results[url] = StreamPlaybackHint(referrer: megaUrl, extraHeaders: {'User-Agent': _userAgent});
      }
    }
    return results;
  }

  String _unpackHtml(String html) {
    const patterns = [
      r"<script[^>]*>\s*(eval\s*\([^;]*;)\s*</script>",
      r"<script[^>]*>\s*(window\s*\.\s*eval[^;]*;)\s*</script>",
      r"<script[^>]*>\s*(document\s*\.\s*write\s*\([^;]*;)\s*</script>",
    ];

    var result = html;
    int pass = 0;
    while (pass < 10) {
      int found = 0;
      for (final pattern in patterns) {
        final re = RegExp(pattern, dotAll: true, caseSensitive: false);
        for (final m in re.allMatches(result).toList()) {
          final script = m.group(1)!;
          final decoded = _tryUnpackJs(script);
          if (decoded != null && decoded.isNotEmpty) {
            result = result.replaceFirst(script, decoded);
            found++;
          }
        }
      }
      if (found == 0) break;
      pass++;
    }

    return result;
  }

  String? _tryUnpackJs(String js) {
    try {
      final packedMatch = RegExp(
        r"eval\s*\(\s*function\s*(\w+)?\s*\((\w+),\s*(\w+),\s*(\w+),\s*(\w+)\)",
        dotAll: true,
      ).firstMatch(js);

      if (packedMatch == null) return null;

      final bodyMatch = RegExp(
        r"'([^']+)'\.split\('([^']+)'\)",
        dotAll: true,
      ).firstMatch(js);

      if (bodyMatch == null) return null;

      final payload = bodyMatch.group(1)!;
      final delimiter = bodyMatch.group(2)!;
      final words = payload.split(delimiter);

      final initialValueMatch = RegExp(r'\|\|(\w+)', dotAll: true).firstMatch(js);
      if (initialValueMatch == null) return null;

      final rotateMatch = RegExp(
        r"while\s*\((\w+)\s*--\s*\)\s*(\w+)\s*\+\=\s*(\w+)\s*=\s*(\w+)\s*=\s*",
        dotAll: true,
      ).firstMatch(js);
      if (rotateMatch == null) return null;

      final cMatch = RegExp(r"}\s*while\s*\(\s*(\w+)\s*--\s*\)", dotAll: true).firstMatch(js);
      if (cMatch == null) return null;

      final countStr = cMatch.group(1)!;
      final keyFromValue = <String, String>{};
      for (int i = 0; i < words.length; i++) {
        final idx = i < countStr.length ? countStr.codeUnitAt(i) - 97 : i;
        String key;
        if (idx < 26) {
          key = String.fromCharCode(97 + idx);
        } else if (idx < 52) {
          key = String.fromCharCode(65 + (idx - 26));
        } else {
          key = 'v$i';
        }
        keyFromValue[key] = words[i];
      }

      var unpackSource = js;
      for (final entry in keyFromValue.entries) {
        if (entry.value == '\\') continue;
        unpackSource = unpackSource.replaceAll(
          RegExp(RegExp.escape('=${entry.key}[^\\w]'), dotAll: true, caseSensitive: false),
          '=${entry.value}',
        );
      }

      return unpackSource;
    } catch (e) {
      debugPrint('Anipub JS unpack error: $e');
      return null;
    }
  }
}
