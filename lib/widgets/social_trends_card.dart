// lib/widgets/social_trends_card.dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:fl_chart/fl_chart.dart';

import '../services/history_service.dart'; // <-- add logging
import '../services/market_repo.dart'; // RedditPost, SentimentPoint, MarketRepo
import '../social_trends_page.dart'; // "See more" navigation

class SocialTrendsCard extends StatefulWidget {
  final String symbol;
  final MarketRepo repo;

  const SocialTrendsCard({super.key, required this.symbol, required this.repo});

  @override
  State<SocialTrendsCard> createState() => _SocialTrendsCardState();
}

class _SocialTrendsCardState extends State<SocialTrendsCard> {
  DateTime? _lastUpdated;
  DateTime? _oldestSourceDate;
  static const int _maxPosts = 6;

  bool _loading = true;
  String? _error;

  // Fixed range: Last 14 days
  static const int _windowDays = 14;

  List<RedditPost> _posts = const [];
  List<SentimentPoint> _series = const [];
  String _summary = '…';

  String _formatUpdated(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final m = local.minute.toString().padLeft(2, '0');
    final ampm = local.hour >= 12 ? 'PM' : 'AM';
    return 'Updated $h:$m $ampm';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  // --- utils ---------------------------------------------------------------

  int _ts(String? createdUtc) {
    if (createdUtc == null || createdUtc.isEmpty) return 0;
    final n = num.tryParse(createdUtc);
    if (n != null) {
      // Heuristic: 13-digit ms, 10-digit sec
      final ms = n > 2000000000000 ? n : n * 1000;
      return ms.toInt();
    }
    return DateTime.tryParse(createdUtc)?.millisecondsSinceEpoch ?? 0;
  }

  DateTime? _parseDateLoose(String s) {
    // Accept "YYYY-MM-DD", ISO, or millis/seconds
    final asNum = num.tryParse(s);
    if (asNum != null) {
      final ms = asNum > 2000000000000 ? asNum : asNum * 1000;
      return DateTime.fromMillisecondsSinceEpoch(
        ms.toInt(),
        isUtc: true,
      ).toLocal();
    }
    return DateTime.tryParse(s)?.toLocal();
  }

  String _formatPostWhen(String? createdUtc) {
    if (createdUtc == null || createdUtc.isEmpty) return '';
    final dt = _parseDateLoose(createdUtc);
    if (dt == null) return createdUtc;
    return '${dt.month}/${dt.day}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  List<RedditPost> _dedupePosts(List<RedditPost> posts) {
    final map = <String, RedditPost>{}; // key = normalized "title|host"
    for (final p in posts) {
      final uri = Uri.tryParse(p.url);
      final host = uri == null ? '' : uri.host.toLowerCase();
      final key = '${p.title.trim().toLowerCase()}|$host';
      final existing = map[key];
      if (existing == null || _ts(p.createdUtc) > _ts(existing.createdUtc)) {
        map[key] = p; // keep most recent for that title+host
      }
    }
    final unique = map.values.toList()
      ..sort((a, b) => _ts(b.createdUtc).compareTo(_ts(a.createdUtc)));
    return unique;
  }

  List<SentimentPoint> _filterSeriesByWindow(
    List<SentimentPoint> series,
    int days,
  ) {
    if (series.isEmpty) return series;
    final now = DateTime.now();
    final cutoff = now.subtract(Duration(days: days));
    final parsed = <({DateTime t, SentimentPoint p})>[];
    for (final sp in series) {
      final dt = _parseDateLoose(sp.date);
      if (dt != null) parsed.add((t: dt, p: sp));
    }
    parsed.sort((a, b) => a.t.compareTo(b.t));
    return parsed.where((e) => e.t.isAfter(cutoff)).map((e) => e.p).toList();
  }

  double _avgScore(List<SentimentPoint> series) {
    if (series.isEmpty) return 0.0;
    var sum = 0.0;
    for (final p in series) {
      sum += p.score.toDouble();
    }
    return sum / series.length;
  }

  String _coverageLabel() {
    final oldest = _oldestSourceDate;
    if (oldest == null) {
      return 'No recent post data';
    }
    final today = DateTime.now();
    final start = DateTime(oldest.year, oldest.month, oldest.day);
    final end = DateTime(today.year, today.month, today.day);
    final days = end.difference(start).inDays + 1;
    final clamped = days.clamp(1, _windowDays);
    return clamped == 1 ? 'Last 1 day' : 'Last $clamped days';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final posts = await widget.repo.reddit(widget.symbol, days: _windowDays);
      final (series, summary) = await widget.repo.sentiment(
        widget.symbol,
        days: _windowDays,
      );
      final deduped = _dedupePosts(posts);

      if (!mounted) return;
      setState(() {
        _posts = deduped.take(_maxPosts).toList();
        _series = series;
        _oldestSourceDate = deduped.isEmpty
            ? null
            : deduped
                  .map((p) => p.createdUtc)
                  .whereType<String>()
                  .map(_parseDateLoose)
                  .whereType<DateTime>()
                  .fold<DateTime?>(null, (oldest, dt) {
                    if (oldest == null || dt.isBefore(oldest)) return dt;
                    return oldest;
                  });
        _summary = (summary.isEmpty) ? 'Neutral' : summary;
        _loading = false;
        _lastUpdated = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load social trends: $e';
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_error!),
          action: SnackBarAction(label: 'Retry', onPressed: _load),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  // --- open helpers with logging -------------------------------------------

  Future<void> _openUrlLogged(String url, String title) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;

    // Log the view
    await HistoryService.instance.logView(
      type: 'reddit_post',
      id: uri.toString(),
      title: title,
    );

    // Then launch
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _openHostSearch(String host) async {
    if (host.isEmpty) return;
    final q = Uri.encodeComponent('${widget.symbol} site:$host');

    // Log the search intent (optional but useful)
    await HistoryService.instance.logSearch(
      query: '${widget.symbol} site:$host',
      source: 'SocialTrendsCard',
    );

    final url = 'https://www.reddit.com/search/?q=$q&sort=new';
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // --- UI bits -------------------------------------------------------------

  Widget _sparkline(List<SentimentPoint> windowed) {
    if (windowed.isEmpty) return const Text('No recent sentiment data');

    // Parse to points
    final parsed = <({DateTime t, double y})>[];
    for (final sp in windowed) {
      final dt = _parseDateLoose(sp.date);
      if (dt != null) parsed.add((t: dt, y: sp.score.toDouble()));
    }
    if (parsed.isEmpty) return const Text('No recent sentiment data');

    parsed.sort((a, b) => a.t.compareTo(b.t));
    final spots = <FlSpot>[];
    for (var i = 0; i < parsed.length; i++) {
      spots.add(FlSpot(i.toDouble(), parsed[i].y));
    }

    // Y range + nice ticks
    final ys = spots.map((s) => s.y).toList();
    double minY = ys.reduce((a, b) => a < b ? a : b);
    double maxY = ys.reduce((a, b) => a > b ? a : b);

    // small padding
    minY -= 0.02;
    maxY += 0.02;

    final range = (maxY - minY).abs().clamp(0.1, 1.0);
    // choose a clean step (0.05 / 0.1 / 0.2)
    final double yStep = (range <= 0.2)
        ? 0.05
        : (range <= 0.4)
        ? 0.1
        : 0.2;

    // snap bounds to step so ticks land on nice numbers
    minY = (minY / yStep).floor() * yStep;
    maxY = (maxY / yStep).ceil() * yStep;

    String labelForX(double value) {
      if (parsed.isEmpty) return '';
      final idx = value.round().clamp(0, parsed.length - 1);
      final d = parsed[idx].t;
      return '${d.month}/${d.day}';
    }

    final xInterval = parsed.length > 8 ? 3.0 : 2.0;

    return SizedBox(
      height: 200,
      child: LineChart(
        LineChartData(
          // Tooltips
          lineTouchData: LineTouchData(
            handleBuiltInTouches: true,
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (touchedSpots) {
                return touchedSpots.map((s) {
                  final idx = s.x.round().clamp(0, parsed.length - 1);
                  final d = parsed[idx].t;
                  final y = parsed[idx].y;
                  return LineTooltipItem(
                    '${d.month}/${d.day}/${d.year}\nscore: ${y.toStringAsFixed(3)}',
                    const TextStyle(fontWeight: FontWeight.w600),
                  );
                }).toList();
              },
            ),
          ),

          minY: minY,
          maxY: maxY,

          gridData: FlGridData(show: true, horizontalInterval: yStep),
          borderData: FlBorderData(show: true),

          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              axisNameWidget: const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Text('Sentiment score', style: TextStyle(fontSize: 12)),
              ),
              axisNameSize: 18,
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 44,
                interval: yStep,
                getTitlesWidget: (v, meta) => Text(
                  v.toStringAsFixed(1),
                  style: const TextStyle(fontSize: 10),
                ),
              ),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              axisNameWidget: const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text('Date', style: TextStyle(fontSize: 12)),
              ),
              axisNameSize: 22,
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 34,
                getTitlesWidget: (v, meta) => Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    labelForX(v),
                    style: const TextStyle(fontSize: 10),
                  ),
                ),
                interval: xInterval,
              ),
            ),
          ),

          lineBarsData: [
            LineChartBarData(
              spots: (() {
                // Build spots again for rendering (keeps code local to widget)
                final parsed = <({DateTime t, double y})>[];
                for (final sp in windowed) {
                  final dt = _parseDateLoose(sp.date);
                  if (dt != null) parsed.add((t: dt, y: sp.score.toDouble()));
                }
                parsed.sort((a, b) => a.t.compareTo(b.t));
                return List.generate(
                  parsed.length,
                  (i) => FlSpot(i.toDouble(), parsed[i].y),
                );
              })(),
              isCurved: true,
              barWidth: 2,
              dotData: const FlDotData(show: false),
            ),
          ],
        ),
      ),
    );
  }

  // --- build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final windowed = _filterSeriesByWindow(_series, _windowDays);

    return Stack(
      children: [
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with refresh
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Wrap(
                        alignment: WrapAlignment.start,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 2,
                        children: [
                          Text(
                            'Social Trends',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          if (_lastUpdated != null)
                            Text(
                              _formatUpdated(_lastUpdated!),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: Colors.grey),
                            ),
                          Text(
                            _coverageLabel(),
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Refresh',
                      icon: const Icon(Icons.refresh),
                      onPressed: _loading ? null : _load,
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                if (_loading && _posts.isEmpty && _series.isEmpty) ...[
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

                // Summary
                Text(
                  _summary.isEmpty ? 'Neutral' : _summary,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),

                // Chips: Avg + Posts
                Builder(
                  builder: (_) {
                    final avg = _avgScore(windowed);
                    final color = avg > 0.05
                        ? Colors.green
                        : (avg < -0.05 ? Colors.red : Colors.grey);
                    final sign = avg >= 0 ? '+' : '';
                    return Wrap(
                      spacing: 8,
                      children: [
                        Chip(
                          label: Text('Score: $sign${avg.toStringAsFixed(3)}'),
                          backgroundColor: color.withValues(alpha: 0.12),
                          side: BorderSide(
                            color: color.withValues(alpha: 0.35),
                          ),
                        ),
                        Chip(label: Text('Posts: ${_posts.length}')),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 8),

                // Sparkline
                _sparkline(windowed),
                const SizedBox(height: 12),

                // Posts list (deduped & limited)
                ..._posts.map((p) {
                  final host = Uri.tryParse(p.url)?.host ?? '';
                  final when = _formatPostWhen(p.createdUtc);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: InkWell(
                      onTap: () =>
                          _openUrlLogged(p.url, p.title), // <-- log then open
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('•  '),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.title,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                const SizedBox(height: 2),
                                Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 6,
                                  children: [
                                    GestureDetector(
                                      onTap: () => _openHostSearch(host),
                                      child: Text(
                                        host,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              decoration:
                                                  TextDecoration.underline,
                                            ),
                                      ),
                                    ),
                                    Text(
                                      '•  $when',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ],
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

                // See more
                if (_posts.isNotEmpty)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () async {
                        // Log that user opened the Social Trends page
                        await HistoryService.instance.logView(
                          type: 'page',
                          id: 'social_trends:${widget.symbol}',
                          title: 'Social Trends ${widget.symbol}',
                        );
                        if (!mounted) return;
                        Navigator.of(this.context).push(
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
        ),

        // Subtle loading overlay on refetch
        if (_loading && (_posts.isNotEmpty || _series.isNotEmpty))
          Positioned.fill(
            child: IgnorePointer(
              ignoring: true,
              child: ColoredBox(
                color: Colors.black12,
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),
          ),
      ],
    );
  }
}
