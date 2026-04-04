// lib/services/alpha_vantage.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models.dart';

const String alphaVantageKey = 'LDITVKSK8ZWVIZH6';

class PricePoint {
  final DateTime time;
  final double close;

  PricePoint({required this.time, required this.close});
}

Future<bool> symbolExists(String symbolUpper) async {
  final normalized = symbolUpper.trim().toUpperCase();

  try {
    final url = Uri.parse(
      'https://www.alphavantage.co/query?function=SYMBOL_SEARCH&keywords=$normalized&apikey=$alphaVantageKey',
    );
    final res = await http.get(url);
    if (res.statusCode == 200) {
      final data = json.decode(res.body) as Map<String, dynamic>;
      final matches = (data['bestMatches'] as List?) ?? const [];
      for (final m in matches) {
        final sym = (m['1. symbol'] as String?)?.toUpperCase().trim();
        if (sym == normalized) return true;
      }
    }
  } catch (_) {
    // Fall through to Yahoo validation.
  }

  return _yahooSymbolExists(normalized);
}

Future<LiveQuote> fetchStockQuote(String symbol) async {
  final normalized = symbol.trim().toUpperCase();

  try {
    final url = Uri.parse(
      'https://www.alphavantage.co/query?function=GLOBAL_QUOTE&symbol=$normalized&apikey=$alphaVantageKey',
    );
    final response = await http.get(url);
    if (response.statusCode == 200) {
      final data = json.decode(response.body) as Map<String, dynamic>;
      final quote = data['Global Quote'] as Map<String, dynamic>?;

      if (quote != null && quote.isNotEmpty) {
        final price = _parseNum(quote['05. price']?.toString());
        final changePct = _parseNum(quote['10. change percent']?.toString());
        if (!price.isNaN) {
          return LiveQuote(
            price: price,
            changePct: changePct.isNaN ? null : changePct,
          );
        }
      }
    }
  } catch (_) {
    // Fall through to Yahoo quote.
  }

  return _fetchYahooQuote(normalized);
}

double _parseNum(String? s) {
  if (s == null) return double.nan;
  return double.tryParse(s.replaceAll('%', '').trim()) ?? double.nan;
}

Future<bool> _yahooSymbolExists(String symbol) async {
  final uri = Uri.parse(
    'https://query1.finance.yahoo.com/v8/finance/chart/$symbol?interval=1d&range=1d',
  );
  final response = await http.get(uri);
  if (response.statusCode != 200) return false;

  final data = json.decode(response.body) as Map<String, dynamic>;
  final chart = data['chart'] as Map<String, dynamic>?;
  if (chart == null) return false;
  if (chart['error'] != null) return false;

  final results = chart['result'] as List?;
  return results != null && results.isNotEmpty;
}

Future<LiveQuote> _fetchYahooQuote(String symbol) async {
  final uri = Uri.parse(
    'https://query1.finance.yahoo.com/v8/finance/chart/$symbol?interval=1d&range=5d',
  );
  final response = await http.get(uri);
  if (response.statusCode != 200) {
    throw Exception('Quote HTTP ${response.statusCode}');
  }

  final data = json.decode(response.body) as Map<String, dynamic>;
  final chart = data['chart'] as Map<String, dynamic>?;
  if (chart == null || chart['error'] != null) {
    throw Exception('No quote available for $symbol');
  }

  final results = chart['result'] as List?;
  if (results == null || results.isEmpty) {
    throw Exception('No quote available for $symbol');
  }

  final result = results.first as Map<String, dynamic>;
  final meta = result['meta'] as Map<String, dynamic>? ?? const {};

  final price = (meta['regularMarketPrice'] as num?)?.toDouble();
  final previousClose = (meta['previousClose'] as num?)?.toDouble();
  if (price == null) {
    throw Exception('No quote available for $symbol');
  }

  double? changePct;
  if (previousClose != null && previousClose != 0) {
    changePct = ((price - previousClose) / previousClose) * 100;
  }

  return LiveQuote(price: price, changePct: changePct);
}

Future<List<PricePoint>> fetchPriceHistory(
  String symbol, {
  String range = '1mo',
  String interval = '1d',
}) async {
  final uri = Uri.parse(
    'https://query1.finance.yahoo.com/v8/finance/chart/$symbol?interval=$interval&range=$range',
  );
  final response = await http.get(uri);
  if (response.statusCode != 200) {
    throw Exception('History HTTP ${response.statusCode}');
  }

  final data = json.decode(response.body) as Map<String, dynamic>;
  final chart = data['chart'] as Map<String, dynamic>?;
  if (chart == null || chart['error'] != null) {
    throw Exception('No history available for $symbol');
  }

  final results = chart['result'] as List?;
  if (results == null || results.isEmpty) {
    throw Exception('No history available for $symbol');
  }

  final result = results.first as Map<String, dynamic>;
  final timestamps = (result['timestamp'] as List?) ?? const [];
  final indicators = result['indicators'] as Map<String, dynamic>? ?? const {};
  final quotes = (indicators['quote'] as List?) ?? const [];
  final quote = quotes.isEmpty
      ? const <String, dynamic>{}
      : quotes.first as Map<String, dynamic>;
  final closes = (quote['close'] as List?) ?? const [];

  final points = <PricePoint>[];
  final count = timestamps.length < closes.length
      ? timestamps.length
      : closes.length;
  for (var i = 0; i < count; i++) {
    final ts = timestamps[i];
    final close = closes[i];
    if (ts is num && close is num) {
      points.add(
        PricePoint(
          time: DateTime.fromMillisecondsSinceEpoch(
            ts.toInt() * 1000,
            isUtc: true,
          ).toLocal(),
          close: close.toDouble(),
        ),
      );
    }
  }

  if (points.isEmpty) {
    throw Exception('No history available for $symbol');
  }
  return points;
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
    return list
        .map<Mover>((e) {
          String s(Object? v) => (v ?? '').toString();
          double p(Object? v) =>
              double.tryParse(s(v).replaceAll('%', '').trim()) ?? double.nan;

          final symbol = s(e['ticker']).toUpperCase().trim();
          final price = p(e['price']);
          final pct = p(e['change_percentage']);
          return Mover(symbol: symbol, price: price, changePct: pct);
        })
        .where(
          (m) => m.symbol.isNotEmpty && !m.price.isNaN && !m.changePct.isNaN,
        )
        .toList();
  }

  return TopMovers(
    gainers: parseList(data['top_gainers']),
    losers: parseList(data['top_losers']),
  );
}
