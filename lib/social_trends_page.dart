// lib/social_trends_page.dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'services/market_repo.dart'; // RedditPost, SentimentPoint, MarketRepo

class SocialTrendsPage extends StatefulWidget {
  final String symbol;
  final MarketRepo repo;

  const SocialTrendsPage({
    super.key,
    required this.symbol,
    required this.repo,
  });

  @override
  State<SocialTrendsPage> createState() => _SocialTrendsPageState();
}

class _SocialTrendsPageState extends State<SocialTrendsPage> {
  static const int _pageSize = 15;

  bool _loading = true;
  String? _error;

  List<RedditPost> _allPosts = const [];
  List<RedditPost> _viewPosts = const [];
  List<SentimentPoint> _series = const [];
  String _summary = '…';

  // UI state
  final _search = TextEditingController();
  bool _dedupe = true;
  int _visible = _pageSize;
  String _sort = 'Newest';
  String _hostFilter = 'All'; // All / reddit.com / twitter.com / etc.

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

  // ---------- utils ----------

  int _ts(String? createdUtc) {
    if (createdUtc == null || createdUtc.isEmpty) return 0;
    final n = int.tryParse(createdUtc);
    if (n != null) return n; // sec/millis okay
    return DateTime.tryParse(createdUtc)?.millisecondsSinceEpoch ?? 0;
  }

  String _host(String url) => Uri.tryParse(url)?.host?.toLowerCase() ?? '';

  List<RedditPost> _dedupePosts(List<RedditPost> posts) {
    final map = <String, RedditPost>{};
    for (final p in posts) {
      final key = '${p.title.trim().toLowerCase()}|${_host(p.url)}';
      final existing = map[key];
      if (existing == null || _ts(p.createdUtc) > _ts(existing.createdUtc)) {
        map[key] = p; // keep newer
      }
    }
    return map.values.toList();
  }

  List<RedditPost> _applyFilters() {
    Iterable<RedditPost> list = _allPosts;

    if (_dedupe) list = _dedupePosts(list.toList());

    final q = _search.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((p) =>
      p.title.toLowerCase().contains(q) ||
          (_host(p.url).contains(q)));
    }

    if (_hostFilter != 'All') {
      list = list.where((p) => _host(p.url) == _hostFilter);
    }

    final arr = list.toList();
    switch (_sort) {
      case 'Oldest':
        arr.sort((a, b) => _ts(a.createdUtc).compareTo(_ts(b.createdUtc)));
        break;
      case 'Score':
      // if you have score on the post object, you can sort by it; otherwise fallback to newest
        arr.sort((a, b) => _ts(b.createdUtc).compareTo(_ts(a.createdUtc)));
        break;
      case 'Newest':
      default:
        arr.sort((a, b) => _ts(b.createdUtc).compareTo(_ts(a.createdUtc)));
    }
    return arr;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final posts = await widget.repo.reddit(widget.symbol);
      final (series, summary) = await widget.repo.sentiment(widget.symbol);

      // build host list choices dynamically (top few common hosts)
      final filtered = posts.where((p) => p.url.isNotEmpty).toList();
      final hosts = <String>{ for (final p in filtered) _host(p.url) }..removeWhere((h) => h.isEmpty);
      final sortedHosts = hosts.toList()..sort();

      setState(() {
        _allPosts = posts;
        _series = series;
        _summary = summary.isEmpty ? 'Neutral' : summary;
        _viewPosts = _applyFilters();
        _visible = _pageSize; // reset pagination
        _loading = false;
      });

      // If you want the host filter list shown in a dropdown, keep _hostFilter options dynamic.
      _hostOptions = ['All', ...sortedHosts];
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load social trends: $e';
        _loading = false;
      });
    }
  }

  List<String> _hostOptions = const ['All'];

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  String _prettyWhen(String? createdUtc) {
    final t = _ts(createdUtc);
    if (t == 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(
      t > 20000000000 ? t : t * 1000, // handle sec vs ms
      isUtc: true,
    ).toLocal();
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  // ---------- build ----------

  @override
  Widget build(BuildContext context) {
    final items = _viewPosts.take(_visible).toList();
    final canLoadMore = _visible < _viewPosts.length;

    return Scaffold(
      appBar: AppBar(title: Text('Social Trends – ${widget.symbol}')),
      body: Column(
        children: [
          // top summary row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Text('Sentiment: $_summary',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  tooltip: 'Refresh',
                  icon: const Icon(Icons.refresh),
                  onPressed: _loading ? null : _load,
                ),
              ],
            ),
          ),

          // controls
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                // search
                SizedBox(
                  width: 260,
                  child: TextField(
                    controller: _search,
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search),
                      labelText: 'Search posts',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) {
                      setState(() {
                        _viewPosts = _applyFilters();
                        _visible = _pageSize;
                      });
                    },
                  ),
                ),

                // sort
                DropdownButton<String>(
                  value: _sort,
                  items: const [
                    DropdownMenuItem(value: 'Newest', child: Text('Newest')),
                    DropdownMenuItem(value: 'Oldest', child: Text('Oldest')),
                    DropdownMenuItem(value: 'Score',  child: Text('Score (if available)')),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() {
                      _sort = v;
                      _viewPosts = _applyFilters();
                      _visible = _pageSize;
                    });
                  },
                ),

                // host filter
                DropdownButton<String>(
                  value: _hostFilter,
                  items: _hostOptions
                      .map((h) => DropdownMenuItem(value: h, child: Text(h)))
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() {
                      _hostFilter = v;
                      _viewPosts = _applyFilters();
                      _visible = _pageSize;
                    });
                  },
                ),

                // dedupe toggle
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Deduplicate'),
                    Switch(
                      value: _dedupe,
                      onChanged: (v) {
                        setState(() {
                          _dedupe = v;
                          _viewPosts = _applyFilters();
                          _visible = _pageSize;
                        });
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),

          if (_loading) const LinearProgressIndicator(),

          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_error!, style: const TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 8),

          // list
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final p = items[i];
                final host = _host(p.url);
                final when = _prettyWhen(p.createdUtc);
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  title: Text(p.title),
                  subtitle: Text([host, when].where((x) => x.isNotEmpty).join(' • ')),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _open(p.url),
                );
              },
            ),
          ),

          // pagination
          if (canLoadMore)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: FilledButton(
                onPressed: () => setState(() => _visible += _pageSize),
                child: Text('Load more (${_viewPosts.length - _visible} more)'),
              ),
            ),
        ],
      ),
    );
  }
}
