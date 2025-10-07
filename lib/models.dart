// lib/models.dart
class LiveQuote {
  final double price;
  final double? changePct;
  LiveQuote({required this.price, this.changePct});
}

class StockSummary {
  final String symbol;
  final double price;
  final double changePct;
  final String sentiment;
  StockSummary({
    required this.symbol,
    required this.price,
    required this.changePct,
    required this.sentiment,
  });
}

// Movers used by the Markets page
class Mover {
  final String symbol;
  final double price;
  final double changePct;
  Mover({required this.symbol, required this.price, required this.changePct});
}

class TopMovers {
  final List<Mover> gainers;
  final List<Mover> losers;
  TopMovers({required this.gainers, required this.losers});
}
