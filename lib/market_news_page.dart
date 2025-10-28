// lib/market_news_page.dart
import 'package:flutter/material.dart';
import 'services/history_service.dart';
import 'news/article_detail_page.dart';
import 'services/news_service.dart';            // For NewsItem
import 'services/trending_service.dart';
import 'widgets/trending_chips.dart';
import 'models.dart';                           // For TrendingKeyword only

class MarketNewsPage extends StatefulWidget {
  const MarketNewsPage({super.key});

  @override
  State<MarketNewsPage> createState() => _MarketNewsPageState();
}

class _MarketNewsPageState extends State<MarketNewsPage> {
  bool _loading = true;
  String? _error;
  List<NewsItem> _items = const [];
  final _search = TextEditingController();

  // Trending state
  bool _loadingTrending = false;
  String? _trendingError;
  List<TrendingKeyword> _trending = const [];
  String? _selectedKeyword; // null = All

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final items = await NewsService.fetchMarketNews(limit: 50);
      setState(() {
        _items = items;
        _loading = false;
      });
      _loadTrending(items); // kick off trending after headlines load
    } catch (e) {
      setState(() { _error = '$e'; _loading = false; });
    }
  }

  Future<void> _loadTrending(List<NewsItem> headlines) async {
    setState(() { _loadingTrending = true; _trendingError = null; });
    try {
      final list = await TrendingService.fetchTrendingKeywords(
        headlines,
        days: 14,
        limit: 20,
        includeReddit: false, // turn true if you want Reddit titles included
      );
      setState(() { _trending = list; });
    } catch (e) {
      setState(() { _trendingError = '$e'; });
    } finally {
      setState(() { _loadingTrending = false; });
    }
  }

  Future<void> _openDetail(NewsItem item) async {
    // Log as a recently viewed article (use link/url if available)
    final id = item.link?.toString() ?? item.title;
    await HistoryService.instance.logView(
      type: 'article',
      id: id,
      title: item.title,
    );

    // Navigate to article detail
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ArticleDetailPage(article: item)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();

    // Search filter
    var list = q.isEmpty
        ? _items
        : _items.where((n) =>
    n.title.toLowerCase().contains(q) ||
        n.source.toLowerCase().contains(q)).toList();

    // Keyword filter (from trending chips)
    if (_selectedKeyword != null && _selectedKeyword!.isNotEmpty) {
      final k = _selectedKeyword!.toLowerCase();
      list = list.where((n) => n.title.toLowerCase().contains(k)).toList();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Market News'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loading ? null : _load),
        ],
      ),
      body: Column(
        children: [
          // Search box (local filter)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Filter headlines',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),

          // Trending chips (load state + error + chips)
          if (_loadingTrending) const LinearProgressIndicator(minHeight: 2),
          if (_trendingError != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Trending error: $_trendingError',
                        style: const TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            ),
          if (_trending.isNotEmpty)
            TrendingChips(
              keywords: _trending,
              selected: _selectedKeyword,
              onSelect: (k) => setState(() => _selectedKeyword = k),
            ),

          if (_loading) const LinearProgressIndicator(),

          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                const Icon(Icons.error_outline, color: Colors.red),
                const SizedBox(width: 8),
                Expanded(child: Text(_error!, style: const TextStyle(color: Colors.red))),
              ]),
            ),

          // Headlines list
          Expanded(
            child: ListView.separated(
              itemCount: list.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final n = list[i];
                final when = n.pubDate?.toLocal().toString().split('.').first ?? '';
                return InkWell(
                  onTap: () => _openDetail(n),
                  child: ListTile(
                    title: Text(
                      n.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text([n.source, when].where((s) => s.isNotEmpty).join(' • ')),
                    trailing: const Icon(Icons.open_in_new),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
