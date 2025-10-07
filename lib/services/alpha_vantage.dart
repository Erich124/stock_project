// lib/services/alpha_vantage.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models.dart';

const String alphaVantageKey = 'LDITVKSK8ZWVIZH6';

Future<bool> symbolExists(String symbolUpper) async {
  final url = Uri.parse(
    'https://www.alphavantage.co/query?function=SYMBOL_SEARCH&keywords=$symbolUpper&apikey=$alphaVantageKey',
  );
  final res = await http.get(url);
  if (res.statusCode != 200) return false;

  final data = json.decode(res.body) as Map<String, dynamic>;
  final matches = (data['bestMatches'] as List?) ?? const [];
  for (final m in matches) {
    final sym = (m['1. symbol'] as String?)?.toUpperCase().trim();
    if (sym == symbolUpper) return true;
  }
  return false;
}

Future<LiveQuote> fetchStockQuote(String symbol) async {
  final url = Uri.parse(
    'https://www.alphavantage.co/query?function=GLOBAL_QUOTE&symbol=$symbol&apikey=$alphaVantageKey',
  );
  final response = await http.get(url);
  if (response.statusCode != 200) {
    throw Exception('HTTP ${response.statusCode}');
  }

  final data = json.decode(response.body) as Map<String, dynamic>;
  final quote = data['Global Quote'] as Map<String, dynamic>?;

  if (quote == null || quote.isEmpty) {
    throw Exception('No quote available (API limit or bad symbol)');
  }

  double parseNum(String? s) {
    if (s == null) return double.nan;
    return double.tryParse(s.replaceAll('%', '').trim()) ?? double.nan;
  }

  final price = parseNum(quote['05. price']);
  final changePct = parseNum(quote['10. change percent']);
  if (price.isNaN) throw Exception('Malformed price data');

  return LiveQuote(price: price, changePct: changePct.isNaN ? null : changePct);
}

/// Optional: used by Markets page
Future<TopMovers> fetchTopMoversRaw() async {
  final url = Uri.parse(
    'https://www.alphavantage.co/query?function=TOP_GAINERS_LOSERS&apikey=$alphaVantageKey',
  );
  final res = await http.get(url);
  if (res.statusCode != 200) {
    throw Exception('HTTP ${res.statusCode}');
  }
  final data = json.decode(res.body) as Map<String, dynamic>;

  List<Mover> parseList(dynamic raw) {
    final list = (raw as List?) ?? const [];
    return list.map<Mover>((e) {
      String s(Object? v) => (v ?? '').toString();
      double p(Object? v) => double.tryParse(s(v).replaceAll('%', '').trim()) ?? double.nan;

      final symbol = s(e['ticker']).toUpperCase().trim();
      final price  = p(e['price']);
      final pct    = p(e['change_percentage']);
      return Mover(symbol: symbol, price: price, changePct: pct);
    }).where((m) => m.symbol.isNotEmpty && !m.price.isNaN && !m.changePct.isNaN).toList();
  }

  return TopMovers(
    gainers: parseList(data['top_gainers']),
    losers:  parseList(data['top_losers']),
  );
}
