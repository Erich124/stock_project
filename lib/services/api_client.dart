// lib/services/api_client.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiClient {
  /// Base URL of your backend.
  /// Use the Android emulator host alias by default.
  final String baseUrl;
  const ApiClient({this.baseUrl = 'http://10.0.2.2:8000'});

  /// GET /summary?ticker=...
  Future<Map<String, dynamic>> getSummary(String ticker) async {
    final uri = Uri.parse('$baseUrl/summary')
        .replace(queryParameters: {'ticker': ticker});
    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// GET /symbols/{ticker}/exists
  Future<bool> symbolExists(String ticker) async {
    final uri = Uri.parse('$baseUrl/symbols/$ticker/exists');
    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['exists'] as bool?) ?? false;
  }

  /// GET /reddit?ticker=...&days=14&limit=50
  Future<List<dynamic>> getReddit(String ticker,
      {int days = 14, int limit = 50}) async {
    final uri = Uri.parse('$baseUrl/reddit').replace(queryParameters: {
      'ticker': ticker,
      'days': '$days',
      'limit': '$limit',
    });
    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final parsed = jsonDecode(res.body);
    if (parsed is List) return parsed;
    throw Exception('Unexpected /reddit payload: ${res.body}');
  }

  /// GET /sentiment?ticker=...&days=14&limit=50
  Future<Map<String, dynamic>> getSentiment(String ticker,
      {int days = 14, int limit = 50}) async {
    final uri = Uri.parse('$baseUrl/sentiment').replace(queryParameters: {
      'ticker': ticker,
      'days': '$days',
      'limit': '$limit',
    });
    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }
}
