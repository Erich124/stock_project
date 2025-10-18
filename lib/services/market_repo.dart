// lib/services/market_repo.dart
import 'api_client.dart';
import '../models.dart' show StockSummary; // <- for the summary() return type

class RedditPost {
  final String id;
  final String title;
  final String url;
  final String author;
  final String? createdUtc; // optional

  RedditPost({
    required this.id,
    required this.title,
    required this.url,
    required this.author,
    this.createdUtc,
  });

  factory RedditPost.fromJson(Map<String, dynamic> j) => RedditPost(
    id: j['id']?.toString() ?? '',
    title: j['title']?.toString() ?? '',
    url: j['url']?.toString() ?? '',
    author: j['author']?.toString() ?? '',
    createdUtc: j['created_utc']?.toString(),
  );
}

class SentimentPoint {
  final String date; // e.g., "2025-10-15"
  final num score;   // aggregated daily score

  SentimentPoint({required this.date, required this.score});

  factory SentimentPoint.fromJson(Map<String, dynamic> j) => SentimentPoint(
    date: j['date']?.toString() ?? '',
    score: (j['score'] ?? 0) as num,
  );
}

class MarketRepo {
  final ApiClient _api;
  MarketRepo(this._api);

  /// Returns a list of Reddit posts for [symbol].
  Future<List<RedditPost>> reddit(
      String symbol, {
        int days = 14,
        int limit = 50,
      }) async {
    final raw = await _api.fetchReddit(ticker: symbol, days: days, limit: limit);
    return raw
        .map((e) => RedditPost.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  /// Returns (series, summary) where:
  /// - series: List<SentimentPoint>
  /// - summary: String
  Future<(List<SentimentPoint>, String)> sentiment(
      String symbol, {
        int days = 14,
        int limit = 50,
      }) async {
    final raw = await _api.fetchSentiment(ticker: symbol, days: days, limit: limit);
    final seriesJson = (raw['series'] as List? ?? const []);
    final summary = (raw['summary'] ?? '').toString();

    final series = seriesJson
        .map((e) => SentimentPoint.fromJson((e as Map).cast<String, dynamic>()))
        .toList();

    return (series, summary);
  }

  // ---------- Back-compat wrappers (so old call sites still work) ----------
  Future<(List<SentimentPoint>, String)> fetchSentiment(
      String symbol, {
        int days = 14,
        int limit = 50,
      }) {
    return sentiment(symbol, days: days, limit: limit);
  }

  Future<List<RedditPost>> fetchReddit(
      String symbol, {
        int days = 14,
        int limit = 50,
      }) {
    return reddit(symbol, days: days, limit: limit);
  }

  // ---------- NEW: Stock summary via PATH style (/summary/{symbol}) ----------
  Future<StockSummary> summary(String symbol) async {
    final j = await _api.fetchSummaryPath(symbol.trim().toUpperCase());
    return StockSummary(
      symbol: (j['symbol'] ?? '').toString(),
      price: (j['price'] ?? 0).toDouble(),
      changePct: (j['changePct'] ?? 0).toDouble(),
      sentiment: (j['sentiment'] ?? 'Neutral').toString(),
    );
  }

  // (Optional) Query style if needed later: /summary?ticker=SYMBOL
  Future<StockSummary> summaryQuery(String symbol) async {
    final j = await _api.fetchSummaryQuery(ticker: symbol.trim().toUpperCase());
    return StockSummary(
      symbol: (j['symbol'] ?? '').toString(),
      price: (j['price'] ?? 0).toDouble(),
      changePct: (j['changePct'] ?? 0).toDouble(),
      sentiment: (j['sentiment'] ?? 'Neutral').toString(),
    );
  }
}
