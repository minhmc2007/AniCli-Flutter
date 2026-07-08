import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:pointycastle/export.dart';

final String _apiUrl = 'https://api.allanime.day/api';
final String _cryptoKey = 'Xot36i3lK3:v1';

final Map<String, String> _apiHeaders = {
  'accept': '*/*',
  'origin': 'https://allmanga.to',
  'referer': 'https://allmanga.to/',
  'user-agent':
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
};

String _decryptAesCtr(String encoded) {
  final keyBytes = Uint8List.fromList(sha256.convert(utf8.encode(_cryptoKey)).bytes);
  final raw = base64.decode(encoded);
  final nonce = raw.sublist(1, 13);
  final ctLen = raw.length - 13 - 16;
  final ciphertext = raw.sublist(13, 13 + ctLen);

  final counter = Uint8List(16);
  counter.setAll(0, nonce);
  counter[15] = 0x02;

  final cipher = CTRStreamCipher(AESEngine())
    ..init(false, ParametersWithIV(KeyParameter(keyBytes), counter));

  final out = Uint8List(ciphertext.length);
  cipher.processBytes(ciphertext, 0, ciphertext.length, out, 0);
  return utf8.decode(out);
}

Future<void> _tryPost(String label, String query, Map<String, dynamic> variables) async {
  final hash = sha256.convert(utf8.encode(query)).toString();
  final extensions = {'persistedQuery': {'version': 1, 'sha256Hash': hash}};
  print('\n=== $label ===');
  print('variables: ${jsonEncode(variables)}');
  try {
    final res = await http.post(
      Uri.parse(_apiUrl),
      headers: {..._apiHeaders, 'Content-Type': 'application/json'},
      body: jsonEncode({'query': query, 'variables': variables, 'extensions': extensions}),
    );
    print('Status: ${res.statusCode}');
    final body = res.body;
    print('Body: $body');

    // Try to find tobeparsed
    try {
      final data = jsonDecode(body);
      if (data is Map) {
        // Check different positions for tobeparsed
        final d = data['data'];
        if (d is Map) {
          final tp = d['tobeparsed'] as String? ?? d['_m'] as String?;
          if (tp != null && tp.length > 50) {
            print('\n>>> GOT TOBEPARSED BLOB! len=${tp.length}');
            try {
              final decrypted = _decryptAesCtr(tp);
              print('>>> Decrypted: ${decrypted.substring(0, decrypted.length.clamp(0, 500))}');
            } catch (e) {
              print('>>> Decryption failed: $e');
            }
          }
        }
      }
    } catch (_) {}
  } catch (e) {
    print('Error: $e');
  }
}

Future<void> main() async {
  // Test chapterPages exact match of old keiyoushi query
  await _tryPost(
    'chapterPages (exact old query)',
    r'query($id:String!,$translationType:VaildTranslationTypeMangaEnumType!,$chapterNum:String!){chapterPages(mangaId:$id,translationType:$translationType,chapterString:$chapterNum){edges{pictureUrls,pictureUrlHead}}}',
    {
      'id': '6428b81fdc89afaf61e3dda1',
      'translationType': 'sub',
      'chapterNum': '1',
    },
  );

  // Also test anime episode endpoint for comparison
  await _tryPost(
    'anime episode (for comparison)',
    r'query($showId:String!,$translationType:VaildTranslationTypeEnumType!,$episodeString:String!){episode(showId:$showId,translationType:$translationType,episodeString:$episodeString){episodeString,sourceUrls}}',
    {
      'showId': '6428b81fdc89afaf61e3dda1',
      'translationType': 'sub',
      'episodeString': '1',
    },
  );
}
