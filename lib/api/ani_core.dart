import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class AniCore {
  static const String baseUrl = "https://api.allanime.day/api";
  static const String referer = "https://allmanga.to";
  static const String agent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";

  // Shared Query for Search and Trending
  static const String _commonShowQuery = r'''
  query($search: SearchInput, $limit: Int, $page: Int, $translationType: VaildTranslationTypeEnumType, $countryOrigin: VaildCountryOriginEnumType) {
  shows(search: $search, limit: $limit, page: $page, translationType: $translationType, countryOrigin: $countryOrigin) {
  edges { _id name thumbnail }
}
}
''';

// --- 0. TRENDING / POPULAR ---
static Future<List<AnimeModel>> getTrending() async {
  final variables = {
    "search": {
      "allowAdult": false,
      "allowUnknown": false,
      "sortBy": "Top"
    },
    "limit": 40,
    "page": 1,
    "translationType": "sub",
    "countryOrigin": "ALL"
  };

  try {
    final res = await _post(_commonShowQuery, variables);
    final List edges = res['data']['shows']['edges'];
    return edges.map((e) => AnimeModel.fromJson(e)).toList();
  } catch (e) {
    print("Trending Error: $e");
    return [];
  }
}

// --- 1. SEARCH ---
static Future<List<AnimeModel>> search(String query) async {
  final variables = {
    "search": {
      "allowAdult": false,
      "allowUnknown": false,
      "query": query
    },
    "limit": 40,
    "page": 1,
    "translationType": "sub",
    "countryOrigin": "ALL"
  };

  try {
    final res = await _post(_commonShowQuery, variables);
    final List edges = res['data']['shows']['edges'];
    return edges.map((e) => AnimeModel.fromJson(e)).toList();
  } catch (e) {
    print("Search Error: $e");
    return [];
  }
}

// --- 2. GET EPISODES LIST ---
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
  final detailsMap = res['data']['show']['availableEpisodesDetail'];

  List details = [];
  if (detailsMap['sub'] != null) {
    details = detailsMap['sub'];
  } else if (detailsMap['dub'] != null) {
    details = detailsMap['dub'];
  } else if (detailsMap['raw'] != null) {
    details = detailsMap['raw'];
  }

  return details.reversed.map((e) => e.toString()).toList();
} catch (e) {
  print("Episode List Error: $e");
  return [];
}
}

// --- 3. GET STREAM LINK ---
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

  for (var source in sources) {
    String url = source['sourceUrl'];
    if (url.startsWith("--")) {
      url = url.substring(2);
      String decrypted = _decryptSource(url);
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
static Future<void> playInMpv(String url) async {
  print("Launching MPV with: $url");
  try {
    await Process.start(
      'mpv',
      [
        url,
        '--referrer=$referer',
        '--force-media-title=Ani-Cli-Flutter',
      ],
      mode: ProcessStartMode.detached,
    );
  } catch (e) {
    print("Could not launch MPV. Is it installed? Error: $e");
  }
}

// --- 5. DOWNLOAD EPISODE ---
static Future<void> downloadEpisode(String url, String fileName) async {
  print("Starting download for: $fileName");
  try {
    // Determine download directory based on OS
    String downloadDir = '${Platform.environment['HOME']}/Downloads/Anime';
    if (Platform.isWindows) {
      downloadDir = '${Platform.environment['USERPROFILE']}\\Downloads\\Anime';
    }

    await Directory(downloadDir).create(recursive: true);

    await Process.start(
      'aria2c',
      [
        url,
        '--referer=$referer',
        '--out=$fileName.mp4',
        '--dir=$downloadDir',
        '--split=16',
        '--max-connection-per-server=16',
      ],
      mode: ProcessStartMode.detached,
    );
  } catch (e) {
    print("Download failed: $e");
  }
}

// --- HELPERS ---

static Future<Map<String, dynamic>> _post(String query, Map<String, dynamic> vars) async {
  final uri = Uri.parse("$baseUrl?variables=${jsonEncode(vars)}&query=$query");
  final response = await http.get(uri, headers: {"User-Agent": agent, "Referer": referer});
  if (response.statusCode == 200) return jsonDecode(response.body);
  throw Exception("API Error ${response.statusCode}");
}

static String _decryptSource(String input) {
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

  StringBuffer buffer = StringBuffer();
  for (int i = 0; i < input.length; i += 2) {
    if (i + 2 <= input.length) {
      String segment = input.substring(i, i + 2);
      buffer.write(map[segment.toLowerCase()] ?? "");
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
      id: json['_id'] ?? json['id'] ?? '',
      name: json['name'] ?? 'Unknown',
      thumbnail: json['thumbnail'],
    );
  }

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
