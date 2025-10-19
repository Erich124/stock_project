from typing import Dict, Any
import yfinance as yf

def get_quote(symbol: str) -> Dict[str, Any]:
    t = yf.Ticker(symbol)
    df = t.history(period="2d")  # last two closes
    if df.empty:
        return {"symbol": symbol, "price": None, "changePct": None}
    price = float(df["Close"].iloc[-1])
    prev = float(df["Close"].iloc[-2]) if len(df) >= 2 else price
    change_pct = 0.0 if prev == 0 else (price - prev) / prev * 100.0
    return {"symbol": symbol, "price": price, "changePct": change_pct}
