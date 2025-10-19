# backend/trending.py
import re
import math
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone

# simple stopword set (expand if needed)
STOPWORDS = {
    "the", "a", "an", "and", "or", "but", "of", "to", "in", "on", "for",
    "with", "at", "by", "from", "as", "is", "are", "was", "were", "be",
    "been", "it", "its", "this", "that", "these", "those", "has", "have",
    "will", "would", "can", "could", "should", "may", "might", "not",
    "no", "yes", "vs", "than"
}

TOKEN_RE = re.compile(r"[A-Za-z][A-Za-z\-']{1,}")

def tokenize(text: str):
    for m in TOKEN_RE.finditer(text.lower()):
        tok = m.group(0).strip("-'")
        if len(tok) < 3 or tok in STOPWORDS:
            continue
        yield tok

def extract_keywords(items):
    """
    items: list of dicts { 'text': str, 'ts': datetime }
    """
    per_day = defaultdict(Counter)
    global_counter = Counter()
    for obj in items:
        ts = obj.get("ts") or datetime.now(timezone.utc)
        day = ts.date().isoformat()
        text = obj.get("text") or ""
        kws = list(tokenize(text))
        per_day[day].update(kws)
        global_counter.update(kws)
    return per_day, global_counter

def decay_weight(days_ago, half_life_days=7.0):
    return 0.5 ** (days_ago / half_life_days)

def trend_scores(per_day, window_days=14):
    today = datetime.now(timezone.utc).date()
    scores = Counter()
    for i in range(window_days):
        day = (today - timedelta(days=i)).isoformat()
        w = decay_weight(i)
        for k, c in per_day.get(day, {}).items():
            scores[k] += w * c
    return scores

def top_keywords(items, window_days=14, limit=25):
    per_day, _ = extract_keywords(items)
    scores = trend_scores(per_day, window_days=window_days)
    top = scores.most_common(limit)
    today = datetime.now(timezone.utc).date()
    # build daily series (for optional mini-chart)
    series = {}
    for k, _ in top:
        arr = []
        for i in range(window_days - 1, -1, -1):
            day = (today - timedelta(days=i)).isoformat()
            arr.append(per_day.get(day, {}).get(k, 0))
        series[k] = arr
    return {
        "window_days": window_days,
        "top": [{"keyword": k, "score": round(s, 3)} for k, s in top],
        "series": series,
    }
