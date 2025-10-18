// lib/company_news_page.dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'services/news_service.dart';

class CompanyNewsPage extends StatefulWidget {
  final String symbol;
  const CompanyNewsPage({super.key, required this.symbol});

  @override
  State<CompanyNewsPage> createState() => _CompanyNewsPageState();
}

class _CompanyNewsPageState extends State<CompanyNewsPage> {
  bool _loading = true;
  String? _error;
  List<NewsItem> _items = const [];
  final _search = TextEditingController();

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

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final items = await NewsService.fetchCompanyNews(widget.symbol, limit: 50);
      setState(() { _items = items; _loading = false; });
    } catch (e) {
      setState(() { _error = '$e'; _loading = false; });
    }
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();
    final list = q.isEmpty
        ? _items
        : _items.where((n) => n.title.toLowerCase().contains(q) || n.source.toLowerCase().contains(q)).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('News – ${widget.symbol.toUpperCase()}'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loading ? null : _load),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Filter headlines',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                const Icon(Icons.error_outline, color: Colors.red),
                const SizedBox(width: 8),
                Expanded(child: Text(_error!, style: const TextStyle(color: Colors.red))),
              ]),
            ),
          Expanded(
            child: ListView.separated(
              itemCount: list.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final n = list[i];
                final when = n.pubDate?.toLocal().toString().split('.').first ?? '';
                return ListTile(
                  title: Text(n.title),
                  subtitle: Text([n.source, when].where((s) => s.isNotEmpty).join(' • ')),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _open(n.link),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
