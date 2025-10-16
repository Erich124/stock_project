// lib/models.dart

/// ====== Pricing / Summary ======
class LiveQuote {
  final double price;
  final double? changePct;
  LiveQuote({required this.price, this.changePct});

  factory LiveQuote.fromJson(Map<String, dynamic> j) => LiveQuote(
    price: (j['price'] as num).toDouble(),
    changePct: j['changePct'] == null ? null : (j['changePct'] as num).toDouble(),
  );

  Map<String, dynamic> toJson() => {
    'price': price,
    if (changePct != null) 'changePct': changePct,
  };
}

class StockSummary {
  final String symbol;
  final double price;
  final double changePct;
  final String sentiment; // "Positive" | "Neutral" | "Negative"

  StockSummary({
    required this.symbol,
    required this.price,
    required this.changePct,
    required this.sentiment,
  });

  factory StockSummary.fromJson(Map<String, dynamic> j) => StockSummary(
    symbol: j['symbol'],
    price: (j['price'] as num).toDouble(),
    changePct: (j['changePct'] as num).toDouble(),
    sentiment: j['sentiment'] ?? 'Neutral',
  );

  Map<String, dynamic> toJson() => {
    'symbol': symbol,
    'price': price,
    'changePct': changePct,
    'sentiment': sentiment,
  };
}

/// ====== Markets / Movers ======
class Mover {
  final String symbol;
  final double price;
  final double changePct;

  Mover({required this.symbol, required this.price, required this.changePct});

  factory Mover.fromJson(Map<String, dynamic> j) => Mover(
    symbol: j['symbol'],
    price: (j['price'] as num).toDouble(),
    changePct: (j['changePct'] as num).toDouble(),
  );

  Map<String, dynamic> toJson() => {
    'symbol': symbol,
    'price': price,
    'changePct': changePct,
  };
}

class TopMovers {
  final List<Mover> gainers;
  final List<Mover> losers;

  TopMovers({required this.gainers, required this.losers});

  factory TopMovers.fromJson(Map<String, dynamic> j) => TopMovers(
    gainers: (j['gainers'] as List? ?? [])
        .map((e) => Mover.fromJson(e as Map<String, dynamic>))
        .toList(),
    losers: (j['losers'] as List? ?? [])
        .map((e) => Mover.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  Map<String, dynamic> toJson() => {
    'gainers': gainers.map((e) => e.toJson()).toList(),
    'losers': losers.map((e) => e.toJson()).toList(),
  };
}

/// ====== Social Trends (Reddit + Sentiment) ======

class RedditPost {
  final String title;
  final String url;
  final String content; // selftext
  final int score;
  final int comments;
  final double upvoteRatio;
  final DateTime createdAt;

  RedditPost({
    required this.title,
    required this.url,
    required this.content,
    required this.score,
    required this.comments,
    required this.upvoteRatio,
    required this.createdAt,
  });

  factory RedditPost.fromJson(Map<String, dynamic> j) => RedditPost(
    title: j['title'] ?? '',
    url: j['url'] ?? '',
    content: j['content'] ?? '',
    score: (j['score'] ?? 0) as int,
    comments: (j['comments'] ?? 0) as int,
    upvoteRatio: (j['upvote_ratio'] == null)
        ? 0.0
        : (j['upvote_ratio'] as num).toDouble(),
    createdAt: DateTime.parse(j['created_at']),
  );

  Map<String, dynamic> toJson() => {
    'title': title,
    'url': url,
    'content': content,
    'score': score,
    'comments': comments,
    'upvote_ratio': upvoteRatio,
    'created_at': createdAt.toIso8601String(),
  };
}

class SentimentPoint {
  /// ISO date "YYYY-MM-DD"
  final String date;
  /// Weighted daily sentiment in [-1, 1]
  final double value;

  SentimentPoint({required this.date, required this.value});

  factory SentimentPoint.fromJson(Map<String, dynamic> j) => SentimentPoint(
    date: j['date'],
    value: (j['value'] as num).toDouble(),
  );

  Map<String, dynamic> toJson() => {
    'date': date,
    'value': value,
  };
}

class SentimentSummary {
  /// Average of the series ([-1,1])
  final double avg;
  /// "Positive" | "Neutral" | "Negative"
  final String label;

  SentimentSummary({required this.avg, required this.label});

  factory SentimentSummary.fromJson(Map<String, dynamic> j) => SentimentSummary(
    avg: (j['avg'] as num).toDouble(),
    label: j['label'] ?? 'Neutral',
  );

  Map<String, dynamic> toJson() => {
    'avg': avg,
    'label': label,
  };
}
