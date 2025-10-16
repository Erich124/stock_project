import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models.dart';
import '../services/market_repo.dart';

class SocialTrendsCard extends StatefulWidget {
  final String symbol;
  final MarketRepo repo;
  const SocialTrendsCard({super.key, required this.symbol, required this.repo});

  @override
  State<SocialTrendsCard> createState() => _SocialTrendsCardState();
}

class _SocialTrendsCardState extends State<SocialTrendsCard> {
  late Future<void> _future;
  List<RedditPost> _posts = [];
  List<SentimentPoint> _series = [];
  SentimentSummary? _summary;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<void> _load() async {
    final posts = await widget.repo.reddit(widget.symbol);
    final (series, summary) = await widget.repo.sentiment(widget.symbol);
    setState(() {
      _posts = posts.take(5).toList();
      _series = series;
      _summary = summary;
    });
  }

  Color _summaryColor(String label) {
    switch (label) {
      case 'Positive':
        return Colors.green;
      case 'Negative':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder(
          future: _future,
          builder: (ctx, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const SizedBox(height: 72, child: Center(child: CircularProgressIndicator()));
            }
            if (_summary == null) {
              return const Text('No social data available.');
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.public),
                    const SizedBox(width: 8),
                    const Text('Social Trends', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _summaryColor(_summary!.label).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Sentiment: ${_summary!.label}',
                        style: TextStyle(color: _summaryColor(_summary!.label), fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_series.isNotEmpty)
                  Text(
                    _sparkline(_series.map((e) => e.value).toList()),
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                const SizedBox(height: 12),
                ..._posts.map((p) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text('▲ ${p.score}   💬 ${p.comments}   ${p.createdAt.toLocal()}'.split('.').first),
                  onTap: () => launchUrl(Uri.parse(p.url), mode: LaunchMode.externalApplication),
                )),
              ],
            );
          },
        ),
      ),
    );
  }

  // Simple ASCII sparkline; swap with a chart later if you want.
  String _sparkline(List<double> xs) {
    if (xs.isEmpty) return '';
    final blocks = ['▁','▂','▃','▄','▅','▆','▇','█'];
    var minV = xs.first, maxV = xs.first;
    for (final v in xs) { if (v < minV) minV = v; if (v > maxV) maxV = v; }
    var span = (maxV - minV).abs();
    if (span < 1e-9) span = 1.0;
    return xs.map((v) {
      final idx = ((v - minV) / span * (blocks.length - 1)).clamp(0, blocks.length - 1).round();
      return blocks[idx];
    }).join();
  }
}
