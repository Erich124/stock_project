// lib/services/market_repo.dart
import 'api_client.dart';
import '../models.dart' show StockSummary; // for summary()/summaryQuery()

// ---------------- Models ----------------

class RedditPost {
  final String id;
  final String title;
  final String url;
  final String author;
  final String? createdUtc; // seconds/ms/ISO tolerated as string

  RedditPost({
    required this.id,
    required this.title,
    required this.url,
    required this.author,
    this.createdUtc,
  });

  factory RedditPost.fromJson(Map<String, dynamic> j) => RedditPost(
    id: (j['id'] ?? '').toString(),
    title: (j['title'] ?? j['headline'] ?? '').toString(),
    url: (j['url'] ?? j['link'] ?? '').toString(),
    author: (j['author'] ?? j['by'] ?? '').toString(),
    createdUtc: j['created_utc']?.toString() ?? j['created']?.toString(),
  );
}

class SentimentPoint {
  /// Keep as string; UI parses flexibly (YYYY-MM-DD, ISO, millis, seconds).
  final String date;
  /// Aggregated daily score (positive up, negative down).
  final num score;

  SentimentPoint({required this.date, required this.score});

  factory SentimentPoint.fromJson(Map<String, dynamic> j) => SentimentPoint(
    date: (j['date'] ?? j['day'] ?? j['timestamp'] ?? '').toString(),
    score: (j['score'] ?? j['value'] ?? 0) is num
        ? (j['score'] ?? j['value'] ?? 0) as num
        : num.tryParse((j['score'] ?? j['value'] ?? '0').toString()) ?? 0,
  );
}

// ---------------- Repo ----------------

class MarketRepo {
  final ApiClient _api;
  MarketRepo(this._api);

  // ---------- Utilities ----------

  int _tsMillis(String? createdUtc) {
    if (createdUtc == null || createdUtc.isEmpty) return 0;
    final n = int.tryParse(createdUtc);
    if (n != null) {
      // Heuristic: 13 digits => ms, 10 digits => sec
      return n > 2e12 ? n : n * 1000;
    }
    return DateTime.tryParse(createdUtc)?.millisecondsSinceEpoch ?? 0;
  }

  List<RedditPost> _dedupePosts(List<RedditPost> posts) {
    // key = normalized "title|host"
    final map = <String, RedditPost>{};
    for (final p in posts) {
      final host = Uri.tryParse(p.url)?.host?.toLowerCase() ?? '';
      final key = '${p.title.trim().toLowerCase()}|$host';
      final existing = map[key];
      if (existing == null || _tsMillis(p.createdUtc) > _tsMillis(existing.createdUtc)) {
        map[key] = p; // keep most recent
      }
    }
    final unique = map.values.toList()
      ..sort((a, b) => _tsMillis(b.createdUtc).compareTo(_tsMillis(a.createdUtc)));
    return unique;
  }

  (double avg, String label) _labelFromSeries(List<SentimentPoint> series, String backendSummary) {
    double avg = 0.0;
    if (series.isNotEmpty) {
      double sum = 0.0;
      for (final p in series) {
        sum += p.score.toDouble();
      }
      avg = sum / series.length;
    }
    if (backendSummary.trim().isNotEmpty) {
      return (avg, backendSummary.trim());
    }
    final label = avg > 0.05
        ? 'Overall positive'
        : (avg < -0.05 ? 'Overall negative' : 'Neutral');
    return (avg, label);
  }

  // ---------- Reddit ----------

  /// Returns a list of Reddit posts for [symbol].
  /// Results are deduped by (title, host) keeping the newest.
  Future<List<RedditPost>> reddit(
      String symbol, {
        int days = 14,
        int limit = 50,
      }) async {
    final raw = await _api.fetchReddit(ticker: symbol, days: days, limit: limit);
    final posts = raw
        .whereType<Map>() // tolerate mixed lists
        .map((e) => RedditPost.fromJson(e.cast<String, dynamic>()))
        .where((p) => p.title.isNotEmpty && p.url.isNotEmpty)
        .toList();
    return _dedupePosts(posts);
  }

  // ---------- Sentiment ----------

  /// Returns (series, summary) where:
  /// - series: List<SentimentPoint>
  /// - summary: String (falls back to synthesized label if backend empty)
  Future<(List<SentimentPoint>, String)> sentiment(
      String symbol, {
        int days = 14,
        int limit = 50,
      }) async {
    final raw = await _api.fetchSentiment(ticker: symbol, days: days, limit: limit);

    final seriesJson = (raw['series'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();

    final summaryText = (raw['summary'] ?? '').toString();

    final series = seriesJson.map(SentimentPoint.fromJson).toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    final (avg, label) = _labelFromSeries(series, summaryText);
    // You can log or store avg if you want more analytics.
    return (series, label);
  }

  // ---------- Back-compat wrappers ----------

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

  // ---------- Summary endpoints ----------

  /// PATH style: /summary/{symbol}
  Future<StockSummary> summary(String symbol) async {
    final j = await _api.fetchSummaryPath(symbol.trim().toUpperCase());
    return StockSummary(
      symbol: (j['symbol'] ?? '').toString(),
      price: (j['price'] ?? 0).toDouble(),
      changePct: (j['changePct'] ?? 0).toDouble(),
      sentiment: (j['sentiment'] ?? 'Neutral').toString(),
    );
  }

  /// Query style: /summary?ticker=SYMBOL
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
