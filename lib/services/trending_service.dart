// lib/services/trending_service.dart
import '../models.dart';
import 'news_service.dart'; // for NewsItem

class TrendingService {
  /// If [baseUrl] is null, we auto-pick the right one per platform.
  static Future<List<TrendingKeyword>> fetchTrendingKeywords(
    List<NewsItem> headlines, {
    String? baseUrl,
    int days = 14,
    int limit = 20,
    bool includeReddit = false,
    List<String> redditTickers = const [],
  }) async {
    final counts = <String, int>{};
    const stopWords = {
      'the',
      'and',
      'for',
      'with',
      'from',
      'that',
      'this',
      'into',
      'over',
      'under',
      'after',
      'before',
      'about',
      'stock',
      'stocks',
      'market',
      'markets',
      'finance',
      'yahoo',
      'watch',
      'says',
      'amid',
      'news',
      'more',
      'than',
      'will',
      'your',
      'their',
      'they',
      'them',
      'have',
      'has',
      'had',
      'are',
      'was',
      'were',
      'its',
      'all',
    };

    for (final headline in headlines) {
      final words = headline.title
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
          .split(RegExp(r'\s+'))
          .where((w) => w.length >= 3 && !stopWords.contains(w));

      final seen = <String>{};
      for (final word in words) {
        if (seen.add(word)) {
          counts[word] = (counts[word] ?? 0) + 1;
        }
      }
    }

    final sorted = counts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        if (byCount != 0) return byCount;
        return a.key.compareTo(b.key);
      });

    return sorted
        .take(limit)
        .map(
          (entry) => TrendingKeyword(
            keyword: entry.key,
            score: entry.value.toDouble(),
          ),
        )
        .toList();
  }
}
