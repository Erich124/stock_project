from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from backend.reddit_posts import fetch_posts
from backend.sentiment import score_posts, aggregate_daily, summarize
from backend.quotes import get_quote

app = FastAPI(title="Stock Backend", version="0.1")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"], allow_methods=["*"], allow_headers=["*"]
)

@app.get("/health")
def health():
    return {"ok": True}

@app.get("/reddit")
def reddit(ticker: str, days: int = 14, limit: int = 50):
    return fetch_posts(ticker, days=days, limit=limit)

@app.get("/sentiment")
def sentiment(ticker: str, days: int = 14, limit: int = 50):
    posts = fetch_posts(ticker, days=days, limit=limit)
    scored = score_posts(posts)
    series = aggregate_daily(scored)
    summary = summarize(series)
    return {"series": series, "summary": summary, "count": len(scored)}

# ---- SUMMARY (for your Home page) ----
def _make_summary_payload(ticker: str):
    q = get_quote(ticker)  # {symbol, price, changePct}
    posts = fetch_posts(ticker, days=14, limit=50)
    scored = score_posts(posts)
    series = aggregate_daily(scored)
    s = summarize(series)  # {"avg": ... , "label": ...}
    return {
        "symbol": ticker,
        "price": q.get("price"),
        "changePct": q.get("changePct"),
        "sentiment": s["label"],
    }

@app.get("/summary")
def summary(ticker: str):
    return _make_summary_payload(ticker)

# Some clients call /api/summary — mirror it so we never 404
@app.get("/api/summary")
def api_summary(ticker: str):
    return _make_summary_payload(ticker)
