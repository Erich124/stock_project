// lib/markets_page.dart
import 'package:flutter/material.dart';

import 'models.dart';
import 'services/alpha_vantage.dart';
import 'market_news_page.dart'; // NEW: open market-wide news

typedef OpenSymbol = void Function(String symbol);

class MarketsPage extends StatefulWidget {
  final OpenSymbol onOpenSymbol;
  const MarketsPage({super.key, required this.onOpenSymbol});

  @override
  State<MarketsPage> createState() => _MarketsPageState();
}

class _MarketsPageState extends State<MarketsPage> {
  late Future<TopMovers> _future;

  /// Price floor options (USD). Users can pick one.
  static const List<double> _floors = [0, 10, 20, 50];
  double _selectedFloor = 10;

  @override
  void initState() {
    super.initState();
    _future = fetchTopMoversRaw();
  }

  Future<void> _refresh() async {
    setState(() => _future = fetchTopMoversRaw());
    await _future.catchError((_) {});
  }

  // ---- Helpers: rank purely by % change ----

  // Gainers: sort by changePct descending (largest positive first)
  List<Mover> _rankGainers(List<Mover> xs) {
    final copy = [...xs];
    copy.sort((a, b) => b.changePct.compareTo(a.changePct));
    return copy;
  }

  // Decliners: sort by changePct ascending (most negative first)
  List<Mover> _rankDecliners(List<Mover> xs) {
    final copy = [...xs];
    copy.sort((a, b) => a.changePct.compareTo(b.changePct));
    return copy;
  }

  // Filter by price floor and take top N
  List<Mover> _topNWithFloor(List<Mover> ranked, {required int n, required double floor}) {
    return ranked.where((m) => m.price >= floor).take(n).toList();
  }

  // ---- UI bits ----

  Widget _tile(BuildContext context, Mover m) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final isUp = m.changePct >= 0;
    final pct  = '${isUp ? '+' : ''}${m.changePct.toStringAsFixed(2)}%';
    final arrow = isUp ? Icons.north_east : Icons.south_east;
    final color = isUp ? Colors.green : Colors.red;

    return InkWell(
      onTap: () => widget.onOpenSymbol(m.symbol),
      borderRadius: BorderRadius.circular(12),
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.outlineVariant),
          color: colors.surfaceContainerHighest,
        ),
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(m.symbol, style: text.titleMedium),
            const SizedBox(height: 4),
            Text('\$${m.price.toStringAsFixed(2)}', style: text.bodyMedium),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(arrow, size: 16, color: color),
                const SizedBox(width: 4),
                Text(
                  pct,
                  style: text.bodyMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _grid(BuildContext context, List<Mover> items) {
    final width = MediaQuery.of(context).size.width;
    final crossAxisCount = width < 380 ? 2 : 3;
    final aspect = width < 380 ? 0.95 : 1.0;
    final show = items.take(6).toList();

    return GridView.builder(
      itemCount: show.length,
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: aspect,
      ),
      itemBuilder: (_, i) => _tile(context, show[i]),
    );
  }

  Widget _headerRow() {
    final text = Theme.of(context).textTheme;

    return Row(
      children: [
        Expanded(child: Text('Top 6 • Price Filter', style: text.titleLarge)),

        // Quick link to market-wide news
        IconButton(
          tooltip: 'Market News',
          icon: const Icon(Icons.article_outlined),
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MarketNewsPage()),
            );
          },
        ),
        const SizedBox(width: 4),

        // Price floor selector
        DropdownButton<double>(
          value: _selectedFloor,
          onChanged: (v) {
            if (v == null) return;
            setState(() => _selectedFloor = v);
          },
          items: _floors
              .map((f) => DropdownMenuItem(
            value: f,
            child: Text(f == 0 ? 'All prices' : '≥ \$${f.toStringAsFixed(0)}'),
          ))
              .toList(),
        ),
        const SizedBox(width: 4),

        IconButton(
          onPressed: _refresh,
          icon: const Icon(Icons.refresh),
          tooltip: 'Refresh',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<TopMovers>(
          future: _future,
          builder: (context, snap) {
            // Loading
            if (snap.connectionState == ConnectionState.waiting) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _headerRow(),
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
              );
            }

            // Error
            if (snap.hasError) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _headerRow(),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Theme.of(context).colorScheme.error),
                    ),
                    child: Text(
                      'Could not load movers: ${snap.error}',
                      style: text.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              );
            }

            // Success
            final data = snap.data!;
            final rankedGainers   = _rankGainers(data.gainers);
            final rankedDecliners = _rankDecliners(data.losers);

            final gainersTop   = _topNWithFloor(rankedGainers,   n: 6, floor: _selectedFloor);
            final declinersTop = _topNWithFloor(rankedDecliners, n: 6, floor: _selectedFloor);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _headerRow(),
                const SizedBox(height: 16),

                // Gainers
                Text('Top 6 Gainers (by % change)', style: text.titleMedium),
                const SizedBox(height: 12),
                _grid(context, gainersTop),

                const SizedBox(height: 24),

                // Decliners
                Text('Top 6 Decliners (by % change)', style: text.titleMedium),
                const SizedBox(height: 12),
                _grid(context, declinersTop),

                const SizedBox(height: 12),
                Text(
                  'Source: Alpha Vantage TOP_GAINERS_LOSERS',
                  style: text.bodySmall,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
