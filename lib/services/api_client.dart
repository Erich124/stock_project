// lib/services/api_client.dart
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

class ApiClient {
  final String baseUrl;
  final http.Client _http;

  ApiClient({String? baseUrl, http.Client? httpClient})
      : baseUrl = baseUrl ?? _defaultBaseUrl(),
        _http = httpClient ?? http.Client() {
    // Debug: confirm which base URL the app is actually using.
    // ignore: avoid_print
    print('[ApiClient] baseUrl=$baseUrl');
  }

  static String _defaultBaseUrl() {
    if (kIsWeb) return 'http://localhost:8000';
    if (Platform.isAndroid) return 'http://10.0.2.2:8000';
    return 'http://127.0.0.1:8000';
  }

  Future<List<dynamic>> getJsonList(String path, {Map<String, String>? query}) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    final resp = await _http.get(uri);
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      final decoded = jsonDecode(resp.body);
      if (decoded is List) return decoded;
      throw StateError('Expected a JSON list from $path; got ${decoded.runtimeType}');
    }
    throw HttpException('GET $uri failed: ${resp.statusCode} ${resp.reasonPhrase} – ${resp.body}');
  }

  Future<Map<String, dynamic>> getJsonMap(String path, {Map<String, String>? query}) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    final resp = await _http.get(uri);
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      final decoded = jsonDecode(resp.body);
      if (decoded is Map<String, dynamic>) return decoded;
      throw StateError('Expected a JSON object from $path; got ${decoded.runtimeType}');
    }
    throw HttpException('GET $uri failed: ${resp.statusCode} ${resp.reasonPhrase} – ${resp.body}');
  }

  // ---------- Backend endpoints ----------
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

  // --- Summary: support both path and query styles ---
  Future<Map<String, dynamic>> fetchSummaryPath(String symbol) {
    // e.g., GET /summary/NVDA
    return getJsonMap('/summary/$symbol');
  }

  Future<Map<String, dynamic>> fetchSummaryQuery({required String ticker}) {
    // e.g., GET /summary?ticker=NVDA
    return getJsonMap('/summary', query: {'ticker': ticker});
  }
}

class HttpException implements Exception {
  final String message;
  HttpException(this.message);
  @override
  String toString() => message;
}
