from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
import yfinance as yf

app = FastAPI(title="Stocks API")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"], allow_credentials=True,
    allow_methods=["*"], allow_headers=["*"],
)

@app.get("/ping")
def ping():
    return {"ok": True}

def _t(sym: str):
    return yf.Ticker(sym.upper().strip())

@app.get("/symbols/{symbol}/exists")
def symbol_exists(symbol: str):
    try:
        t = _t(symbol)
        # quick check; some fields may be absent, so just ensure we get something
        return {"symbol": symbol.upper(), "exists": bool(t.fast_info)}
    except Exception:
        return {"symbol": symbol.upper(), "exists": False}

@app.get("/symbols/{symbol}/summary")
def summary(symbol: str):
    try:
        t = _t(symbol)
        fi = t.fast_info or {}
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
def history(symbol: str, period: str = "6mo", interval: str = "1d"):
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
