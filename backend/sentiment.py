from nltk.sentiment import SentimentIntensityAnalyzer
from collections import defaultdict
from math import log

_sia = SentimentIntensityAnalyzer()

def score_posts(posts):
    scored = []
    for p in posts:
        text = f"{p.get('title','')} {p.get('content','')}"
        s = _sia.polarity_scores(text)["compound"]  # [-1,1]
        w = log(1 + p.get("score",0)) + log(1 + p.get("comments",0))
        scored.append({**p, "sentiment": s, "weight": w})
    return scored

def aggregate_daily(scored):
    buckets = defaultdict(lambda: {"num":0.0,"den":0.0})
    for p in scored:
        day = p["created_at"][:10]
        w = max(1e-6, p["weight"])
        buckets[day]["num"] += p["sentiment"] * w
        buckets[day]["den"] += w
    series = [{"date": d, "value": v["num"]/v["den"]} for d,v in sorted(buckets.items())]
    return series

def summarize(series):
    if not series: return {"avg":0.0,"label":"Neutral"}
    avg = sum(pt["value"] for pt in series)/len(series)
    label = "Positive" if avg > 0.1 else "Negative" if avg < -0.1 else "Neutral"
    return {"avg": avg, "label": label}
