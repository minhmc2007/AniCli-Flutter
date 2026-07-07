import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:crypto/crypto.dart';
import 'provider_base.dart';

class AllAnimeProvider extends AnimeProvider {
  @override
  String get name => 'allanime';

  @override
  String get providerId => 'allanime';

  static const String _baseUrl = 'https://api.allanime.day/api';
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  static const String _gqlSearch = '''
query (\$search: SearchInput) {
  shows(search: \$search) {
    edges {
      _id
      name
      availableEpisodesDetail
      thumbnail
    }
  }
}
''';

  static const String _gqlEpisodeSources = '''
query (\$showId: String!, \$translationType: TranslationType!) {
  episode(showId: \$showId, translationType: \$translationType) {
    episodeInfo {
      episodeString
      sourceUrls
      notes
    }
  }
}
''';

  Map<String, String> get _headers => {
        'User-Agent': _userAgent,
        'Referer': 'https://allanime.to/',
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
        'query': _gqlSearch,
        'variables': {
          'search': {
            'allowAdult': true,
            'searchTerm': query,
            'limit': 40,
          },
        },
      }),
    );
    if (!isHttpOk(res.statusCode)) {
      throw Exception('AllAnime GraphQL search failed: ${res.statusCode}');
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

      final detailRaw = node['availableEpisodesDetail'];
      String? epSummary;
      if (detailRaw is String && detailRaw.isNotEmpty) {
        try {
          final detail = jsonDecode(detailRaw) as Map<String, dynamic>;
          final subCount = (detail['sub'] as List?)?.length ?? 0;
          final dubCount = (detail['dub'] as List?)?.length ?? 0;
          final total = subCount + dubCount;
          if (total > 0) epSummary = '${subCount}s/${dubCount}d';
        } catch (_) {}
      }

      final parts = <String>[name];
      if (epSummary != null) parts.add(epSummary);

      return SelectionOption(
        key: showId,
        label: parts.join(' · '),
        title: name,
        thumbnail: (node['thumbnail'] as String? ?? '').trim(),
        extraData: {
          '_id': showId,
          'name': name,
          'availableEpisodesDetail': detailRaw,
        },
      );
    }).toList();
  }

  @override
  Future<List<String>> episodesList(String showId, String mode) async {
    final id = showId.trim();
    if (id.isEmpty) throw Exception('Empty AllAnime show ID');

    final wantDub = normalizeTranslationType(mode) == 'dub';
    final gqlMode = wantDub ? 'dub' : 'sub';

    final res = await http.post(
      Uri.parse(_baseUrl),
      headers: {
        ..._headers,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'query': _gqlEpisodeSources,
        'variables': {
          'showId': id,
          'translationType': gqlMode,
        },
      }),
    );
    if (!isHttpOk(res.statusCode)) {
      throw Exception('AllAnime episodes failed: ${res.statusCode}');
    }

    final body = jsonDecode(res.body);
    final epInfo = (body['data'] as Map<String, dynamic>?)
            ?['episode']?['episodeInfo'] as List? ??
        [];

    if (epInfo.isEmpty) {
      final fallback = await _fallbackEpisodesFromDetail(id, wantDub);
      if (fallback.isEmpty) throw Exception('No episodes found');
      return fallback;
    }

    final eps = epInfo.map((e) {
      final raw = (e['episodeString'] as String? ?? '').trim();
      return int.tryParse(raw) ?? 0;
    }).where((e) => e > 0).toSet().toList()
      ..sort();

    if (eps.isEmpty) throw Exception('No valid episode numbers');
    return eps.map((e) => e.toString()).toList();
  }

  Future<List<String>> _fallbackEpisodesFromDetail(String showId, bool wantDub) async {
    final res = await http.post(
      Uri.parse(_baseUrl),
      headers: {
        ..._headers,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'query': r'''
query ($showId: String!) {
  show(_id: $showId) {
    availableEpisodesDetail
  }
}
''',
        'variables': {'showId': showId},
      }),
    );
    if (!isHttpOk(res.statusCode)) return [];

    final body = jsonDecode(res.body);
    final detailRaw = (body['data'] as Map<String, dynamic>?)
        ?['show']?['availableEpisodesDetail'];
    if (detailRaw is! String || detailRaw.isEmpty) return [];

    try {
      final detail = jsonDecode(detailRaw) as Map<String, dynamic>;
      final key = wantDub ? 'dub' : 'sub';
      final eps = detail[key] as List? ?? [];
      return eps.map((e) => e.toString()).toList()
        ..sort((a, b) => int.parse(a).compareTo(int.parse(b)));
    } catch (_) {
      return [];
    }
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

    final wantDub = normalizeTranslationType(mode) == 'dub';
    final gqlMode = wantDub ? 'dub' : 'sub';

    final res = await http.post(
      Uri.parse(_baseUrl),
      headers: {
        ..._headers,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'query': _gqlEpisodeSources,
        'variables': {
          'showId': showId,
          'translationType': gqlMode,
        },
      }),
    );
    if (!isHttpOk(res.statusCode)) {
      throw Exception('AllAnime sources failed: ${res.statusCode}');
    }

    final body = jsonDecode(res.body);
    final epInfoList = (body['data'] as Map<String, dynamic>?)
            ?['episode']?['episodeInfo'] as List? ??
        [];

    Map<String, dynamic>? targetEp;
    for (final ep in epInfoList) {
      final epStr = (ep['episodeString'] as String? ?? '').trim();
      if (int.tryParse(epStr) == epNo) {
        targetEp = ep as Map<String, dynamic>;
        break;
      }
    }

    if (targetEp == null) {
      throw Exception('Episode $epNo not found in source list');
    }

    final sourceUrlsRaw = targetEp['sourceUrls'] as String? ?? '';
    final notes = targetEp['notes'] as String? ?? '';

    final sourceUrls = sourceUrlsRaw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (sourceUrls.isEmpty) throw Exception('No source URLs for episode $epNo');

    final usesClock = notes.toLowerCase().contains('clock') ||
        sourceUrls.any((u) => u.contains('clock') || u.contains(':'));
    final usesLegacy = notes.toLowerCase().contains('legacy') ||
        sourceUrls.any((u) => u.contains('?') && !u.contains('/clock'));

    if (usesClock) {
      return _decryptClockSources(sourceUrls, showId, epNo);
    } else if (usesLegacy) {
      return _decryptLegacySources(sourceUrls, showId, epNo);
    } else {
      final results = <String, StreamPlaybackHint>{};
      for (final url in sourceUrls) {
        if (url.isNotEmpty && !results.containsKey(url)) {
          results[url] = StreamPlaybackHint(
            referrer: 'https://allanime.to/',
            extraHeaders: {'User-Agent': _userAgent},
          );
        }
      }
      if (results.isEmpty) throw Exception('No playable streams found');
      return results;
    }
  }

  Map<String, StreamPlaybackHint> _decryptClockSources(
    List<String> sourceUrls,
    String showId,
    int epNo,
  ) {
    final results = <String, StreamPlaybackHint>{};

    for (final encoded in sourceUrls) {
      final clean = encoded.trim();
      if (clean.isEmpty) continue;

      if (clean.startsWith('http')) {
        final cleaned = clean.replaceAll(RegExp(r'^[a-z]+://clock[a-z]*\d*\.'), 'https://');
        results[cleaned] = StreamPlaybackHint(
          referrer: 'https://allanime.to/',
          extraHeaders: {'User-Agent': _userAgent},
        );
        continue;
      }

      try {
        final parts = clean.split(':');
        if (parts.length < 4) {
          results[clean] = StreamPlaybackHint(extraHeaders: {'User-Agent': _userAgent});
          continue;
        }

        final hexKey = parts[0];
        final hexIv = parts[1];
        final hexCiphertext = parts[2];

        final key = _parseHexString(hexKey);
        final iv = _parseHexString(hexIv);
        final ciphertext = _parseHexString(hexCiphertext);

        if (key.length != 32 || iv.length != 16 || ciphertext.isEmpty) {
          debugPrint('AllAnime clock: invalid key/iv lengths');
          continue;
        }

        final aesKey = encrypt.Key(Uint8List.fromList(key));
        final aesIv = encrypt.IV(Uint8List.fromList(iv));
        final encrypter = encrypt.Encrypter(
          encrypt.AES(aesKey, mode: encrypt.AESMode.ctr, padding: null),
        );

        final decrypted = encrypter.decryptBytes(
          encrypt.Encrypted(Uint8List.fromList(ciphertext)),
          iv: aesIv,
        );

        var decoded = utf8.decode(decrypted, allowMalformed: true);

        if (decoded.startsWith('{') && decoded.contains('"sourceUrl"')) {
          try {
            final jsonObj = jsonDecode(decoded) as Map<String, dynamic>;
            final sourceUrl = (jsonObj['sourceUrl'] as String? ?? '').trim();
            if (sourceUrl.isNotEmpty) {
              decoded = sourceUrl;
            }
          } catch (_) {}
        }

        if (decoded.isNotEmpty && !results.containsKey(decoded)) {
          results[decoded] = StreamPlaybackHint(
            referrer: 'https://allanime.to/',
            extraHeaders: {'User-Agent': _userAgent},
          );
        } else {
          results[decoded] = StreamPlaybackHint(extraHeaders: {'User-Agent': _userAgent});
        }
      } catch (e) {
        debugPrint('AllAnime clock decrypt error: $e');
      }
    }

    if (results.isEmpty) throw Exception('Clock decryption failed');
    return results;
  }

  Map<String, StreamPlaybackHint> _decryptLegacySources(
    List<String> sourceUrls,
    String showId,
    int epNo,
  ) {
    final results = <String, StreamPlaybackHint>{};

    for (final encoded in sourceUrls) {
      final clean = encoded.trim();
      if (clean.isEmpty) continue;

      if (clean.startsWith('http')) {
        results[clean] = StreamPlaybackHint(referrer: 'https://allanime.to/', extraHeaders: {'User-Agent': _userAgent});
        continue;
      }

      try {
        final parts = clean.split('?');
        if (parts.length < 2) {
          results[clean] = StreamPlaybackHint(extraHeaders: {'User-Agent': _userAgent});
          continue;
        }

        final b64Part = parts[0].trim();
        final aadPart = parts[1].trim();
        if (b64Part.isEmpty || aadPart.isEmpty) continue;

        final encrypted = base64Url.decode(b64Part.padRight(((b64Part.length + 3) ~/ 4) * 4, '='));
        final aad = base64Url.decode(aadPart.padRight(((aadPart.length + 3) ~/ 4) * 4, '='));

        final customCipherKey = _computeLegacyKey(showId, epNo);

        final combined = List<int>.from(customCipherKey)
          ..addAll(aad);

        final hash = sha256.convert(Uint8List.fromList(combined));
        final hashBytes = hash.bytes;

        final aesKey = encrypt.Key(Uint8List.fromList(hashBytes.take(32).toList()));
        final aesIv = encrypt.IV(Uint8List.fromList(List.filled(16, 0)));
        final encrypter = encrypt.Encrypter(
          encrypt.AES(aesKey, mode: encrypt.AESMode.ctr, padding: null),
        );

        final decrypted = encrypter.decryptBytes(
          encrypt.Encrypted(Uint8List.fromList(encrypted)),
          iv: aesIv,
        );

        var decoded = utf8.decode(decrypted, allowMalformed: true);

        if (decoded.startsWith('{')) {
          try {
            final jsonObj = jsonDecode(decoded) as Map<String, dynamic>;
            final src = (jsonObj['sourceUrl'] as String? ?? '').trim();
            if (src.isNotEmpty) decoded = src;
          } catch (_) {}
        }

        if (decoded.isNotEmpty && !results.containsKey(decoded)) {
          results[decoded] = StreamPlaybackHint(
            referrer: 'https://allanime.to/',
            extraHeaders: {'User-Agent': _userAgent},
          );
        }
      } catch (e) {
        debugPrint('AllAnime legacy decrypt error: $e');
      }
    }

    if (results.isEmpty) throw Exception('Legacy decryption failed');
    return results;
  }

  List<int> _computeLegacyKey(String showId, int epNo) {
    final seed = _hashString(showId) ^ epNo;
    final rng = Random(seed);
    final key = List<int>.generate(32, (_) => rng.nextInt(256));
    return key;
  }

  int _hashString(String s) {
    int h = 0;
    for (final c in s.runes) {
      h = ((h << 5) - h) + c;
      h = h & h;
    }
    return h;
  }

  List<int> _parseHexString(String hex) {
    final clean = hex.replaceAll(RegExp(r'\s+'), '');
    if (clean.length % 2 != 0) throw FormatException('Odd hex length: $clean');
    final bytes = <int>[];
    for (int i = 0; i < clean.length; i += 2) {
      bytes.add(int.parse(clean.substring(i, i + 2), radix: 16));
    }
    return bytes;
  }
}
