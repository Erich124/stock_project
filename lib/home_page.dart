// lib/home_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:firebase_auth/firebase_auth.dart';

import 'models.dart';
import 'stock_details_page.dart';
import 'markets_page.dart';
import 'account_profile_page.dart';
import 'login_page.dart'; // for redirect after logout

// NEW: backend client + repo
import 'services/api_client.dart';
import 'services/market_repo.dart';

// NEW: history logging
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
    final baseUrl = (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
        ? 'http://10.0.2.2:8000'
        : 'http://127.0.0.1:8000';
    _api = ApiClient(baseUrl: baseUrl);
    _repo = MarketRepo(_api);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<bool> _symbolExists(String symbolUpper) async {
    final j = await _api.getJsonMap('/symbols/$symbolUpper/exists');
    return (j['exists'] == true);
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
      // Log the user's search (Step 3 hook)
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

  Widget _homeTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _onSearch(), // logs search inside
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
              onPressed: _loading ? null : _onSearch, // logs search inside
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
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
          ],
          const SizedBox(height: 24),
          Expanded(
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: const Text(
                'Home Dashboard (ignore for now)',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileTab() {
    final user = FirebaseAuth.instance.currentUser;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.person, size: 80, color: Colors.deepPurple),
            const SizedBox(height: 16),
            Text(
              user != null
                  ? 'Logged in as: ${user.email}'
                  : 'No user signed in',
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.logout),
              label: const Text('Sign Out'),
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
                if (context.mounted) {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginPage()),
                        (route) => false,
                  );
                }
              },
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
      MarketsPage(onOpenSymbol: (symbol) {
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
      }),
      _profileTab(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock Scout'),
        actions: [
          // History button (opens the minimal History UI at /history)
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
