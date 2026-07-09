import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

class HlsProxy {
  static HttpServer? _server;
  static int _port = 0;
  static late HttpClient _client;

  static int get port => _port;
  static bool get isRunning => _server != null;

  static Future<void> start() async {
    if (_server != null) return;
    _client = HttpClient()
      ..badCertificateCallback = (cert, host, port) => true;
    _server = await HttpServer.bind('127.0.0.1', 0);
    _port = _server!.port;
    _server!.listen(_onRequest);
  }

  static String proxyUrl(String targetUrl) {
    if (_server == null) return targetUrl;
    return 'http://127.0.0.1:$_port/proxy?url=${Uri.encodeComponent(targetUrl)}';
  }

  static void _onRequest(HttpRequest request) {
    final raw = request.uri.query;
    final urlParam = request.uri.queryParameters['url'];
    debugPrint('[HlsProxy] request: $raw -> $urlParam');
    if (urlParam == null || urlParam.isEmpty) {
      request.response.statusCode = 400;
      request.response.close();
      return;
    }
    _pipeRequest(request, urlParam);
  }

  static final Map<String, String> _headers = {};

  static Future<void> setHeaders(Map<String, String> h) async {
    _headers.clear();
    _headers.addAll(h);
    if (_server == null) await start();
  }

  static Future<HttpClientResponse> _fetch(String url) async {
    final req = await _client.getUrl(Uri.parse(url));
    for (final e in _headers.entries) {
      req.headers.set(e.key, e.value);
    }
    return req.close();
  }

  static void _pipeRequest(HttpRequest request, String targetUrl) async {
    debugPrint('[HlsProxy] proxying $targetUrl');
    debugPrint('[HlsProxy] headers=$_headers');
    try {
      final res = await _fetch(targetUrl);
      debugPrint('[HlsProxy] CDN status=${res.statusCode}');

      request.response.statusCode = res.statusCode;

      // Forward CDN headers needed by the client
      void _forwardHeaders({bool skipContentLength = false}) {
        const keep = {'content-type', 'content-length', 'cache-control', 'etag', 'last-modified'};
        res.headers.forEach((name, values) {
          if (values.isNotEmpty && keep.contains(name.toLowerCase())) {
            if (!skipContentLength || name.toLowerCase() != 'content-length') {
              request.response.headers.set(name, values.first);
            }
          }
        });
      }

      final isManifest = targetUrl.endsWith('.m3u8');
      final contentType = res.headers.value('content-type') ?? '';
      debugPrint('[HlsProxy] isManifest=$isManifest contentType=$contentType');

      if (res.statusCode != 200) {
        final errBody = await res.transform(utf8.decoder).join();
        debugPrint('[HlsProxy] CDN error body=${errBody.length > 500 ? errBody.substring(0, 500) : errBody}');
        request.response.write(errBody);
      } else if (isManifest || contentType.contains('mpegurl') || contentType.contains('x-mpegurl')) {
        _forwardHeaders(skipContentLength: true);
        final body = await res.transform(utf8.decoder).join();
        debugPrint('[HlsProxy] playlist body=${body.substring(0, body.length.clamp(0, 500))}');

        // Check if this is a master playlist (contains #EXT-X-STREAM-INF)
        if (body.contains('#EXT-X-STREAM-INF:')) {
          final resolved = await _resolveFirstVariant(body, targetUrl);
          if (resolved != null) {
            debugPrint('[HlsProxy] resolved variant=${resolved.substring(0, resolved.length.clamp(0, 500))}');
            request.response.headers.set('content-type', 'application/vnd.apple.mpegurl');
            request.response.write(resolved);
          } else {
            final rewritten = _rewritePlaylist(body, targetUrl);
            debugPrint('[HlsProxy] rewritten master=${rewritten.substring(0, rewritten.length.clamp(0, 500))}');
            request.response.headers.set('content-type', 'application/vnd.apple.mpegurl');
            request.response.write(rewritten);
          }
        } else {
          final rewritten = _rewritePlaylist(body, targetUrl);
          debugPrint('[HlsProxy] rewritten media=${rewritten.substring(0, rewritten.length.clamp(0, 500))}');
          request.response.headers.set('content-type', 'application/vnd.apple.mpegurl');
          request.response.write(rewritten);
        }
      } else {
        debugPrint('[HlsProxy] piping segment response, content-type=$contentType length=${res.contentLength}');
        _forwardHeaders();
        await res.pipe(request.response);
      }
    } catch (e) {
      debugPrint('[HlsProxy] error: $e');
      if (request.response.statusCode == 200) {
        request.response.statusCode = 502;
      }
      try {
        request.response.write('Proxy error: $e');
      } catch (_) {}
    } finally {
      try { await request.response.close(); } catch (_) {}
      debugPrint('[HlsProxy] done');
    }
  }

  static Future<String?> _resolveFirstVariant(String masterBody, String masterUrl) async {
    final base = masterUrl.substring(0, masterUrl.lastIndexOf('/') + 1);
    final lines = masterBody.split('\n');

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final variantUrl = trimmed.startsWith('http') ? trimmed : '$base$trimmed';
      debugPrint('[HlsProxy] fetching variant: $variantUrl');
      try {
        final variantRes = await _fetch(variantUrl);
        if (variantRes.statusCode != 200) {
          debugPrint('[HlsProxy] variant fetch failed: ${variantRes.statusCode}');
          continue;
        }
        final variantBody = await variantRes.transform(utf8.decoder).join();
        debugPrint('[HlsProxy] variant body=${variantBody.substring(0, variantBody.length.clamp(0, 500))}');
        final rewritten = _rewritePlaylist(variantBody, variantUrl);
        return rewritten;
      } catch (e) {
        debugPrint('[HlsProxy] variant fetch error: $e');
        continue;
      }
    }
    return null;
  }

  static String _rewritePlaylist(String playlist, String baseUrl) {
    final base = baseUrl.substring(0, baseUrl.lastIndexOf('/') + 1);
    final lines = playlist.split('\n');
    final out = <String>[];
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        out.add(line);
        continue;
      }
      if (trimmed.startsWith('#')) {
        out.add(line);
        continue;
      }
      // Extract the URI (skip any leading whitespace/empty lines)
      final absolute = trimmed.startsWith('http') ? trimmed : '$base$trimmed';
      out.add('http://127.0.0.1:$_port/proxy?url=${Uri.encodeComponent(absolute)}');
    }
    return out.join('\n');
  }

  static void stop() {
    _client.close(force: true);
    _server?.close(force: true);
    _server = null;
    _port = 0;
  }
}
