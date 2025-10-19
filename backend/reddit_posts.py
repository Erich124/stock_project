import os, datetime, langid
from dotenv import load_dotenv
import praw

load_dotenv()
_reddit = praw.Reddit(
    client_id=os.getenv("REDDIT_CLIENT_ID"),
    client_secret=os.getenv("REDDIT_CLIENT_SECRET"),
    user_agent=os.getenv("REDDIT_USER_AGENT", "stock-app"),
)
def _english(text):
    if not text: return False
    try: lang,_ = langid.classify(text); return lang == "en"
    except: return False

def fetch_posts(ticker: str, days: int = 14, limit: int = 50):
    end = datetime.datetime.utcnow()
    start = end - datetime.timedelta(days=days)
    s, e = int(start.timestamp()), int(end.timestamp())
    out = []
    for p in _reddit.subreddit("all").search(ticker, sort="new", limit=limit):
        if not (s <= int(p.created_utc) <= e): continue
        title = p.title or ""
        body = getattr(p, "selftext", "") or ""
        if not _english(title + " " + body): continue
        out.append({
            "title": title,
            "url": str(p.url),
            "score": int(p.score or 0),
            "comments": int(p.num_comments or 0),
            "upvote_ratio": float(p.upvote_ratio or 0),
            "content": body,
            "created_at": datetime.datetime.utcfromtimestamp(p.created_utc).isoformat() + "Z",
        })
    return out
