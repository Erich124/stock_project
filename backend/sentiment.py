# backend/sentiment.py
from __future__ import annotations
from math import log
from datetime import datetime
from typing import Any, Dict, List
from collections import defaultdict

# ------------------------------------------------------
# Sentiment analyzer setup (works locally & on Render)
# ------------------------------------------------------
# Try NLTK VADER and auto-download the lexicon.
# If anything about NLTK fails, fall back to vaderSentiment (if installed).
try:
    import nltk  # type: ignore
    from nltk.sentiment import SentimentIntensityAnalyzer as _NLTK_SIA

    def _build_sia() -> _NLTK_SIA:
        # Ensure the VADER lexicon exists; download once if missing.
        try:
            nltk.data.find("sentiment/vader_lexicon.zip")
        except LookupError:
            nltk.download("vader_lexicon", quiet=True)
        return _NLTK_SIA()

    _sia = _build_sia()
except Exception:
    # Fallback: use standalone vaderSentiment analyzer if NLTK is unavailable
    try:
        from vaderSentiment.vaderSentiment import SentimentIntensityAnalyzer as _VS_SIA  # type: ignore
    except Exception:
        raise RuntimeError(
            "No VADER sentiment analyzer available. Install nltk or vaderSentiment."
        )
    _sia = _VS_SIA()

# ------------------------------------------------------
# Finance tweaks + helpers
# ------------------------------------------------------

# Light domain adaptation for finance headlines
_FIN_CUES = {
    "beats": 0.6, "record": 0.5, "soars": 0.8, "surge": 0.6, "jumps": 0.5,
    "raises guidance": 0.7, "dividend increase": 0.4, "profit": 0.4,
    "better margins": 0.4, "upgrade": 0.5,

    "cuts production": -0.6, "recalls": -0.7, "export restrictions": -0.6,
    "rate hike": -0.3, "misses": -0.6, "weak demand": -0.5,
    "share offering": -0.4, "downgrade": -0.6,
}

def _finance_boost(text: str) -> float:
    t = text.lower()
    return sum(w for k, w in _FIN_CUES.items() if k in t)

def _to_day(any_ts: Any) -> str:
    """
    Accepts seconds, milliseconds, or ISO-ish strings.
    Returns YYYY-MM-DD (local date is fine for daily buckets).
    """
    if any_ts is None:
        return "1970-01-01"
    # Numeric epochs (string or int)
    try:
        s = str(any_ts).strip()
        if s.isdigit():
            n = int(s)
            if n > 2_000_000_000_000:  # ms
                dt = datetime.fromtimestamp(n / 1000.0)
            elif n > 2_000_000_000:    # guard against weird large secs
                dt = datetime.fromtimestamp(n / 1000.0)
            else:                      # sec
                dt = datetime.fromtimestamp(n)
            return dt.date().isoformat()
    except Exception:
        pass
    # ISO / RFC-ish strings
    try:
        # Handle '2025-11-08T12:34:56Z' or '2025-11-08 12:34:56'
        s = str(any_ts).replace("Z", "+00:00")
        # fromisoformat handles '+00:00'; if it fails, fallback to split
        try:
            dt = datetime.fromisoformat(s)
        except Exception:
            dt = datetime.fromisoformat(s.split(".")[0])  # drop fractional seconds
        return dt.date().isoformat()
    except Exception:
        return "1970-01-01"

def _extract_text(p: Dict[str, Any]) -> str:
    title = p.get("title") or ""
    body = p.get("selftext") or p.get("content") or ""
    return f"{title} {body}".strip()

def _engagement_weight(p: Dict[str, Any]) -> float:
    """
    Log-weight by post score/upvotes and comments if available.
    """
    points = float(p.get("score") or p.get("ups") or 0)
    comments = float(p.get("comments") or p.get("num_comments") or 0)
    w = log(1.0 + max(0.0, points)) + log(1.0 + max(0.0, comments))
    return max(w, 1e-6)

def score_posts(posts: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """
    Returns each input post augmented with:
      - score: float in [-1, 1] (VADER compound + small finance boost)
      - sentiment: alias of score (for backward compatibility)
      - weight: engagement-based weight for aggregation
    """
    out: List[Dict[str, Any]] = []
    for p in posts:
        text = _extract_text(p)
        base = _sia.polarity_scores(text)["compound"]
        boosted = base + 0.40 * _finance_boost(text)
        # clamp to [-1, 1]
        comp = max(-1.0, min(1.0, boosted))
        w = _engagement_weight(p)
        out.append({**p, "score": comp, "sentiment": comp, "weight": w})
    return out

def aggregate_daily(scored: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """
    Weighted daily average -> list of dicts:
      { "date": "YYYY-MM-DD", "score": float , "value": float (alias) }
    Accepts created_at / created_utc / created / timestamp keys.
    """
    buckets: Dict[str, Dict[str, float]] = defaultdict(lambda: {"num": 0.0, "den": 0.0})
    for p in scored:
        raw_ts = p.get("created_at") or p.get("created_utc") or p.get("created") or p.get("timestamp")
        day = _to_day(raw_ts)
        w = float(p.get("weight") or 1.0)
        s = float(p.get("score") or p.get("sentiment") or 0.0)
        buckets[day]["num"] += s * max(w, 1e-6)
        buckets[day]["den"] += max(w, 1e-6)

    series = []
    for day in sorted(buckets.keys()):
        den = buckets[day]["den"] or 1e-6
        val = buckets[day]["num"] / den
        series.append({"date": day, "score": val, "value": val})  # provide both keys
    return series

def summarize(series: List[Dict[str, Any]]) -> str:
    """
    Returns a plain string label: "Positive", "Neutral", or "Negative".
    Thresholds tuned slightly wider to reduce false positives/negatives.
    """
    if not series:
        return "Neutral"
    avg = sum(float(pt.get("score") or pt.get("value") or 0.0) for pt in series) / len(series)
    if avg >= 0.10:
        return "Positive"
    if avg <= -0.10:
        return "Negative"
    return "Neutral"
