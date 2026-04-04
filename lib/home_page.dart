import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'models.dart';
import 'stock_details_page.dart';
import 'markets_page.dart';
import 'account_profile_page.dart';
import 'services/alpha_vantage.dart' as alpha_vantage;

// Backend client + repo
import 'services/api_client.dart';
import 'services/market_repo.dart';

// History logging
import 'services/history_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tabIndex = 0;
  final _search = TextEditingController();
  bool _loading = false;
  String? _error;

  late final ApiClient _api;
  late final MarketRepo _repo;

  @override
  void initState() {
    super.initState();
    _api = ApiClient();
    _repo = MarketRepo(_api);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<bool> _symbolExists(String symbolUpper) async {
    return alpha_vantage.symbolExists(symbolUpper);
  }

  Future<StockSummary> _fetchSummary(String symbolUpper) async {
    return _repo.summary(symbolUpper);
  }

  Future<void> _onSearch() async {
    final raw = _search.text.trim();
    if (raw.isEmpty) {
      setState(() => _error = 'Please enter a stock name or ticker.');
      return;
    }
    setState(() {
      _error = null;
      _loading = true;
    });

    final symbolUpper = raw.toUpperCase();
    try {
      // Log the user's search
      await HistoryService.instance.logSearch(
        query: raw,
        source: 'HomeSearch',
        symbolHint: symbolUpper,
      );

      final exists = await _symbolExists(symbolUpper);
      if (!exists) {
        setState(() => _error = 'This stock does not exist');
        return;
      }

      final summary = await _fetchSummary(symbolUpper);
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => StockDetailsPage(summary: summary)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Failed to fetch data: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // --------------------  UI TABS  --------------------

  Widget _homeTab() {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _onSearch(),
              decoration: InputDecoration(
                labelText: 'Search by stock names',
                hintText: 'e.g. AAPL, NVDA, AMZN…',
                border: const OutlineInputBorder(),
                suffixIcon: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(12.0),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => _search.clear(),
                        tooltip: 'Clear',
                      ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Go'),
                onPressed: _loading ? null : _onSearch,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
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
            ],
            const SizedBox(height: 16),

            // Recent searches area — fills remaining height and scrolls
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: const _RecentSearchesCard(limit: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      _homeTab(),
      MarketsPage(
        onOpenSymbol: (symbol) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => StockDetailsPage(
                summary: StockSummary(
                  symbol: symbol,
                  price: 0,
                  changePct: 0,
                  sentiment: 'Neutral',
                ),
              ),
            ),
          );
        },
      ),
      const AccountProfilePage(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock Scout'),
        actions: [
          IconButton(
            tooltip: 'History',
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.of(context).pushNamed('/history'),
          ),
        ],
      ),
      body: IndexedStack(index: _tabIndex, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.show_chart),
            selectedIcon: Icon(Icons.stacked_line_chart),
            label: 'Markets',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

// --------------------  Recent Searches Card  --------------------

class _RecentSearchesCard extends StatelessWidget {
  const _RecentSearchesCard({this.limit = 20});
  final int limit;

  Stream<QuerySnapshot<Map<String, dynamic>>> _stream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      // empty stream if not logged in
      return const Stream<QuerySnapshot<Map<String, dynamic>>>.empty();
    }
    final col = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('search_history');
    return col.orderBy('ts', descending: true).limit(limit).snapshots();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Text(
                'Recent Searches',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).pushNamed('/history'),
                child: const Text('See all'),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // List
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _stream(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  );
                }

                final docs = snap.data?.docs ?? const [];
                if (docs.isEmpty) {
                  return Center(
                    child: Text(
                      'recent search history',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final d = docs[i].data();
                    final query = (d['query'] ?? '') as String;
                    final symbol =
                        (d['symbol'] ?? d['symbolHint'] ?? '') as String;
                    final source = (d['source'] ?? '') as String;

                    DateTime? ts;
                    final rawTs = d['ts'];
                    if (rawTs is Timestamp) {
                      ts = rawTs.toDate();
                    } else if (rawTs is String) {
                      ts = DateTime.tryParse(rawTs);
                    }
                    final rel = _fmtAgo(ts);

                    return ListTile(
                      leading: const Icon(Icons.search),
                      title: Text(query),
                      subtitle: Text(
                        [
                          if (symbol.isNotEmpty) 'symbol: $symbol',
                          if (source.isNotEmpty) 'from: $source',
                          if (rel.isNotEmpty) rel,
                        ].join(' • '),
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => _openSymbol(
                        context,
                        symbol.isNotEmpty ? symbol : query,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static String _fmtAgo(DateTime? t) {
    if (t == null) return '';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }

  Future<void> _openSymbol(BuildContext context, String raw) async {
    final symbolUpper = raw.trim().toUpperCase();
    if (symbolUpper.isEmpty) return;

    // Reuse the repo from the nearest HomePage state
    final state = context.findAncestorStateOfType<_HomePageState>();
    if (state == null) return;

    try {
      // Log as a search coming from RecentList
      await HistoryService.instance.logSearch(
        query: raw,
        source: 'RecentList',
        symbolHint: symbolUpper,
      );

      final exists = await state._symbolExists(symbolUpper);
      if (!context.mounted) return;
      if (!exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Symbol $symbolUpper not found')),
        );
        return;
      }

      final summary = await state._fetchSummary(symbolUpper);
      if (!context.mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => StockDetailsPage(summary: summary)),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Open failed: $e')));
    }
  }
}
