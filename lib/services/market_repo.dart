// lib/services/market_repo.dart
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models.dart' show StockSummary; // for summary()/summaryQuery()
import '../models.dart' as app_models show LiveQuote;
import 'alpha_vantage.dart' as alpha_vantage;

// ---------------- Models ----------------

class RedditPost {
  final String id;
  final String title;
  final String url;
  final String author;
  final String? createdUtc; // seconds/ms/ISO tolerated as string
  final String content;
  final int score;
  final int comments;
  final double upvoteRatio;
  final double sentimentScore;

  RedditPost({
    required this.id,
    required this.title,
    required this.url,
    required this.author,
    this.createdUtc,
    this.content = '',
    this.score = 0,
    this.comments = 0,
    this.upvoteRatio = 0.0,
    this.sentimentScore = 0.0,
  });

  factory RedditPost.fromJson(Map<String, dynamic> j) => RedditPost(
    id: (j['id'] ?? '').toString(),
    title: (j['title'] ?? j['headline'] ?? '').toString(),
    url: (j['url'] ?? j['link'] ?? j['permalink'] ?? '').toString(),
    author: (j['author'] ?? j['by'] ?? j['subreddit_name_prefixed'] ?? '')
        .toString(),
    createdUtc:
        j['created_utc']?.toString() ??
        j['created_at']?.toString() ??
        j['created']?.toString(),
    content: (j['content'] ?? j['selftext'] ?? '').toString(),
    score: (j['score'] as num?)?.toInt() ?? 0,
    comments:
        (j['comments'] as num?)?.toInt() ??
        (j['num_comments'] as num?)?.toInt() ??
        0,
    upvoteRatio: (j['upvote_ratio'] as num?)?.toDouble() ?? 0.0,
    sentimentScore: (j['sentiment_score'] as num?)?.toDouble() ?? 0.0,
  );

