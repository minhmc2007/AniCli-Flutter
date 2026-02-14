import 'dart:convert';
import 'package:http/http.dart' as http;

import 'ani_core.dart';

/// Vietnamese anime source via PhimAPI (Vietsub)
class ViAnimeCore {
  static const String baseUrl = "https://phimapi.com";
  static const String cdnImage = "https://phimimg.com";
  static const String referer = "https://phimapi.com";

  static Future<List<AnimeModel>> getTrending() async {
    return _fetchAnimeList(
      "$baseUrl/v1/api/danh-sach/hoat-hinh?page=1&country=nhat-ban&limit=40&sort_field=modified.time&sort_type=desc",
    );
  }

  static Future<List<AnimeModel>> search(String query) async {
    if (query.trim().isEmpty) return getTrending();
    final encoded = Uri.encodeQueryComponent(query.trim());
    return _fetchAnimeList(
      "$baseUrl/v1/api/tim-kiem?keyword=$encoded&limit=40",
    );
  }

  static Future<List<AnimeModel>> _fetchAnimeList(String url) async {
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {"User-Agent": "AniCli-Flutter/2.0"},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return [];

      final root = jsonDecode(response.body);
      final inner = root['data'] ?? root;
      final items = inner['items'];
      if (items == null || items is! List) return [];

      final cdn = inner['APP_DOMAIN_CDN_IMAGE'] ?? cdnImage;

      return items.map<AnimeModel>((item) {
        final slug = item['slug'] ?? '';
        String thumb = item['poster_url'] ?? item['thumb_url'] ?? '';
        if (thumb.isNotEmpty && !thumb.startsWith('http')) {
          thumb = thumb.startsWith('/') ? '$cdn$thumb' : '$cdn/$thumb';
        }
        return AnimeModel(
          id: slug,
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

  static Future<List<String>> getEpisodes(String slug) async {
    try {
      final response = await http.get(
        Uri.parse("$baseUrl/phim/$slug"),
        headers: {"User-Agent": "AniCli-Flutter/2.0"},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body);
      final episodes = data['episodes'] as List?;
      if (episodes == null || episodes.isEmpty) return [];

      final serverData = episodes[0]['server_data'] as List?;
      if (serverData == null || serverData.isEmpty) return [];

      return List.generate(serverData.length, (i) => '${i + 1}');
    } catch (e) {
      return [];
    }
  }

  static Future<String?> getStreamUrl(String slug, String episodeNum) async {
    try {
      final idx = int.tryParse(episodeNum) ?? 1;
      final response = await http.get(
        Uri.parse("$baseUrl/phim/$slug"),
        headers: {"User-Agent": "AniCli-Flutter/2.0"},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body);
      final episodes = data['episodes'] as List?;
      if (episodes == null || episodes.isEmpty) return null;

      final serverData = episodes[0]['server_data'] as List?;
      if (serverData == null) return null;

      final i = (idx - 1).clamp(0, serverData.length - 1);
      return serverData[i]['link_m3u8'] as String?;
    } catch (e) {
      return null;
    }
  }
}
