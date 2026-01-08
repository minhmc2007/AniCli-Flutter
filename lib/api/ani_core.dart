import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class AniCore {
  static const String baseUrl = "https://api.allanime.day/api";
  static const String referer = "https://allmanga.to";
  static const String agent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";

  // --- 1. SEARCH ---
  static Future<List<AnimeModel>> search(String query) async {
    const String queryGql = r'''
    query($search: SearchInput, $limit: Int, $page: Int, $translationType: VaildTranslationTypeEnumType, $countryOrigin: VaildCountryOriginEnumType) {
    shows(search: $search, limit: $limit, page: $page, translationType: $translationType, countryOrigin: $countryOrigin) {
    edges { _id name thumbnail }
  }
  }
  ''';

  // Default to 'sub' like the script
  final variables = {
    "search": {"allowAdult": false, "allowUnknown": false, "query": query},
    "limit": 40,
    "page": 1,
    "translationType": "sub",
    "countryOrigin": "ALL"
  };

  try {
    final res = await _post(queryGql, variables);
    final List edges = res['data']['shows']['edges'];
    return edges.map((e) => AnimeModel.fromJson(e)).toList();
  } catch (e) {
    print("Search Error: $e");
    return [];
  }
  }

  // --- 2. GET EPISODES LIST ---
  // Port of `episodes_list_gql`
  static Future<List<String>> getEpisodes(String animeId) async {
    const String queryGql = r'''
    query ($showId: String!) {
    show( _id: $showId ) {
    _id
    availableEpisodesDetail
  }
  }
  ''';

  try {
    final res = await _post(queryGql, {"showId": animeId});
    // The API returns distinct arrays for sub/dub. We focus on sub for now.
    final details = res['data']['show']['availableEpisodesDetail']['sub'] as List;
    // Reverse to get 1, 2, 3... order usually
    return details.reversed.map((e) => e.toString()).toList();
  } catch (e) {
    print("Episode List Error: $e");
    return [];
  }
  }

  // --- 3. GET STREAM LINK (The Hard Part) ---
  // Port of `get_episode_url` and `provider_init`
  static Future<String?> getStreamUrl(String animeId, String episodeNum) async {
    const String queryGql = r'''
    query ($showId: String!, $translationType: VaildTranslationTypeEnumType!, $episodeString: String!) {
    episode( showId: $showId translationType: $translationType episodeString: $episodeString ) {
    episodeString sourceUrls
  }
  }
  ''';

  try {
    final res = await _post(queryGql, {
      "showId": animeId,
      "translationType": "sub",
      "episodeString": episodeNum
    });

    final List sources = res['data']['episode']['sourceUrls'];

    // We look for the sourceUrl string. The shell script prioritizes certain providers.
    // We will look for the first valid one we can decrypt.
    for (var source in sources) {
      String url = source['sourceUrl'];
      // In the bash script, it processes the hex ID.
      if (url.startsWith("--")) {
        url = url.substring(2); // Remove '--'
        // Identify the ID (the hex part)
        // The script logic is complex here, but usually, AllAnime serves
        // a specific hash we need to decrypt into a URL.

        String decrypted = _decryptSource(url);

        // If it's a clock.json, we might need further processing,
        // but often the decrypted URL is the m3u8 or mp4 directly.
        if (decrypted.startsWith("http")) {
          return decrypted.replaceFirst("/clock", "/clock.json");
        }
      }
    }
  } catch (e) {
    print("Stream Fetch Error: $e");
  }
  return null;
  }

  // --- 4. PLAY IN MPV ---
  // Replaces the `play_episode` bash function
  static Future<void> playInMpv(String url) async {
    print("Launching MPV with: $url");
    try {
      await Process.start(
        'mpv',
        [
          url,
          '--referrer=$referer',
          '--force-media-title=Ani-Cli-Flutter',
          // '--fs' // Optional: start fullscreen
        ],
        mode: ProcessStartMode.detached, // Don't block the UI
      );
    } catch (e) {
      print("Could not launch MPV. Is it installed? Error: $e");
    }
  }

  // --- HELPERS ---

  static Future<Map<String, dynamic>> _post(String query, Map<String, dynamic> vars) async {
    final uri = Uri.parse("$baseUrl?variables=${jsonEncode(vars)}&query=$query");
    final response = await http.get(uri, headers: {"User-Agent": agent, "Referer": referer});
    if (response.statusCode == 200) return jsonDecode(response.body);
    throw Exception("API Error ${response.statusCode}");
  }

  // The "Decrypt" Magic (Ported from `provider_init` sed regex map)
  static String _decryptSource(String input) {
    // This maps the hex-like codes to characters based on the bash script's `sed` commands
    // Example: s/^01$/9/g means "01" becomes "9"
    const Map<String, String> map = {
      "01": "9", "08": "0", "09": "1", "0a": "2", "0b": "3", "0c": "4", "0d": "5", "0e": "6", "0f": "7", "00": "8",
      "50": "h", "51": "i", "52": "j", "53": "k", "54": "l", "55": "m", "56": "n", "57": "o", "58": "p", "59": "a",
      "5a": "b", "5b": "c", "5c": "d", "5d": "e", "5e": "f", "5f": "g",
      "60": "X", "61": "Y", "62": "Z", "63": "[", "64": "\\", "65": "]", "66": "^", "67": "_", "68": "P", "69": "Q",
      "6a": "R", "6b": "S", "6c": "T", "6d": "U", "6e": "V", "6f": "W",
      "70": "H", "71": "I", "72": "J", "73": "K", "74": "L", "75": "M", "76": "N", "77": "O", "78": "@", "79": "A",
      "7a": "B", "7b": "C", "7c": "D", "7d": "E", "7e": "F", "7f": "G",
      "40": "x", "41": "y", "42": "z", "48": "p", "49": "q", "4a": "r", "4b": "s", "4c": "t", "4d": "u", "4e": "v", "4f": "w",
      "15": "-", "16": ".", "02": ":", "17": "/", "07": "?", "05": "=", "12": "*", "13": "+", "14": ",", "03": ";",
    };

    // Split string into chunks of 2
    StringBuffer buffer = StringBuffer();
    for (int i = 0; i < input.length; i += 2) {
      if (i + 2 <= input.length) {
        String segment = input.substring(i, i + 2);
        buffer.write(map[segment.toLowerCase()] ?? ""); // Fallback to empty if not found (or handle error)
      }
    }
    return buffer.toString();
  }
}

class AnimeModel {
  final String id;
  final String name;
  final String? thumbnail;

  AnimeModel({required this.id, required this.name, this.thumbnail});

  factory AnimeModel.fromJson(Map<String, dynamic> json) {
    return AnimeModel(
      id: json['_id'] ?? json['id'] ?? '', // Handle both API and local storage keys
      name: json['name'] ?? 'Unknown',
      thumbnail: json['thumbnail'],
    );
  }

  // NEW: Needed for saving to SharedPrefs
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'thumbnail': thumbnail,
  };

  String get fullImageUrl {
    if (thumbnail == null) return "https://via.placeholder.com/300x450";
      if (thumbnail!.startsWith("http")) return thumbnail!;
      return "https://wp.youtube-anime.com/alldata/$thumbnail";
  }
}
