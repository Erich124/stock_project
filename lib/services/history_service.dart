// lib/services/history_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// HistoryService
/// - Writes under:
///     users/{uid}/recent_views/{docId}
///     users/{uid}/search_history/{docId}
/// - Each write includes:
///     uid: <owner uid>, ts: FieldValue.serverTimestamp()
///   (required by per-user Firestore security rules)
///
/// Public API:
///   - logRecentView(symbol: ..., where: ...)
///   - logSearch(query: ..., source: ..., symbolHint: ...)
///   - recentViewsStream(limit: ...)
///   - searchHistoryStream(limit: ...)
///   - clearRecentViews()
///   - clearSearchHistory()
class HistoryService {
  HistoryService._();
  static final HistoryService instance = HistoryService._();

  // ---- Tunables (caps to keep collections small) ----
  static const int maxRecentViews = 100;
  static const int maxSearches = 100;

  // ---- Collection names (must match your rules) ----
  static const String _collUsers = 'users';
  static const String _recentViews = 'recent_views';
  static const String _searchHistory = 'search_history';

  FirebaseFirestore get _db => FirebaseFirestore.instance;
  FirebaseAuth get _auth => FirebaseAuth.instance;

  /// Ensures there's a signed-in user; anonymous sign-in for dev/first run.
  Future<User> _ensureUser() async {
    final u = _auth.currentUser;
    if (u != null) return u;
    final cred = await _auth.signInAnonymously();
    return cred.user!;
  }

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      _db.collection(_collUsers).doc(uid);

  CollectionReference<Map<String, dynamic>> _subcol(String uid, String name) =>
      _userDoc(uid).collection(name);

  /// Generic add with server timestamp & pruning to `cap`.
  Future<void> _addItem({
    required String sub,
    required Map<String, dynamic> data,
    required int cap,
  }) async {
    final user = await _ensureUser();
    final col = _subcol(user.uid, sub);

    final payload = <String, dynamic>{
      'uid': user.uid,
      'ts': FieldValue.serverTimestamp(),
      ...data,
    };

    await col.add(payload);

    // Trim older docs beyond cap (ordered by ts desc)
    final snap = await col.orderBy('ts', descending: true).get();
    if (snap.docs.length > cap) {
      final batch = _db.batch();
      for (final d in snap.docs.skip(cap)) {
        batch.delete(d.reference);
      }
      await batch.commit();
    }
  }

  // --------------------------------------------------------------------------
  // WRITE APIs
  // --------------------------------------------------------------------------

  /// Log a *search* action.
  /// - [query]: user-entered text
  /// - [source]: optional origin (e.g., 'SearchBar', 'MarketsPage')
  /// - [symbolHint]: optional association (e.g., 'AAPL')
  Future<void> logSearch({
    required String query,
    String? source,
    String? symbolHint,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return;

    await _addItem(
      sub: _searchHistory,
      cap: maxSearches,
      data: {
        'type': 'search',
        'query': q,
        if (source != null) 'source': source,
        if (symbolHint != null) 'symbol_hint': symbolHint,
      },
    );
  }

  /// Log a *recent view* (ticker, article, page).
  /// - [symbol]: for tickers use the ticker (e.g., 'AAPL')
  /// - [where]: where this happened ('StockDetailsPage', 'ArticleDetailPage', etc.)
  Future<void> logRecentView({
    required String symbol,
    String? where,
  }) async {
    final s = symbol.trim();
    if (s.isEmpty) return;

    await _addItem(
      sub: _recentViews,
      cap: maxRecentViews,
      data: {
        'type': 'ticker_view',
        'symbol': s.toUpperCase(),
        if (where != null) 'where': where,
      },
    );
  }

  /// Compatibility shim for older code paths:
  /// Old usage: logView(type: 'ticker'|'article'|'page', id: 'AAPL', title: '...')
  Future<void> logView({
    required String type, // 'ticker' | 'article' | 'page'
    required String id,
    String? title,
    int keep = maxRecentViews, // ignored; cap uses maxRecentViews
  }) async {
    final s = id.trim();
    if (s.isEmpty) return;

    await _addItem(
      sub: _recentViews,
      cap: maxRecentViews,
      data: {
        'type': type,
        'symbol': s.toUpperCase(),
        if (title != null) 'title': title,
        'where': 'legacy:$type',
      },
    );
  }

  // --------------------------------------------------------------------------
  // READ APIs (streams)
  // --------------------------------------------------------------------------

  /// Stream of recent ticker views, newest first.
  Stream<QuerySnapshot<Map<String, dynamic>>> recentViewsStream({
    int limit = 50,
  }) async* {
    final user = await _ensureUser();
    yield* _subcol(user.uid, _recentViews)
        .orderBy('ts', descending: true)
        .limit(limit)
        .snapshots();
  }

  /// Stream of recent searches, newest first.
  Stream<QuerySnapshot<Map<String, dynamic>>> searchHistoryStream({
    int limit = 50,
  }) async* {
    final user = await _ensureUser();
    yield* _subcol(user.uid, _searchHistory)
        .orderBy('ts', descending: true)
        .limit(limit)
        .snapshots();
  }

  // --------------------------------------------------------------------------
  // CLEAR APIs
  // --------------------------------------------------------------------------

  Future<void> clearRecentViews() async {
    final user = await _ensureUser();
    final col = _subcol(user.uid, _recentViews);
    final snap = await col.get();
    if (snap.docs.isEmpty) return;
    final batch = _db.batch();
    for (final d in snap.docs) {
      batch.delete(d.reference);
    }
    await batch.commit();
  }

  Future<void> clearSearchHistory() async {
    final user = await _ensureUser();
    final col = _subcol(user.uid, _searchHistory);
    final snap = await col.get();
    if (snap.docs.isEmpty) return;
    final batch = _db.batch();
    for (final d in snap.docs) {
      batch.delete(d.reference);
    }
    await batch.commit();
  }
}
