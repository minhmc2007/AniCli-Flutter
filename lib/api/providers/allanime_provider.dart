import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:crypto/crypto.dart';
import 'provider_base.dart';

class _SourceCandidate {
  final double priority;
  final String name;
  final String url;
  _SourceCandidate(this.priority, this.name, this.url);
}

class AllAnimeProvider extends AnimeProvider {
  @override
  String get name => 'allanime';

  @override
  String get providerId => 'allanime';

  static const String _baseUrl = 'https://api.allanime.day/api';
  static const String _referer = 'https://youtu-chan.com';
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:150.0) Gecko/20100101 Firefox/150.0';

  static const String _gqlSearch = r'''
query($search: SearchInput $limit: Int $page: Int $translationType: VaildTranslationTypeEnumType $countryOrigin: VaildCountryOriginEnumType) {
  shows(search: $search limit: $limit page: $page translationType: $translationType countryOrigin: $countryOrigin) {
    edges {
      _id
      name
      thumbnail
      availableEpisodes
      __typename
    }
  }
}
''';

  static const String _gqlEpisodes = r'''
query ($showId: String!) {
  show(_id: $showId) {
    _id
    availableEpisodesDetail
  }
}
''';

  // Persistent query hash for stream URL
  static const String _streamQueryHash =
      'd405d0edd690624b66baba3068e0edc3ac90f1597d898a1ec8db4e5c43c00fec';

  Map<String, String> get _headers => {
        'User-Agent': _userAgent,
        'Referer': _referer,
        'Origin': _referer,
      };

  @override
  Future<List<SelectionOption>> searchAnime(String query, String mode) async {
    query = query.trim();
    if (query.isEmpty) throw Exception('Empty search query');

    final res = await http.post(
      Uri.parse(_baseUrl),
      headers: {
        ..._headers,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'variables': {
          'search': {
            'allowAdult': true,
            'allowUnknown': true,
            'query': query,
          },
          'limit': 40,
          'page': 1,
          'translationType': mode,
          'countryOrigin': 'ALL',
        },
        'query': _gqlSearch,
      }),
    );
    if (!isHttpOk(res.statusCode)) {
      throw Exception('AllAnime search failed: ${res.statusCode}');
    }

    final body = jsonDecode(res.body);
    final edges = (body['data'] as Map<String, dynamic>?)
            ?['shows']?['edges'] as List? ??
        [];
    if (edges.isEmpty) throw Exception('No results for "$query"');

    return edges.map<SelectionOption>((e) {
      final node = e is Map<String, dynamic> ? e : (e['node'] as Map<String, dynamic>? ?? {});
      final showId = (node['_id'] as String? ?? '').trim();
      final name = (node['name'] as String? ?? '').trim();

      final available = node['availableEpisodes'] as Map<String, dynamic>? ?? {};
      final subCount = (available['sub'] as num?)?.toInt() ?? 0;
      final dubCount = (available['dub'] as num?)?.toInt() ?? 0;
      final total = subCount + dubCount;

      final parts = <String>[name];
      if (total > 0) parts.add('${subCount}s/${dubCount}d');

      return SelectionOption(
        key: showId,
        label: parts.join(' · '),
        title: name,
        thumbnail: (node['thumbnail'] as String? ?? '').trim(),
        extraData: {
          '_id': showId,
          'name': name,
          'availableEpisodes': available,
        },
      );
    }).toList();
  }

  @override
  Future<List<String>> episodesList(String showId, String mode) async {
    final id = showId.trim();
    if (id.isEmpty) throw Exception('Empty AllAnime show ID');

    final res = await http.post(
      Uri.parse(_baseUrl),
      headers: {
        ..._headers,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'variables': {'showId': id},
        'query': _gqlEpisodes,
      }),
    );
    if (!isHttpOk(res.statusCode)) {
      throw Exception('AllAnime episodes failed: ${res.statusCode}');
    }

    final body = jsonDecode(res.body);
    final detail = (body['data'] as Map<String, dynamic>?)
        ?['show']?['availableEpisodesDetail'] as Map<String, dynamic>? ?? {};

    final key = mode == 'dub' ? 'dub' : 'sub';
    final eps = (detail[key] as List?)
            ?.map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .toList() ??
        [];

    if (eps.isEmpty) throw Exception('No episodes found');
    eps.sort((a, b) => _parseEpNum(a).compareTo(_parseEpNum(b)));
    return eps;
  }

  double _parseEpNum(String s) {
    final n = double.tryParse(s);
    if (n != null) return n;
    final m = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(s);
    if (m != null) return double.parse(m.group(1)!);
    return 0;
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
    if (showId.isEmpty) throw Exception('Empty AllAnime show ID');
    if (epNo <= 0) throw Exception('Invalid episode number $epNo');

    final gqlMode = mode == 'dub' ? 'dub' : 'sub';

    // Step 1: Get the encrypted response via persistent query (GET)
    final vars = jsonEncode({
      'showId': showId,
      'translationType': gqlMode,
      'episodeString': epNo.toString(),
    });
    final ext = jsonEncode({
      'persistedQuery': {
        'version': 1,
        'sha256Hash': _streamQueryHash,
      }
    });

    final uri = Uri.parse(_baseUrl).replace(queryParameters: {
      'variables': vars,
      'extensions': ext,
    });

    final res = await http.get(uri, headers: _headers);
    if (!isHttpOk(res.statusCode)) {
      throw Exception('AllAnime stream failed: ${res.statusCode}');
    }

    final body = jsonDecode(res.body);
    final tobeparsed = (body['data'] as Map<String, dynamic>?)?['tobeparsed'] as String?;
    if (tobeparsed == null || tobeparsed.isEmpty) {
      throw Exception('No tobeparsed data in response');
    }

    // Step 2: Decrypt tobeparsed
    final decrypted = _decryptTobeparsed(tobeparsed);
    if (decrypted == null || decrypted.isEmpty) {
      throw Exception('Failed to decrypt episode data');
    }

    // Step 3: Parse JSON and extract source URLs
    Map<String, dynamic> parsed;
    try {
      parsed = jsonDecode(decrypted) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('AllAnime: failed to parse decrypted JSON: $e');
      throw Exception('Invalid decrypted data');
    }

    final epData = parsed['episode'] as Map<String, dynamic>? ?? parsed;
    final sourceUrls = (epData['sourceUrls'] as List?) ?? [];

    if (sourceUrls.isEmpty) {
      throw Exception('No source URLs found');
    }

    // Step 4: Decode and sort sources by priority (lower = better)
    final candidates = <_SourceCandidate>[];
    for (final src in sourceUrls) {
      if (src is! Map<String, dynamic>) continue;
      final rawUrl = src['sourceUrl'] as String? ?? '';
      if (rawUrl.isEmpty) continue;
      final decoded = _decodeSourceUrl(rawUrl);
      if (decoded == null || decoded.isEmpty) continue;
      final priority = (src['priority'] as num?)?.toDouble() ?? 99;
      final name = src['sourceName'] as String? ?? 'Unknown';
      candidates.add(_SourceCandidate(priority, name, decoded));
    }
    candidates.sort((a, b) => a.priority.compareTo(b.priority));

    if (candidates.isEmpty) throw Exception('No playable streams found');

    // Step 5: Collect sources in priority order.
    // For each non-clock source, try yt-dlp resolution and add the direct URL.
    // Always add the original embed URL as fallback (for external mpv --ytdl=yes).
    final results = <String, StreamPlaybackHint>{};
    for (final c in candidates) {
      if (c.url.contains('clock.json')) {
        try {
          final clockRes = await http.get(Uri.parse(c.url), headers: _headers);
          if (clockRes.statusCode == 200) {
            final clockData = jsonDecode(clockRes.body) as Map<String, dynamic>;
            final links = clockData['links'] as List?;
            if (links != null) {
              for (final link in links) {
                if (link is! Map) continue;
                final target = link['link'] as String?;
                if (target != null && !results.containsKey(target)) {
                  results[target] = StreamPlaybackHint(
                    referrer: 'https://allanime.day',
                    extraHeaders: {'User-Agent': _userAgent},
                  );
                }
              }
            }
          }
        } catch (e) {
          debugPrint('[AllAnime] clock resolve error: $e');
        }
      } else {
        final resolved = await _resolveWithYtdl(c.url);
        if (resolved != c.url && !results.containsKey(resolved)) {
          results[resolved] = StreamPlaybackHint(
            referrer: c.url.contains('ok.ru') ? 'https://ok.ru/' : _referer,
            extraHeaders: {'User-Agent': _userAgent},
          );
        }
        // Always add the original embed URL as fallback
        if (!results.containsKey(c.url)) {
          results[c.url] = StreamPlaybackHint(
            referrer: c.url.contains('ok.ru') ? 'https://ok.ru/' : _referer,
            extraHeaders: {'User-Agent': _userAgent},
          );
        }
      }
    }

    if (results.isEmpty) throw Exception('No playable streams found');
    return results;
  }

  /// Resolve an embed URL to a direct media URL using yt-dlp.
  static Future<String> _resolveWithYtdl(String url) async {
    final commands = [
      ['yt-dlp', '-g', '--no-warnings', url],
      ['python', '-m', 'yt_dlp', '-g', '--no-warnings', url],
    ];
    for (final cmd in commands) {
      try {
        final result = await Process.run(cmd[0], cmd.sublist(1))
            .timeout(const Duration(seconds: 15));
        if (result.exitCode == 0) {
          final lines = (result.stdout as String).trim().split('\n');
          if (lines.isNotEmpty && lines.first.isNotEmpty) {
            debugPrint('[AllAnime] yt-dlp resolved $url → ${lines.first}');
            return lines.first;
          }
        }
      } catch (e) {
        debugPrint('[AllAnime] yt-dlp cmd=$cmd error=$e');
      }
    }
    return url;
  }

  /// Decrypt the `tobeparsed` field from AllAnime API response.
  /// Matches the bash `process_response()` function and Python `decrypt_tobeparsed()`.
  String? _decryptTobeparsed(String b64) {
    try {
      final raw = base64.decode(b64);
      if (raw.length < 14) return null;

      // IV = bytes[1..12] (12 bytes) + "00000002" (4 bytes) = 16 bytes total
      final iv = raw.sublist(1, 13);
      final ivList = [...iv, 0x00, 0x00, 0x00, 0x02];
      final aesIv = encrypt.IV(Uint8List.fromList(ivList));

      // Key = SHA256("Xot36i3lK3:v1") as 32 bytes
      final keyBytes = sha256.convert(utf8.encode('Xot36i3lK3:v1')).bytes;
      final aesKey = encrypt.Key(Uint8List.fromList(keyBytes));

      // Ciphertext = bytes[13..(length-16)]
      final ctLen = raw.length - 13 - 16;
      if (ctLen <= 0) return null;
      final ciphertext = raw.sublist(13, 13 + ctLen);

      final encrypter = encrypt.Encrypter(
        encrypt.AES(aesKey, mode: encrypt.AESMode.ctr, padding: null),
      );

      final decrypted = encrypter.decryptBytes(
        encrypt.Encrypted(Uint8List.fromList(ciphertext)),
        iv: aesIv,
      );

      return utf8.decode(decrypted, allowMalformed: true);
    } catch (e) {
      debugPrint('AllAnime decrypt error: $e');
      return null;
    }
  }

  /// Decode a hex-encoded AllAnime source URL (starts with `--`).
  /// Returns an absolute URL — prepends the API base for relative paths.
  String? _decodeSourceUrl(String url) {
    if (!url.startsWith('--')) return url;

    final hexPairs = url.substring(2);
    final buf = StringBuffer();
    for (int i = 0; i < hexPairs.length; i += 2) {
      if (i + 1 >= hexPairs.length) break;
      final pair = hexPairs.substring(i, i + 2);
      buf.write(_hexDecodeMap[pair] ?? '');
    }
    var decoded = buf.toString();
    // Replace /clock? with /clock.json? (bash does this)
    decoded = decoded.replaceAll('/clock?', '/clock.json?');
    // Prepend base URL for relative paths
    if (decoded.startsWith('/')) {
      decoded = 'https://allanime.day$decoded';
    }
    return decoded;
  }

  static const Map<String, String> _hexDecodeMap = {
    '08': '0', '09': '1', '0a': '2', '0b': '3', '0c': '4', '0d': '5', '0e': '6', '0f': '7',
    '00': '8', '01': '9',
    '50': 'h', '51': 'i', '52': 'j', '53': 'k', '54': 'l', '55': 'm', '56': 'n', '57': 'o',
    '48': 'p', '49': 'q', '4a': 'r', '4b': 's', '4c': 't', '4d': 'u', '4e': 'v', '4f': 'w',
    '59': 'a', '5a': 'b', '5b': 'c', '5c': 'd', '5d': 'e', '5e': 'f', '5f': 'g',
    '60': 'X', '61': 'Y', '62': 'Z', '63': '[', '64': '\\', '65': ']', '66': '^', '67': '_',
    '68': 'P', '69': 'Q', '6a': 'R', '6b': 'S', '6c': 'T', '6d': 'U', '6e': 'V', '6f': 'W',
    '70': 'H', '71': 'I', '72': 'J', '73': 'K', '74': 'L', '75': 'M', '76': 'N', '77': 'O',
    '78': '@', '79': 'A', '7a': 'B', '7b': 'C', '7c': 'D', '7d': 'E', '7e': 'F', '7f': 'G',
    '40': 'x', '41': 'y', '42': 'z',
    '15': '-', '16': '.', '02': ':', '17': '/', '07': '?', '05': '=', '12': '*', '13': '+',
    '14': ',', '03': ';', '1b': '#', '46': '~', '19': '!', '1c': r'$', '1e': '&',
    '10': '(', '11': ')', '1d': '%',
  };
}
