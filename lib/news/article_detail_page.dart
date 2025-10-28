// lib/news/article_detail_page.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../services/news_service.dart'; // For NewsItem class
import '../services/history_service.dart'; // <-- add logging

class ArticleDetailPage extends StatefulWidget {
  final NewsItem article; // NewsItem
  const ArticleDetailPage({super.key, required this.article});

  @override
  State<ArticleDetailPage> createState() => _ArticleDetailPageState();
}

class _ArticleDetailPageState extends State<ArticleDetailPage> {
  late final WebViewController _controller;
  double _progress = 0;

  @override
  void initState() {
    super.initState();

    // Log the article view as soon as the page opens
    HistoryService.instance.logView(
      type: 'article',
      id: widget.article.link,     // use URL for stable id
      title: widget.article.title,
    );

    // Correct WebView setup
    if (Platform.isAndroid) {
      WebViewPlatform.instance = AndroidWebViewPlatform();
    } else if (Platform.isIOS) {
      WebViewPlatform.instance = WebKitWebViewPlatform();
    }

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) => setState(() => _progress = p / 100.0),
        ),
      )
      ..loadRequest(Uri.parse(widget.article.link));
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.article;

    return Scaffold(
      appBar: AppBar(
        title: Text(a.source.isEmpty ? 'Article' : a.source),
        actions: [
          IconButton(
            tooltip: 'Open in browser',
            icon: const Icon(Icons.open_in_new),
            onPressed: () async {
              final uri = Uri.parse(a.link);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
          ),
          IconButton(
            tooltip: 'Share',
            icon: const Icon(Icons.share),
            onPressed: () => Share.share(a.link, subject: a.title),
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_progress < 1.0)
            LinearProgressIndicator(
              minHeight: 2,
              value: _progress,
              backgroundColor: Colors.transparent,
            ),
        ],
      ),
    );
  }
}
