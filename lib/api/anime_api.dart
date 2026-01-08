import 'dart:convert';
import 'package:http/http.dart' as http;

class AnimeApi {
  // Constants from the shell script
  static const String baseUrl = "https://api.allanime.day/api";
  static const String referer = "https://allmanga.to";
  static const String userAgent =
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";

  // Search Query (Ported from the shell script's $search_gql)
  static Future<List<Anime>> search(String query) async {
    const String searchGql = r'''
    query($search: SearchInput, $limit: Int, $page: Int, $translationType: VaildTranslationTypeEnumType, $countryOrigin: VaildCountryOriginEnumType) {
    shows(search: $search, limit: $limit, page: $page, translationType: $translationType, countryOrigin: $countryOrigin) {
    edges {
    _id
    name
    thumbnail
    availableEpisodes
  }
  }
  }
  ''';

  final variables = {
    "search": {"allowAdult": false, "allowUnknown": false, "query": query},
    "limit": 40,
    "page": 1,
    "translationType": "sub",
    "countryOrigin": "ALL"
  };

  try {
    final response = await http.get(
      Uri.parse("$baseUrl?variables=${jsonEncode(variables)}&query=$searchGql"),
      headers: {
        "User-Agent": userAgent,
        "Referer": referer,
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final List edges = data['data']['shows']['edges'];
      return edges.map((e) => Anime.fromJson(e)).toList();
    }
  } catch (e) {
    print("Error fetching anime: $e");
  }
  return [];
  }
}

class Anime {
  final String id;
  final String name;
  final String? thumbnail;
  final dynamic availableEpisodes;

  Anime({required this.id, required this.name, this.thumbnail, this.availableEpisodes});

  factory Anime.fromJson(Map<String, dynamic> json) {
    return Anime(
      id: json['_id'] ?? '',
      name: json['name'] ?? 'Unknown',
      thumbnail: json['thumbnail'], // AllAnime thumbnails often need a base URL prepended
      availableEpisodes: json['availableEpisodes'],
    );
  }

  // AllAnime thumbnails usually reside here
  String get fullImageUrl => thumbnail != null
  ? "https://wp.youtube-anime.com/alldata/$thumbnail"
  : "https://via.placeholder.com/300x450";
}
