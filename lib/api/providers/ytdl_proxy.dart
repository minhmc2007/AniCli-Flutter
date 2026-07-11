import 'dart:io';
import 'package:flutter/foundation.dart';

class YtdlProxy {
  static HttpServer? _server;
  static int _port = 0;

  static int get port => _port;
  static bool get isRunning => _server != null;

  static Future<void> start() async {
    if (_server != null) return;
    _server = await HttpServer.bind('127.0.0.1', 0);
    _port = _server!.port;
    _server!.listen(_onRequest);
    debugPrint('[YtdlProxy] started on port $_port');
  }

  static Future<void> ensureStarted() async {
    if (_server != null) return;
    await start();
  }

  static String proxyUrl(String embedUrl) {
    if (_server == null) return embedUrl;
    return 'http://127.0.0.1:$_port/proxy?url=${Uri.encodeComponent(embedUrl)}';
  }

  static final Map<String, String> _headers = {};

  static Future<void> setHeaders(Map<String, String> h) async {
    _headers.clear();
    _headers.addAll(h);
    if (_server == null) await start();
  }

  static void _onRequest(HttpRequest request) {
    final urlParam = request.uri.queryParameters['url'];
    if (urlParam == null || urlParam.isEmpty) {
      request.response.statusCode = 400;
      request.response.close();
      return;
    }
    _pipeFromYtdl(request, urlParam);
  }

  static Future<void> _pipeFromYtdl(HttpRequest request, String embedUrl) async {
    final referer = _headers['Referer'] ?? '';
    final ua = _headers['User-Agent'] ?? 'Mozilla/5.0';

    final args = <String>[
      '-o', '-',
      '--add-headers', 'Referer:$referer',
      '--add-headers', 'User-Agent:$ua',
      embedUrl,
    ];

    debugPrint('[YtdlProxy] spawning yt-dlp $embedUrl');

    try {
      final proc = await Process.start('yt-dlp', args,
          runInShell: true,
          mode: ProcessStartMode.normal);

      request.response.headers.set('Content-Type', 'video/mp4');
      request.response.headers.set('Transfer-Encoding', 'chunked');
      request.response.headers.set('Cache-Control', 'no-cache');
      request.response.statusCode = 200;

      await request.response.addStream(proc.stdout);
      final exitCode = await proc.exitCode;
      debugPrint('[YtdlProxy] yt-dlp exit code: $exitCode');

      try { await request.response.close(); } catch (_) {}
    } catch (e) {
      debugPrint('[YtdlProxy] yt-dlp failed: $e, falling back to direct pipe');
      await _pipeDirect(request, embedUrl);
    }
  }

  static Future<void> _pipeDirect(HttpRequest request, String url) async {
    final client = HttpClient()
      ..badCertificateCallback = (cert, host, port) => true;
    try {
      final req = await client.getUrl(Uri.parse(url));
      for (final e in _headers.entries) {
        req.headers.set(e.key, e.value);
      }
      final res = await req.close();
      request.response.statusCode = res.statusCode;
      if (res.statusCode == 200) {
        const keep = {'content-type', 'content-length', 'cache-control'};
        res.headers.forEach((name, values) {
          if (values.isNotEmpty && keep.contains(name.toLowerCase())) {
            request.response.headers.set(name, values.first);
          }
        });
        await res.pipe(request.response);
      } else {
        await request.response.close();
      }
    } catch (e) {
      request.response.statusCode = 502;
      await request.response.close();
    } finally {
      client.close(force: true);
    }
  }

  static void stop() {
    _server?.close(force: true);
    _server = null;
    _port = 0;
  }
}
