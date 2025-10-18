// lib/stock_details_page.dart
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';

import 'models.dart';
import 'services/alpha_vantage.dart'; // provides fetchStockQuote + LiveQuote

// Backend client + repo + social trends UI
import 'services/api_client.dart';
import 'services/market_repo.dart';
import 'widgets/social_trends_card.dart';

class StockDetailsPage extends StatefulWidget {
  final StockSummary summary;
  const StockDetailsPage({super.key, required this.summary});

  @override
  State<StockDetailsPage> createState() => _StockDetailsPageState();
}

class _StockDetailsPageState extends State<StockDetailsPage> {
  late Future<LiveQuote> _future;
  String? _error;

  // Backend repo + sentiment summary
  late final MarketRepo _repo;
  SentimentSummary? _sentSummary;

  @override
  void initState() {
    super.initState();

    // Live pricing (AlphaVantage or your existing source)
    _future = fetchStockQuote(widget.summary.symbol);

    // Base URL: Android emulator requires 10.0.2.2; others can use localhost
    final baseUrl = (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
        ? 'http://10.0.2.2:8000'
        : 'http://127.0.0.1:8000';

    _repo = MarketRepo(ApiClient(baseUrl: baseUrl));

    // Fetch sentiment once for the “Prediction / Recommendation” card
    _loadSentimentSummary();
  }

  Future<void> _loadSentimentSummary() async {
    try {
      // Repo returns a Dart record: (List<SentimentPoint>, String)
      final (series, summaryText) =
      await _repo.fetchSentiment(widget.summary.symbol);

      if (!mounted) return;

      // Compute average score for your SentimentSummary(avg, label)
      final avg = series.isEmpty
          ? 0.0
          : series
          .map((e) => e.score.toDouble())
          .reduce((a, b) => a + b) /
          series.length;

      setState(() {
        _sentSummary = SentimentSummary(
          avg: avg,
          label: summaryText,
        );
      });
    } catch (_) {
      // Ignore—SocialTrendsCard will render its own state/errors.
    }
  }

  @override
  Widget build(BuildContext context) {
    final symbol = widget.summary.symbol;

    return Scaffold(
      appBar: AppBar(title: Text('$symbol Details')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ===== Live Price Card =====
          FutureBuilder<LiveQuote>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.attach_money),
                    title: const Text('Loading live price…'),
                    subtitle: const Text('Stock Pricing'),
                    trailing: const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                );
              }

              if (snap.hasError) {
                _error ??=
                'Live price unavailable (${snap.error}). Showing cached/simulated.';
              }

              final live = snap.data;
              final price = live?.price ?? widget.summary.price;
              final changePct = live?.changePct ?? widget.summary.changePct;
              final up = changePct >= 0;
              final color = up ? Colors.green : Colors.red;

              return Column(
                children: [
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.attach_money),
                      title: Text('\$${price.toStringAsFixed(2)}'),
                      subtitle: const Text('Stock Pricing'),
                      trailing: Text(
                        '${up ? '+' : ''}${changePct.toStringAsFixed(2)}%',
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _error!,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              );
            },
          ),

          const SizedBox(height: 8),

          // ===== Social Trends Card (Reddit + sentiment series + links) =====
          SocialTrendsCard(symbol: symbol, repo: _repo),

          const SizedBox(height: 8),

          // ===== Prediction / Recommendation =====
          Card(
            child: ListTile(
              leading: const Icon(Icons.lightbulb),
              title: const Text('Prediction / Recommendation'),
              subtitle: Text('Current sentiment: ${_sentSummary?.label ?? '…'}'),
            ),
          ),

          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Sentiment (summary): ${_sentSummary?.label ?? widget.summary.sentiment}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),

          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.home),
            label: const Text('Back to Home'),
          ),
        ],
      ),
    );
  }
}
