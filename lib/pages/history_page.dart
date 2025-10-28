import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/history_service.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> with SingleTickerProviderStateMixin {
  late final TabController _tab;
  @override
  void initState() { super.initState(); _tab = TabController(length: 2, vsync: this); }
  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        bottom: TabBar(controller: _tab, tabs: const [Tab(text: 'Recent'), Tab(text: 'Searches')]),
        actions: [
          IconButton(
            tooltip: 'Clear',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final idx = _tab.index;
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Clear history?'),
                  content: Text(idx == 0 ? 'Clear recent views?' : 'Clear searches?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                    FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Clear')),
                  ],
                ),
              );
              if (confirmed != true) return;
              if (idx == 0) {
                await HistoryService.instance.clearRecentViews();
              } else {
                await HistoryService.instance.clearSearchHistory();
              }
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(idx == 0 ? 'Recent views cleared' : 'Searches cleared')),
              );
            },
          ),
        ],
      ),
      body: TabBarView(
        controller: _tab,
        children: const [_RecentTab(), _SearchesTab()],
      ),
    );
  }
}

class _RecentTab extends StatelessWidget {
  const _RecentTab();
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: HistoryService.instance.recentViewsStream(limit: 100),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data?.docs ?? const [];
        if (docs.isEmpty) return const Center(child: Text('No recent views yet.'));
        return ListView.separated(
          itemCount: docs.length,
          separatorBuilder: (_, __) => const Divider(height: 0),
          itemBuilder: (context, i) {
            final d = docs[i].data();
            final sym = (d['symbol'] ?? '') as String;
            final where = (d['where'] ?? '') as String;
            final ts = (d['ts'] as Timestamp?)?.toDate();
            return ListTile(
              leading: const Icon(Icons.trending_up),
              title: Text(sym),
              subtitle: Text(where.isEmpty ? 'View' : 'View • $where'),
              trailing: Text(ts == null ? '' : _fmt(ts)),
            );
          },
        );
      },
    );
  }
}

class _SearchesTab extends StatelessWidget {
  const _SearchesTab();
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: HistoryService.instance.searchHistoryStream(limit: 100),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data?.docs ?? const [];
        if (docs.isEmpty) return const Center(child: Text('No searches yet.'));
        return ListView.separated(
          itemCount: docs.length,
          separatorBuilder: (_, __) => const Divider(height: 0),
          itemBuilder: (context, i) {
            final d = docs[i].data();
            final q = (d['query'] ?? '') as String;
            final source = (d['source'] ?? '') as String;
            final ts = (d['ts'] as Timestamp?)?.toDate();
            return ListTile(
              leading: const Icon(Icons.search),
              title: Text(q),
              subtitle: Text(source.isEmpty ? 'Search' : 'Search • $source'),
              trailing: Text(ts == null ? '' : _fmt(ts)),
            );
          },
        );
      },
    );
  }
}

String _fmt(DateTime dt) {
  final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final mm = dt.minute.toString().padLeft(2, '0');
  final ampm = dt.hour >= 12 ? 'PM' : 'AM';
  return '${dt.month}/${dt.day} $h:$mm $ampm';
}
