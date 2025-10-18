# backend/server.py
from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from typing import Dict, Any, List, Optional

# Absolute imports so we can run `uvicorn backend.server:app`
from backend.reddit_posts import fetch_posts
from backend.sentiment import score_posts, aggregate_daily, summarize
from backend.quotes import get_quote

import yfinance as yf

app = FastAPI(title="Stock Backend", version="0.5")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# ---- simple request logger (helps you see the exact URL the app calls)
@app.middleware("http")
async def log_requests(request: Request, call_next):
    print(f"[REQ] {request.method} {request.url.path}?{request.url.query}")
    resp = await call_next(request)
    print(f"[RESP] {resp.status_code} {request.url.path}")
    return resp

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
    s = summarize(series) or {}
    summary_text = s.get("label", "Neutral")
    return {"series": series, "summary": summary_text, "count": len(scored)}

# ---------------- Summary (price + sentiment) ----------------
def _make_summary_payload(ticker: str) -> Dict[str, Any]:
    tkr = (ticker or "").upper().strip()
    try:
        q = get_quote(tkr) or {}
    except Exception:
        q = {}

    posts = fetch_posts(tkr, days=14, limit=50)
    scored = score_posts(posts)
    series = aggregate_daily(scored)
    s = summarize(series) or {}
    summary_text = s.get("label", "Neutral")

    return {
        "symbol": tkr,
        "price": float(q.get("price") or 0.0),
        "changePct": float(q.get("changePct") or 0.0),
        "sentiment": summary_text,
    }

# Query-param style: accept either ?ticker=NVDA or ?symbol=NVDA
@app.get("/summary")
def summary(ticker: Optional[str] = None, symbol: Optional[str] = None) -> Dict[str, Any]:
    t = ticker or symbol
    if not t:
        raise HTTPException(status_code=400, detail="Provide ?ticker= or ?symbol=")
    return _make_summary_payload(t)

@app.get("/api/summary")
def api_summary(ticker: Optional[str] = None, symbol: Optional[str] = None) -> Dict[str, Any]:
    t = ticker or symbol
    if not t:
        raise HTTPException(status_code=400, detail="Provide ?ticker= or ?symbol=")
    return _make_summary_payload(t)

# Path-param aliases: /summary/NVDA and /api/summary/NVDA
@app.get("/summary/{ticker}")
def summary_path(ticker: str) -> Dict[str, Any]:
    return _make_summary_payload(ticker)

@app.get("/api/summary/{ticker}")
def api_summary_path(ticker: str) -> Dict[str, Any]:
    return _make_summary_payload(ticker)

# ---------------- Symbols (yfinance) ----------------
def _t(sym: str) -> yf.Ticker:
    return yf.Ticker((sym or "").upper().strip())

@app.get("/symbols/{symbol}/exists")
def symbol_exists(symbol: str) -> Dict[str, Any]:
    try:
        t = _t(symbol)
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
            "sentiment": "Neutral",
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
