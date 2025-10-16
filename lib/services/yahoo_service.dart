// lib/services/yahoo_service.dart
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

class YahooSummary {
  final String symbol;
  final double price;
  final double changePct;     // backend may omit -> defaults to 0
  final String? sector;
  final double? pe;
  final double? beta;
  final String sentiment;     // backend may omit -> defaults to 'Neutral'

  YahooSummary({
    required this.symbol,
    required this.price,
    required this.changePct,
    this.sector,
    this.pe,
    this.beta,
    this.sentiment = 'Neutral',
  });

  factory YahooSummary.fromJson(Map<String, dynamic> j) => YahooSummary(
    symbol: (j['symbol'] ?? '').toString(),
    price: (j['price'] ?? 0).toDouble(),
    changePct: (j['changePct'] ?? 0).toDouble(),
    sector: j['sector'],
    pe: j['pe'] == null ? null : (j['pe'] as num).toDouble(),
    beta: j['beta'] == null ? null : (j['beta'] as num).toDouble(),
    sentiment: (j['sentiment'] ?? 'Neutral').toString(),
  );
}

class YahooService {
  // Pick the correct base for each platform.
  // - Android emulator must use 10.0.2.2 to reach your computer.
  // - iOS simulator / desktop / web can use localhost.
  static String get _base {
    if (kIsWeb) return 'http://localhost:8000';
    if (Platform.isAndroid) return 'http://10.0.2.2:8000';
    return 'http://localhost:8000';
  }

  /// Checks if a symbol exists.
  /// Accepts either a bare boolean body (true/false) OR {"exists": true}.
  static Future<bool> symbolExists(String symbol) async {
    final uri = Uri.parse("$_base/symbols/$symbol/exists");
    final r = await http.get(uri);
    if (r.statusCode != 200) {
      throw Exception('Exists error ${r.statusCode}: ${r.body}');
    }

    final body = r.body.trim();
    // Plain boolean?
    if (body == 'true') return true;
    if (body == 'false') return false;

    // Or JSON {"exists": true}
    final j = json.decode(body);
    if (j is Map && j['exists'] is bool) return j['exists'] as bool;

    // Fallback
    return false;
  }

  /// Gets a summary for a symbol.
  /// Backend endpoint is /symbols/{symbol} (as in the FastAPI example).
  /// If your backend uses /symbols/{symbol}/summary, change the path below.
  static Future<YahooSummary> getSummary(String symbol) async {
    final uri = Uri.parse("$_base/symbols/$symbol"); // <-- matches server.py
    final r = await http.get(uri);
    if (r.statusCode != 200) {
      throw Exception('Summary error ${r.statusCode}: ${r.body}');
    }
    final j = json.decode(r.body) as Map<String, dynamic>;
    return YahooSummary.fromJson(j);
  }

  /// Optional: history endpoint if you add it to your backend
  static Future<List<Map<String, dynamic>>> getHistory(
      String symbol, {
        String period = '6mo',
        String interval = '1d',
      }) async {
    final uri = Uri.parse(
      "$_base/symbols/$symbol/history?period=$period&interval=$interval",
    );
    final r = await http.get(uri);
    if (r.statusCode != 200) {
      throw Exception('History error ${r.statusCode}: ${r.body}');
    }
    final j = json.decode(r.body) as Map<String, dynamic>;
    final list = (j['bars'] as List?) ?? const [];
    return list.cast<Map<String, dynamic>>();
  }
}