  RedditPost copyWith({
    String? id,
    String? title,
    String? url,
    String? author,
    String? createdUtc,
    String? content,
    int? score,
    int? comments,
    double? upvoteRatio,
    double? sentimentScore,
  }) => RedditPost(
    id: id ?? this.id,
    title: title ?? this.title,
    url: url ?? this.url,
    author: author ?? this.author,
    createdUtc: createdUtc ?? this.createdUtc,
    content: content ?? this.content,
    score: score ?? this.score,
    comments: comments ?? this.comments,
    upvoteRatio: upvoteRatio ?? this.upvoteRatio,
    sentimentScore: sentimentScore ?? this.sentimentScore,
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
  MarketRepo([Object? _]);

  static const _redditBase = 'https://www.reddit.com';

  static const _positiveTerms = <String, double>{
    'beat': 0.60,
    'beats': 0.65,
    'bullish': 0.85,
    'buy': 0.60,
    'buys': 0.60,
    'long': 0.25,
    'growth': 0.45,
    'gains': 0.45,
    'gain': 0.40,
    'surge': 0.60,
    'surges': 0.65,
    'jump': 0.45,
    'jumps': 0.50,
    'strong': 0.35,
    'record': 0.40,
    'upside': 0.45,
    'profit': 0.50,
    'profits': 0.50,
    'upgrade': 0.55,
    'upgrades': 0.55,
    'outperform': 0.65,
    'outperforms': 0.65,
    'optimistic': 0.40,
    'momentum': 0.35,
    'rally': 0.50,
    'rallies': 0.50,
    'breakout': 0.65,
    'undervalued': 0.60,
    'rebound': 0.45,
    'recovery': 0.40,
    'moon': 0.70,
    'squeeze': 0.70,
    'rip': 0.30,
    'green': 0.20,
  };

  static const _negativeTerms = <String, double>{
    'miss': -0.60,
    'misses': -0.65,
    'bearish': -0.85,
    'sell': -0.60,
    'sells': -0.60,
    'short': -0.30,
    'drop': -0.50,
    'drops': -0.55,
    'slump': -0.60,
    'slumps': -0.60,
    'fall': -0.45,
    'falls': -0.45,
    'weak': -0.35,
    'downgrade': -0.55,
    'downgrades': -0.55,
    'risk': -0.30,
    'risks': -0.30,
    'warning': -0.45,
    'warns': -0.45,
    'lawsuit': -0.55,
    'lawsuits': -0.55,
    'recall': -0.65,
    'recalls': -0.65,
    'loss': -0.50,
    'losses': -0.50,
    'cut': -0.35,
    'cuts': -0.40,
    'decline': -0.45,
    'declines': -0.45,
    'crash': -0.75,
    'dump': -0.60,
    'dilution': -0.70,
    'offering': -0.35,
    'overvalued': -0.60,
    'red': -0.20,
  };

  static const _positivePhrases = <String, double>{
    'beats expectations': 0.80,
    'beat expectations': 0.80,
    'raises guidance': 0.85,
    'strong earnings': 0.75,
    'buy the dip': 0.50,
    'price target raised': 0.70,
    'record revenue': 0.70,
    'double beat': 0.85,
  };

  static const _negativePhrases = <String, double>{
    'misses expectations': -0.80,
    'missed expectations': -0.80,
    'cuts guidance': -0.85,
    'weak guidance': -0.75,
    'share offering': -0.70,
    'price target cut': -0.70,
    'class action': -0.65,
    'sell the rip': -0.50,
  };

  String _normalizeText(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .join(' ');
  }

  double _postSentimentScore(RedditPost post) {
    final text = _normalizeText('${post.title} ${post.content}');
    if (text.isEmpty) return 0.0;

    var score = 0.0;

    for (final entry in _positivePhrases.entries) {
      if (text.contains(entry.key)) score += entry.value;
    }
    for (final entry in _negativePhrases.entries) {
      if (text.contains(entry.key)) score += entry.value;
    }

    for (final word in text.split(' ')) {
      score += _positiveTerms[word] ?? 0.0;
      score += _negativeTerms[word] ?? 0.0;
    }

    final hypeBoost = ((post.upvoteRatio - 0.5) * 0.35).clamp(-0.15, 0.15);
    score += hypeBoost;

    if (score == 0.0) {
      final hasQuestion = post.title.contains('?');
      score = hasQuestion ? 0.05 : 0.0;
    }

    return (score / 2.5).clamp(-1.0, 1.0);
  }

  double _engagementWeight(RedditPost post) {
    final points = post.score < 0 ? 0 : post.score;
    final comments = post.comments < 0 ? 0 : post.comments;
    final upvote = post.upvoteRatio <= 0 ? 0.5 : post.upvoteRatio;
    return (1 + points / 25.0 + comments / 10.0) * (0.8 + upvote * 0.4);
  }

  DateTime? _parseLooseDate(String? value) {
    if (value == null || value.isEmpty) return null;
    final n = num.tryParse(value);
    if (n != null) {
      final ms = n > 2000000000000 ? n : n * 1000;
      return DateTime.fromMillisecondsSinceEpoch(
        ms.toInt(),
        isUtc: true,
      ).toLocal();
    }
    return DateTime.tryParse(value)?.toLocal();
  }

  String _dayKey(DateTime dt) =>
      DateTime(dt.year, dt.month, dt.day).toIso8601String().split('T').first;

  Uri _redditSearchUri(String symbol, int limit, {String? after}) {
    final upper = symbol.toUpperCase();
    final query =
        "($upper OR \$$upper) AND (stock OR shares OR earnings OR market)";
    final afterPart = (after == null || after.isEmpty) ? '' : '&after=$after';
    return Uri.parse(
      '$_redditBase/search.json'
      '?q=${Uri.encodeQueryComponent(query)}'
      '&sort=new&t=month&limit=$limit&type=link$afterPart',
    );
  }

  Future<Map<String, dynamic>> _fetchRedditPage(
    String symbol,
    int limit, {
    String? after,
  }) async {
    final response = await http.get(
      _redditSearchUri(symbol, limit, after: after),
      headers: const {
        'User-Agent': 'stock-scout-mobile/1.0',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Reddit request failed (${response.statusCode})');
    }

    final root = jsonDecode(response.body);
    final children =
        ((root is Map ? root['data'] : null)?['children'] as List?) ?? const [];
    final nextAfter = ((root is Map ? root['data'] : null)?['after'])
        ?.toString();

    final posts = children
        .map((node) => node is Map ? node['data'] : null)
        .whereType<Map>()
        .map((data) {
          final permalink = (data['permalink'] ?? '').toString();
          final resolvedUrl = permalink.startsWith('http')
              ? permalink
              : '$_redditBase$permalink';
          final post = RedditPost.fromJson({
            'id': data['id'],
            'title': data['title'],
            'url': resolvedUrl,
            'author': data['subreddit_name_prefixed'] ?? data['author'],
            'created_utc': data['created_utc'],
            'content': data['selftext'],
            'score': data['score'],
            'num_comments': data['num_comments'],
            'upvote_ratio': data['upvote_ratio'],
          });
          return post.copyWith(sentimentScore: _postSentimentScore(post));
        })
        .where((post) => post.title.isNotEmpty)
        .toList();

    return {'posts': posts, 'after': nextAfter};
  }

  Future<List<RedditPost>> _fetchRedditPosts(
    String symbol,
    int pageSize, {
    int? days,
  }) async {
    final cutoff = days == null
        ? null
        : DateTime.now().subtract(Duration(days: days));
    final allPosts = <RedditPost>[];
    final seenIds = <String>{};
    String? after;

    for (var page = 0; page < 12; page++) {
      final data = await _fetchRedditPage(symbol, pageSize, after: after);
      final posts = (data['posts'] as List).whereType<RedditPost>().toList();
      after = data['after'] as String?;

      if (posts.isEmpty) break;

      for (final post in posts) {
        if (seenIds.add(post.id)) {
          allPosts.add(post);
        }
      }

      if (cutoff != null) {
        DateTime? oldestOnPage;
        for (final post in posts) {
          final dt = _parseLooseDate(post.createdUtc);
          if (dt == null) continue;
          if (oldestOnPage == null || dt.isBefore(oldestOnPage)) {
            oldestOnPage = dt;
          }
        }
        if (oldestOnPage != null && !oldestOnPage.isAfter(cutoff)) {
          break;
        }
      }

      if (after == null || after.isEmpty) break;
    }

    return allPosts;
  }

  List<DateTime> _windowDates(int days) {
    final now = DateTime.now();
    return List.generate(days, (i) {
      final d = now.subtract(Duration(days: days - 1 - i));
      return DateTime(d.year, d.month, d.day);
    });
  }

  // ---------- Reddit ----------

  /// Returns a list of Reddit posts for [symbol].
  /// Results are deduped by (title, host) keeping the newest.
  Future<List<RedditPost>> reddit(
    String symbol, {
    int days = 14,
    int limit = 50,
  }) async {
    final cutoff = DateTime.now().subtract(Duration(days: days));
    final posts = await _fetchRedditPosts(
      symbol.trim().toUpperCase(),
      100,
      days: days,
    );
    return posts.where((post) {
      final dt = _parseLooseDate(post.createdUtc);
      return dt != null && !dt.isBefore(cutoff);
    }).toList();
  }

  // ---------- Sentiment ----------

  /// Returns a sentiment series and summary label.
  Future<(List<SentimentPoint>, String)> sentiment(
    String symbol, {
    int days = 14,
    int limit = 50,
  }) async {
    final posts = await _fetchRedditPosts(
      symbol.trim().toUpperCase(),
      100,
      days: days,
    );
    final dailyWeighted = <String, ({double num, double den})>{};

    for (final post in posts) {
      final postDate = _parseLooseDate(post.createdUtc);
      if (postDate == null) continue;
      final key = _dayKey(postDate);
      final score = post.sentimentScore;
      final weight = _engagementWeight(post);
      final current = dailyWeighted[key];
      dailyWeighted[key] = (
        num: (current?.num ?? 0.0) + score * weight,
        den: (current?.den ?? 0.0) + weight,
      );
    }

    final windowDays = _windowDates(days);
    final windowStart = windowDays.isEmpty ? null : windowDays.first;

    double seededTrendBeforeWindow() {
      if (windowStart == null) return 0.0;

      final prior =
          dailyWeighted.entries
              .map((entry) {
                final dt = DateTime.tryParse(entry.key);
                if (dt == null || !dt.isBefore(windowStart)) return null;
                final den = entry.value.den == 0 ? 1.0 : entry.value.den;
                return (date: dt, score: entry.value.num / den);
              })
              .whereType<({DateTime date, double score})>()
              .toList()
            ..sort((a, b) => a.date.compareTo(b.date));

      if (prior.isEmpty) return 0.0;
      final tail = prior.skip(prior.length > 3 ? prior.length - 3 : 0).toList();
      return tail.map((p) => p.score).reduce((a, b) => a + b) / tail.length;
    }

    var carriedTrend = seededTrendBeforeWindow();
    final series = windowDays.map((day) {
      final key = _dayKey(day);
      final bucket = dailyWeighted[key];
      if (bucket != null && bucket.den > 0) {
        carriedTrend = bucket.num / bucket.den;
      } else {
        carriedTrend *= 0.97;
        if (carriedTrend.abs() < 0.015) carriedTrend = 0.0;
      }
      return SentimentPoint(date: key, score: carriedTrend);
    }).toList();

    final overall = series.isEmpty
        ? 0.0
        : series.map((p) => p.score.toDouble()).reduce((a, b) => a + b) /
              series.length;

    final summary = overall > 0.10
        ? 'Positive'
        : overall < -0.10
        ? 'Negative'
        : 'Neutral';

    return (series, summary);
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
    final j = await _summaryJson(symbol);
    return StockSummary(
      symbol: (j['symbol'] ?? '').toString(),
      price: (j['price'] ?? 0).toDouble(),
      changePct: (j['changePct'] ?? 0).toDouble(),
      sentiment: (j['sentiment'] ?? 'Neutral').toString(),
    );
  }

  /// Query style: /summary?ticker=SYMBOL
  Future<StockSummary> summaryQuery(String symbol) async {
    final j = await _summaryJson(symbol);
    return StockSummary(
      symbol: (j['symbol'] ?? '').toString(),
      price: (j['price'] ?? 0).toDouble(),
      changePct: (j['changePct'] ?? 0).toDouble(),
      sentiment: (j['sentiment'] ?? 'Neutral').toString(),
    );
  }

  Future<Map<String, dynamic>> _summaryJson(String symbol) async {
    final normalized = symbol.trim().toUpperCase();
    final app_models.LiveQuote live = await alpha_vantage.fetchStockQuote(
      normalized,
    );
    return {
      'symbol': normalized,
      'price': live.price,
      'changePct': live.changePct ?? 0.0,
      'sentiment': 'Neutral',
    };
  }
}
