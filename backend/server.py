# backend/server.py
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from typing import Dict, Any, List

# Use RELATIVE imports inside the backend package
from .reddit_posts import fetch_posts
from .sentiment import score_posts, aggregate_daily, summarize
from .quotes import get_quote

import yfinance as yf


app = FastAPI(title="Stock Backend", version="0.3")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# ---------------- Health / Meta ----------------
@app.get("/health")
def health() -> Dict[str, bool]:
    return {"ok": True}

@app.get("/ping")
def ping() -> Dict[str, bool]:
    return {"ok": True}


# ---------------- Reddit & Sentiment ----------------
@app.get("/reddit")
def reddit(ticker: str, days: int = 14, limit: int = 50) -> List[Dict[str, Any]]:
    return fetch_posts(ticker, days=days, limit=limit)

@app.get("/sentiment")
def sentiment(ticker: str, days: int = 14, limit: int = 50) -> Dict[str, Any]:
    posts = fetch_posts(ticker, days=days, limit=limit)
    scored = score_posts(posts)
    series = aggregate_daily(scored)
    s = summarize(series)  # {"avg": ..., "label": ...}
    return {"series": series, "summary": s, "count": len(scored)}


# ---------------- Summary (price + sentiment) ----------------
def _make_summary_payload(ticker: str) -> Dict[str, Any]:
    # quotes.get_quote should return {"symbol","price","changePct"}; add safe fallbacks
    try:
        q = get_quote(ticker) or {}
    except Exception:
        q = {}

    posts = fetch_posts(ticker, days=14, limit=50)
    scored = score_posts(posts)
    series = aggregate_daily(scored)
    s = summarize(series) or {}

    return {
        "symbol": (ticker or "").upper(),
        "price": float(q.get("price") or 0.0),
        "changePct": float(q.get("changePct") or 0.0),
        "sentiment": s.get("label", "Neutral"),
    }

@app.get("/summary")
def summary(ticker: str) -> Dict[str, Any]:
    return _make_summary_payload(ticker)

# Mirror path some clients use
@app.get("/api/summary")
def api_summary(ticker: str) -> Dict[str, Any]:
    return _make_summary_payload(ticker)


# ---------------- Symbols (yfinance) ----------------
def _t(sym: str) -> yf.Ticker:
    return yf.Ticker((sym or "").upper().strip())

@app.get("/symbols/{symbol}/exists")
def symbol_exists(symbol: str) -> Dict[str, Any]:
    try:
        t = _t(symbol)
        # fast_info can be {}, treat empty as nonexistent
        exists = bool(getattr(t, "fast_info", {}) or {})
        return {"symbol": symbol.upper(), "exists": exists}
    except Exception:
        return {"symbol": symbol.upper(), "exists": False}

@app.get("/symbols/{symbol}/summary")
def symbol_summary(symbol: str) -> Dict[str, Any]:
    try:
        t = _t(symbol)
        fi = getattr(t, "fast_info", {}) or {}
        try:
            info = t.info
        except Exception:
            info = {}

        return {
            "symbol": symbol.upper(),
            "price": float(fi.get("last_price") or fi.get("regular_market_price") or 0.0),
            "changePct": float(fi.get("regular_market_change_percent") or 0.0),
            "sector": info.get("sector"),
            "pe": info.get("trailingPE"),
            "beta": info.get("beta"),
            "sentiment": "Neutral",  # wire to summarize(series) later if you want
        }
    except Exception as e:
        raise HTTPException(status_code=404, detail=f"Failed: {e}")

@app.get("/symbols/{symbol}/history")
def history(symbol: str, period: str = "6mo", interval: str = "1d") -> Dict[str, Any]:
    try:
        t = _t(symbol)
        df = t.history(period=period, interval=interval, auto_adjust=False)
        if df is None or df.empty:
            raise HTTPException(status_code=404, detail="No history")

        bars = [{
            "ts": idx.isoformat(),
            "open": float(row["Open"]),
            "high": float(row["High"]),
            "low": float(row["Low"]),
            "close": float(row["Close"]),
            "volume": int(row["Volume"]),
        } for idx, row in df.iterrows()]

        return {"symbol": symbol.upper(), "period": period, "interval": interval, "bars": bars}
    except Exception as e:
        raise HTTPException(status_code=404, detail=f"History error: {e}")
