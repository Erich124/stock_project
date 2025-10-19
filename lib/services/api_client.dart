// lib/services/api_client.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, SocketException;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

/// ApiClient
/// - Smart base URL resolution (Android emulator, desktop, web)
/// - Build-time override: --dart-define=API_BASE_URL=http://192.168.1.5:8000
/// - Timeouts & simple retries with exponential backoff
/// - Convenience wrappers for your backend endpoints
class ApiClient {
  /// Prefer passing your own in tests.
  final http.Client _http;

  /// Base URL like "http://10.0.2.2:8000"
  final String baseUrl;

  /// Request timeout per attempt.
  final Duration timeout;

  /// Number of retry attempts (in addition to the first try).
  final int maxRetries;

  /// Enable console logging.
  final bool debug;

  ApiClient({
    String? baseUrl,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 8),
    this.maxRetries = 1,
    this.debug = true,
  })  : baseUrl = baseUrl ?? _resolveBaseUrl(),
        _http = httpClient ?? http.Client() {
    if (debug) {
      // ignore: avoid_print
      print('[ApiClient] baseUrl=$baseUrl (resolved=$baseUrl)');
    }
  }

  /// Dispose underlying HTTP client (call in tests or when you own the lifecycle).
  void dispose() => _http.close();

  // ----------------------------
  // Public JSON helpers
  // ----------------------------

  Future<List<dynamic>> getJsonList(
      String path, {
        Map<String, String>? query,
        Map<String, String>? headers,
      }) async {
    final data = await _requestJson('GET', path, query: query, headers: headers);
    if (data is List) return data;
    throw StateError('Expected a JSON list from $path; got ${data.runtimeType}');
  }

  Future<Map<String, dynamic>> getJsonMap(
      String path, {
        Map<String, String>? query,
        Map<String, String>? headers,
      }) async {
    final data = await _requestJson('GET', path, query: query, headers: headers);
    if (data is Map<String, dynamic>) return data;
    throw StateError('Expected a JSON object from $path; got ${data.runtimeType}');
  }

  Future<Map<String, dynamic>> postJsonMap(
      String path, {
        Map<String, String>? query,
        Object? body, // Map or List, will be jsonEncoded
        Map<String, String>? headers,
      }) async {
    final data = await _requestJson('POST', path, query: query, body: body, headers: headers);
    if (data is Map<String, dynamic>) return data;
    throw StateError('Expected a JSON object from POST $path; got ${data.runtimeType}');
  }

  // ----------------------------
  // Your backend endpoints
  // ----------------------------

  Future<List<dynamic>> fetchReddit({
    required String ticker,
    int days = 14,
    int limit = 50,
  }) {
    return getJsonList('/reddit', query: {
      'ticker': ticker,
      'days': '$days',
      'limit': '$limit',
    });
  }

  Future<Map<String, dynamic>> fetchSentiment({
    required String ticker,
    int days = 14,
    int limit = 50,
  }) {
    return getJsonMap('/sentiment', query: {
      'ticker': ticker,
      'days': '$days',
      'limit': '$limit',
    });
  }

  /// e.g., GET /summary/NVDA
  Future<Map<String, dynamic>> fetchSummaryPath(String symbol) {
    return getJsonMap('/summary/$symbol');
  }

  /// e.g., GET /summary?ticker=NVDA
  Future<Map<String, dynamic>> fetchSummaryQuery({required String ticker}) {
    return getJsonMap('/summary', query: {'ticker': ticker});
  }

  // ----------------------------
  // Internal helpers
  // ----------------------------

  static String _resolveBaseUrl() {
    // Build-time override
    const fromDefine = String.fromEnvironment('API_BASE_URL'); // --dart-define=API_BASE_URL=...
    if (fromDefine.isNotEmpty) return fromDefine;

    if (kIsWeb) {
      // Browser sees the backend from the same machine
      return 'http://localhost:8000';
    }
    // Mobile/desktop:
    if (Platform.isAndroid) {
      // Android emulator special loopback
      return 'http://10.0.2.2:8000';
    }
    // iOS simulator, macOS, Windows, Linux
    return 'http://127.0.0.1:8000';
  }

  Uri _buildUri(String path, Map<String, String>? query) {
    final normalized = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$baseUrl$normalized').replace(queryParameters: query);
  }

  Future<dynamic> _requestJson(
      String method,
      String path, {
        Map<String, String>? query,
        Object? body,
        Map<String, String>? headers,
      }) async {
    final uri = _buildUri(path, query);
    final mergedHeaders = {
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
      ...?headers,
    };

    dynamic lastError;
    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      if (debug && attempt > 0) {
        // ignore: avoid_print
        print('[ApiClient] retry #$attempt $method $uri');
      }
      try {
        final http.Response resp = await _send(method, uri, mergedHeaders, body)
            .timeout(timeout);

        if (resp.statusCode >= 200 && resp.statusCode < 300) {
          return _decodeJson(resp);
        }

        // Non-2xx: try to parse error body for easier debugging
        final errText = _safeBodyPreview(resp);
        throw HttpException(
          'HTTP ${resp.statusCode} ${resp.reasonPhrase} for $method $uri\n$errText',
        );
      } on TimeoutException catch (e) {
        lastError = e;
        if (attempt == maxRetries) rethrow;
        await Future.delayed(Duration(milliseconds: 300 * (1 << attempt)));
      } on http.ClientException catch (e) {
        lastError = e;
        if (attempt == maxRetries) rethrow;
        await Future.delayed(Duration(milliseconds: 300 * (1 << attempt)));
      } on SocketException catch (e) {
        lastError = e;
        if (attempt == maxRetries) rethrow;
        await Future.delayed(Duration(milliseconds: 300 * (1 << attempt)));
      } catch (e) {
        // Other errors are not likely transient—bubble up immediately.
        rethrow;
      }
    }
    // Should be unreachable, but keeps analyzer happy.
    throw HttpException('Request failed after retries: $lastError');
  }

  Future<http.Response> _send(
      String method,
      Uri uri,
      Map<String, String> headers,
      Object? body,
      ) {
    switch (method) {
      case 'GET':
        return _http.get(uri, headers: headers);
      case 'POST':
        return _http.post(uri, headers: headers, body: body == null ? null : jsonEncode(body));
      case 'DELETE':
        return _http.delete(uri, headers: headers);
      case 'PUT':
        return _http.put(uri, headers: headers, body: body == null ? null : jsonEncode(body));
      case 'PATCH':
        return _http.patch(uri, headers: headers, body: body == null ? null : jsonEncode(body));
      default:
        throw ArgumentError('Unsupported method: $method');
    }
  }

  dynamic _decodeJson(http.Response resp) {
    // Handle UTF-8 + BOM safely
    final text = utf8.decode(resp.bodyBytes);
    return jsonDecode(text);
  }

  String _safeBodyPreview(http.Response resp, {int max = 400}) {
    final text = utf8.decode(resp.bodyBytes, allowMalformed: true);
    final trimmed = text.length > max ? '${text.substring(0, max)}…' : text;
    return 'Body: $trimmed';
  }
}

class HttpException implements Exception {
  final String message;
  HttpException(this.message);
  @override
  String toString() => message;
}
