// lib/services/trending_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:http/http.dart' as http;

import '../models.dart';
import 'news_service.dart'; // for NewsItem

/// Choose the right base URL per platform:
/// - Android emulator: http://10.0.2.2:8000  (special alias to host machine)
/// - iOS simulator/macOS: http://127.0.0.1:8000
/// - Web (Chrome): http://127.0.0.1:8000  (served by your host browser)
String _defaultBaseUrl() {
  if (kIsWeb) return 'http://127.0.0.1:8000';
  if (defaultTargetPlatform == TargetPlatform.android) return 'http://10.0.2.2:8000';
  return 'http://127.0.0.1:8000';
}

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
    final String resolvedBase = baseUrl ?? _defaultBaseUrl();
    final uri = Uri.parse('$resolvedBase/trending');

    final payload = {
      "days": days,
      "limit": limit,
      "include_reddit": includeReddit,
      "reddit_tickers": redditTickers,
      "headlines": headlines
          .map((n) => {
        "title": n.title,
        "publishedAt": n.pubDate?.toUtc().toIso8601String(),
      })
          .toList(),
    };

    final res = await http.post(
      uri,
      headers: const {"Content-Type": "application/json"},
      body: jsonEncode(payload),
    );

    if (res.statusCode != 200) {
      throw Exception('Trending failed: ${res.statusCode} ${res.body}');
    }

    final Map<String, dynamic> j = jsonDecode(res.body) as Map<String, dynamic>;
    final List top = (j["top"] as List? ?? []);
    final Map<String, dynamic> seriesMap =
    Map<String, dynamic>.from(j["series"] as Map? ?? {});

    return top.map<TrendingKeyword>((e) {
      final k = e["keyword"] ?? '';
      return TrendingKeyword(
        keyword: k,
        score: (e["score"] as num).toDouble(),
        series: (seriesMap[k] as List?)
            ?.map((x) => (x as num).toInt())
            .toList(),
      );
    }).toList();
  }
}
