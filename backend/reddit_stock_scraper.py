import os, json, datetime, time
from typing import List, Dict
from dotenv import load_dotenv
import praw, langid

load_dotenv("backend/.env")

reddit = praw.Reddit(
    client_id=os.getenv("REDDIT_CLIENT_ID"),
    client_secret=os.getenv("REDDIT_CLIENT_SECRET"),
    user_agent=os.getenv("REDDIT_USER_AGENT"),
)

END = datetime.datetime.utcnow()
START = END - datetime.timedelta(days=14)
START_TS, END_TS = int(START.timestamp()), int(END.timestamp())

TICKERS = [
    'AAPL','MSFT','GOOGL','AMZN','TSLA','META','NVDA','JPM','BAC','WFC',
    'GS','MS','AXP','XOM','CVX','BP','COP','JNJ','PFE','MRK','UNH',
    'ABBV','PG','KO','PEP','WMT','COST','TGT','HD','LOW','ETSY','DIS',
    'NFLX','SONY','GM','F','RIVN','LCID','DAL','AAL','UAL','MAR','HLT','COIN'
]

def collect_for(ticker: str, limit_per=50) -> List[Dict]:
    out: List[Dict] = []
    sr = reddit.subreddit("all")  # you can narrow later: "stocks+investing+wallstreetbets"
    for post in sr.search(ticker, sort="new", limit=limit_per):
        ts = int(post.created_utc)
        if not (START_TS <= ts <= END_TS):  # date filter
            continue
        title = post.title or ""
        body  = post.selftext or ""
        text  = f"{title} {body}".strip()
        try:
            lang, _ = langid.classify(text or title)
            if lang != "en":
                continue
        except Exception:
            continue
        out.append({
            "ticker": ticker,
            "title": title,
            "score": int(post.score or 0),
            "comments": int(post.num_comments or 0),
            "url": post.url,
            "permalink": f"https://www.reddit.com{getattr(post,'permalink','')}",
            "upvote_ratio": float(getattr(post,'upvote_ratio',0.0) or 0.0),
            "content": body,
            "created_utc": ts,
            "created_at": datetime.datetime.utcfromtimestamp(ts).isoformat()+"Z",
            "subreddit": str(getattr(post,'subreddit','')),
        })
    return out

def main():
    all_rows: List[Dict] = []
    for i, t in enumerate(TICKERS, 1):
        print(f"[{i}/{len(TICKERS)}] {t}")
        all_rows.extend(collect_for(t))
        time.sleep(0.8)  # respect rate limits a bit

    os.makedirs("backend/out", exist_ok=True)
    out_path = "backend/out/reddit_posts.json"
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(all_rows, f, ensure_ascii=False, indent=2)
    print(f"Saved {len(all_rows)} posts -> {out_path}")

if __name__ == "__main__":
    main()
