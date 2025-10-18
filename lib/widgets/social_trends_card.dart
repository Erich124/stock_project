// lib/widgets/social_trends_card.dart
import 'package:flutter/material.dart';
import '../services/market_repo.dart';

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
  bool _loading = true;
  String? _error;
  List<RedditPost> _posts = const [];
  List<SentimentPoint> _series = const [];
  String _summary = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final posts = await widget.repo.reddit(widget.symbol);
      final (series, summary) = await widget.repo.sentiment(widget.symbol);
      if (!mounted) return;
      setState(() {
        _posts = posts;
        _series = series;
        _summary = summary;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Card(child: Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()));
    }
    if (_error != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Social Trends', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Error: $_error'),
            const SizedBox(height: 8),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ]),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Social Trends', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (_summary.isNotEmpty) Text(_summary),
          const SizedBox(height: 12),
          if (_series.isNotEmpty)
            SizedBox(
              height: 80,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _series.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, i) {
                  final s = _series[i];
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(s.date, style: const TextStyle(fontSize: 10)),
                      const SizedBox(height: 4),
                      Text(s.score.toString()),
                    ],
                  );
                },
              ),
            ),
          const SizedBox(height: 12),
          if (_posts.isNotEmpty)
            ..._posts.take(5).map((p) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text('• ${p.title} (@${p.author})', maxLines: 2, overflow: TextOverflow.ellipsis),
            )),
        ]),
      ),
    );
  }
}
