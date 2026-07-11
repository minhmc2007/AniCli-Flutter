import 'dart:convert';
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

    final res = await http.get(
      Uri.parse('$_baseUrl/api/search/${Uri.encodeComponent(query)}'),
      headers: _headers,
    );
    if (!isHttpOk(res.statusCode)) throw Exception('Anipub search failed: ${res.statusCode}');

    final decoded = jsonDecode(res.body);
    final items = decoded is List ? decoded : [];
    if (items.isEmpty) throw Exception('No results for "$query"');

    return items.map<SelectionOption>((item) {
      final slug = (item['finder'] as String? ?? '').trim();
      final title = (item['Name'] as String? ?? '').trim();
      final id = item['Id'] as int? ?? 0;

      return SelectionOption(
        key: id > 0 ? id.toString() : slug,
        label: title,
        title: title,
        thumbnail: item['Image'] as String?,
        extraData: {
          'slug': slug,
          'title': title,
          'id': id,
        },
      );
    }).toList();
  }

  @override
  Future<List<String>> episodesList(String showId, String mode) async {
    final slug = showId.trim();
    if (slug.isEmpty) throw Exception('Empty Anipub slug');

    final res = await http.get(
      Uri.parse('$_baseUrl/AniPlayer/$slug/0'),
      headers: _headers,
    );
    if (!isHttpOk(res.statusCode)) throw Exception('Anipub detail failed: ${res.statusCode}');

    final html = res.body;
    final epDataMatches = RegExp(r'data-ep="(\d+)"').allMatches(html);
    final eps = epDataMatches.map((m) => int.parse(m.group(1)!)).toSet().toList()..sort();
    if (eps.isEmpty) throw Exception('No episodes found');

    return eps.map((e) => (e + 1).toString()).toList();
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

    final epIndex = epNo - 1;

    final res = await http.get(
      Uri.parse('$_baseUrl/AniPlayer/$slug/$epIndex'),
      headers: _headers,
    );
    if (!isHttpOk(res.statusCode)) {
      throw Exception('Anipub player page failed: ${res.statusCode}');
    }

    final html = res.body;
    final iframeMatch = RegExp(
      r'<iframe[^>]*src="https://www\.anipub\.xyz/video/(\d+)/(sub|dub)"',
      caseSensitive: false,
    ).firstMatch(html);
    if (iframeMatch == null) throw Exception('Video iframe not found');

    final videoId = iframeMatch.group(1)!;
    final videoLang = iframeMatch.group(2)!;

    final videoRes = await http.get(
      Uri.parse('https://www.anipub.xyz/video/$videoId/$videoLang'),
      headers: _headers,
    );
    if (!isHttpOk(videoRes.statusCode)) {
      throw Exception('Anipub video page failed: ${videoRes.statusCode}');
    }

    final videoHtml = videoRes.body;
    final megaMatch = RegExp(
      r'<iframe[^>]*src="(https://megaplay\.buzz[^"]+)"',
      caseSensitive: false,
    ).firstMatch(videoHtml);
    if (megaMatch == null) throw Exception('MegaPlay iframe not found');

    final megaUrl = megaMatch.group(1)!;
    return {megaUrl: StreamPlaybackHint(referrer: 'https://www.anipub.xyz/')};
  }
}
