import 'package:flutter/material.dart';
import 'models.dart';
import 'services/alpha_vantage.dart';

class StockDetailsPage extends StatefulWidget {
  final StockSummary summary;
  const StockDetailsPage({super.key, required this.summary});

  @override
  State<StockDetailsPage> createState() => _StockDetailsPageState();
}

class _StockDetailsPageState extends State<StockDetailsPage> {
  late Future<LiveQuote> _future;
  String? _error;

  @override
  void initState() {
    super.initState();
    _future = fetchStockQuote(widget.summary.symbol);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.summary.symbol} Details')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
                        style: TextStyle(color: color, fontWeight: FontWeight.w600),
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
          Card(
            child: const ListTile(
              leading: Icon(Icons.trending_up),
              title: Text('Social Trends'),
              subtitle: Text('Twitter / Reddit / Google Trends (from Flask)'),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.lightbulb),
              title: const Text('Prediction / Recommendation'),
              subtitle: Text('Current sentiment: • ${''}'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Sentiment (summary): ${widget.summary.sentiment}',
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
