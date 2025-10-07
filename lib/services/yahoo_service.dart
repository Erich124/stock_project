import 'dart:convert';
import 'package:http/http.dart' as http;

class YahooSummary {
  final String symbol;
  final double price;
  final double changePct;
  final String? sector;
  final double? pe;
  final double? beta;
  final String sentiment;

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
    symbol: j['symbol'],
    price: (j['price'] ?? 0).toDouble(),
    changePct: (j['changePct'] ?? 0).toDouble(),
    sector: j['sector'],
    pe: j['pe'] == null ? null : (j['pe'] as num).toDouble(),
    beta: j['beta'] == null ? null : (j['beta'] as num).toDouble(),
    sentiment: (j['sentiment'] ?? 'Neutral').toString(),
  );
}

class YahooService {
  // IMPORTANT:
  // Android emulator cannot reach 'localhost' on your machine.
  // Use 10.0.2.2 for Android emulator, localhost for iOS simulator/web,
  // or your computer's LAN IP for a physical phone.
  static const _base = 'http://10.0.2.2:8000';

  static Future<bool> symbolExists(String symbol) async {
    final r = await http.get(Uri.parse("$_base/symbols/$symbol/exists"));
    if (r.statusCode != 200) return false;
    final j = json.decode(r.body) as Map<String, dynamic>;
    return j['exists'] == true;
  }

  static Future<YahooSummary> getSummary(String symbol) async {
    final r = await http.get(Uri.parse("$_base/symbols/$symbol/summary"));
    if (r.statusCode != 200) {
      throw Exception('Summary error ${r.statusCode}: ${r.body}');
    }
    final j = json.decode(r.body) as Map<String, dynamic>;
    return YahooSummary.fromJson(j);
  }

  // Optional: history if/when you add a chart
  static Future<List<Map<String, dynamic>>> getHistory(
      String symbol, {String period = '6mo', String interval = '1d'}) async {
    final r = await http.get(
      Uri.parse("$_base/symbols/$symbol/history?period=$period&interval=$interval"),
    );
    if (r.statusCode != 200) {
      throw Exception('History error ${r.statusCode}: ${r.body}');
    }
    final j = json.decode(r.body) as Map<String, dynamic>;
    return (j['bars'] as List).cast<Map<String, dynamic>>();
  }
}
