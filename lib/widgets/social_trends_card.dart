// lib/widgets/social_trends_card.dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/market_repo.dart'; // RedditPost, SentimentPoint, MarketRepo
import '../social_trends_page.dart';   // <-- wire "See more" navigation

class SocialTrendsCard extends StatefulWidget {
  final String symbol;
  final MarketRepo repo;

  const SocialTrendsCard({
    super.key,
    required this.symbol,
    required this.repo,
  });

  @override
  State<SocialTrendsCard> createState() => _SocialTrendsCardState();
}

class _SocialTrendsCardState extends State<SocialTrendsCard> {
  static const int _maxPosts = 6; // how many to show in the card

  bool _loading = true;
  String? _error;

  List<RedditPost> _posts = const [];
  List<SentimentPoint> _series = const [];
  String _summary = '…';

  @override
  void initState() {
    super.initState();
    _load();
  }

  // --- utils ---------------------------------------------------------------

  int _ts(String? createdUtc) {
    if (createdUtc == null || createdUtc.isEmpty) return 0;
    final n = int.tryParse(createdUtc);
    if (n != null) return n; // seconds/millis ok for ordering
    return DateTime.tryParse(createdUtc)?.millisecondsSinceEpoch ?? 0;
  }

  List<RedditPost> _dedupePosts(List<RedditPost> posts) {
    // key = normalized "title|host"
    final map = <String, RedditPost>{};
    for (final p in posts) {
      final host = Uri.tryParse(p.url)?.host?.toLowerCase() ?? '';
      final key = '${p.title.trim().toLowerCase()}|$host';
      final existing = map[key];
      if (existing == null || _ts(p.createdUtc) > _ts(existing.createdUtc)) {
        map[key] = p; // keep most recent
      }
    }
    final unique = map.values.toList()
      ..sort((a, b) => _ts(b.createdUtc).compareTo(_ts(a.createdUtc)));
    return unique;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final posts = await widget.repo.reddit(widget.symbol);
      final (series, summary) = await widget.repo.sentiment(widget.symbol);

      final deduped = _dedupePosts(posts);

      setState(() {
        _posts = deduped.take(_maxPosts).toList(); // limit shown
        _series = series;
        _summary = summary.isEmpty ? 'Neutral' : summary;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load social trends: $e';
        _loading = false;
      });
    }
  }

  // --- UI helpers ----------------------------------------------------------

  Widget _seriesMiniRow() {
    if (_series.isEmpty) {
      return const Text('No recent sentiment data');
    }
    // Show last 2 points compactly
    final last = _series.length >= 2 ? _series.sublist(_series.length - 2) : _series;
    return Row(
      children: last
          .map((p) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              p.date,
              style: Theme.of(context).textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              p.score.toString(),
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ],
        ),
      ))
          .toList(),
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // --- build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Text('Social Trends', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                IconButton(
                  tooltip: 'Refresh',
                  icon: const Icon(Icons.refresh),
                  onPressed: _loading ? null : _load,
                ),
              ],
            ),
            const SizedBox(height: 4),

            if (_loading) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
            ],

            if (_error != null) ...[
              Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],

            // Summary label
            Text(
              _summary.isEmpty ? 'Neutral' : _summary,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),

            // Mini series row (compact)
            _seriesMiniRow(),
            const SizedBox(height: 12),

            // Posts list (deduped & limited)
            ..._posts.map((p) {
              final host = Uri.tryParse(p.url)?.host ?? '';
              final when = p.createdUtc ?? '';
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: InkWell(
                  onTap: () => _openUrl(p.url),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('•  '),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.title, style: Theme.of(context).textTheme.bodyMedium),
                            const SizedBox(height: 2),
                            Text(
                              '$host  •  $when',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),

            if (_posts.isEmpty && !_loading && _error == null)
              const Text('No recent posts found.'),

            // See more (opens full page)
            if (_posts.isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SocialTrendsPage(
                          symbol: widget.symbol,
                          repo: widget.repo,
                        ),
                      ),
                    );
                  },
                  child: const Text('See more'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
