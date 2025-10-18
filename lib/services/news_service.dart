// lib/services/news_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart' as xml;

/// Minimal News model.
/// If you already keep models in models.dart, you can move this there unchanged.
class NewsItem {
  final String title;
  final String link;
  final String source;
  final DateTime? pubDate;

  NewsItem({
    required this.title,
    required this.link,
    required this.source,
    this.pubDate,
  });
}

/// Parse a Yahoo Finance RSS feed into [NewsItem]s.
List<NewsItem> _parseYahooRss(String body) {
  final doc = xml.XmlDocument.parse(body);
  return doc.findAllElements('item').map((item) {
    final title = item.getElement('title')?.text.trim() ?? '(no title)';
    final link  = item.getElement('link')?.text.trim()  ?? '';
    final src   = item.getElement('source')?.text.trim() ??
        item.getElement('creator')?.text.trim() ?? 'Yahoo Finance';
    final pdStr = item.getElement('pubDate')?.text.trim();
    DateTime? pd;
    if (pdStr != null) {
      try { pd = DateTime.parse(pdStr); } catch (_) {}
    }
    return NewsItem(title: title, link: link, source: src, pubDate: pd);
  }).toList();
}

class NewsService {
  /// Market-wide news (S&P 500 headline feed is a decent proxy).
  static Future<List<NewsItem>> fetchMarketNews({int limit = 30}) async {
    // Yahoo RSS for market headlines. You can swap this later for your backend.
    final uri = Uri.parse(
      'https://feeds.finance.yahoo.com/rss/2.0/headline?s=%5EGSPC&region=US&lang=en-US',
    );
    final resp = await http.get(uri);
    if (resp.statusCode != 200) {
      throw Exception('Market news HTTP ${resp.statusCode}');
    }
    final items = _parseYahooRss(resp.body);
    items.sort((a, b) => (b.pubDate ?? DateTime(0)).compareTo(a.pubDate ?? DateTime(0)));
    return items.take(limit).toList();
  }

  /// Company-specific news using Yahoo Finance RSS by ticker.
  static Future<List<NewsItem>> fetchCompanyNews(String symbol, {int limit = 30}) async {
    final s = symbol.toUpperCase();
    final uri = Uri.parse(
      'https://feeds.finance.yahoo.com/rss/2.0/headline?s=$s&region=US&lang=en-US',
    );
    final resp = await http.get(uri);
    if (resp.statusCode != 200) {
      throw Exception('Company news HTTP ${resp.statusCode}');
    }
    final items = _parseYahooRss(resp.body);
    items.sort((a, b) => (b.pubDate ?? DateTime(0)).compareTo(a.pubDate ?? DateTime(0)));
    return items.take(limit).toList();
  }
}
