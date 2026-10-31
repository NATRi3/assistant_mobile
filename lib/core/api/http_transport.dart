import 'dart:async';
import 'dart:io';

import 'api_error.dart';

abstract interface class ApiTransport {
  Future<ApiResponse> send(ApiRequest request);
  void abortAll();
}

class ApiRequest {
  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final List<int>? body;
  const ApiRequest(this.method, this.uri, this.headers, this.body);
  @override
  String toString() => 'ApiRequest([redacted])';
}

class ApiResponse {
  final int statusCode;
  final Map<String, String> headers;
  final List<int> body;
  const ApiResponse(this.statusCode, this.headers, this.body);
  @override
  String toString() => 'ApiResponse([redacted])';
}

class HttpTransport implements ApiTransport {
  final Set<HttpClient> _active = {};
  @override
  Future<ApiResponse> send(ApiRequest request) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    _active.add(client);
    try {
      return await (() async {
        final req = await client.openUrl(request.method, request.uri);
        req.followRedirects = false;
        req.maxRedirects = 0;
        request.headers.forEach(req.headers.set);
        if (request.body != null) req.add(request.body!);
        final res = await req.close();
        final bytes = <int>[];
        await for (final chunk in res) {
          if (bytes.length + chunk.length > 262144) {
            throw const ApiError(0, 'RESPONSE_TOO_LARGE');
          }
          bytes.addAll(chunk);
        }
        final headers = <String, String>{};
        res.headers.forEach((k, v) => headers[k] = v.join(','));
        return ApiResponse(res.statusCode, headers, bytes);
      })().timeout(const Duration(seconds: 5));
    } on ApiError {
      rethrow;
    } catch (_) {
      throw const ApiError(0, 'TRANSPORT_UNAVAILABLE');
    } finally {
      client.close(force: true);
      _active.remove(client);
    }
  }

  @override
  void abortAll() {
    for (final c in _active) {
      c.close(force: true);
    }
    _active.clear();
  }
}
