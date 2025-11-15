# backend/reddit_posts.py
from __future__ import annotations

import os
import datetime as _dt
from typing import Any, Dict, List

# Optional deps: load .env if python-dotenv is present
try:
    from dotenv import load_dotenv # type: ignore
    from pathlib import Path
    # Always load the .env that sits next to this file, regardless of where Uvicorn is launched
    load_dotenv(dotenv_path=Path(__file__).resolve().parent / ".env", override=False)
except Exception:
    pass

# Make praw/langid optional so the server boots even if they're not installed
try:
    import praw  # type: ignore
except Exception:
    praw = None  # type: ignore

try:
    import langid  # type: ignore
except Exception:
    langid = None  # type: ignore


# ---------------------------
# Lazy PRAW client (dev-safe)
# ---------------------------
_reddit = None  # cache


def _build_reddit():
    """Return a configured PRAW client or None if disabled/misconfigured."""
    if os.getenv("DISABLE_REDDIT", "").lower() in ("1", "true", "yes"):
        return None
    if praw is None:
        return None

    cid = os.getenv("REDDIT_CLIENT_ID")
    secret = os.getenv("REDDIT_CLIENT_SECRET")
    ua = os.getenv("REDDIT_USER_AGENT", "stock_project_dev/0.1")

    if not cid or not secret:
        # Missing creds -> return None so callers can gracefully noop
        return None

    r = praw.Reddit(
        client_id=cid,
        client_secret=secret,
        user_agent=ua,
        check_for_async=False,
    )
    # Read-only mode is what we want
    try:
        r.read_only = True  # type: ignore[attr-defined]
    except Exception:
        pass
    return r


def _get_reddit():
    global _reddit
    if _reddit is None:
        _reddit = _build_reddit()
    return _reddit


# ---------------------------
# Helpers
# ---------------------------
def _is_english(text: str) -> bool:
    """Best-effort language check. Returns True if langid says 'en', else True if langid is unavailable."""
    if not text:
        return False
    if langid is None:
        return True  # don't block results in dev if langid isn't installed
    try:
        lang, _ = langid.classify(text)
        return lang == "en"
    except Exception:
        return True


# ---------------------------
# Public API
# ---------------------------
def fetch_posts(ticker: str, days: int = 14, limit: int = 50) -> List[Dict[str, Any]]:
    """
    Search Reddit for recent posts mentioning the ticker.
    - Boots and returns [] if Reddit is disabled or creds are missing.
    - Filters to the last `days` and English content when possible.
    """
    r = _get_reddit()
    if r is None:
        return []  # dev-friendly noop

    end = _dt.datetime.utcnow()
    start = end - _dt.timedelta(days=days)
    s, e = int(start.timestamp()), int(end.timestamp())

    out: List[Dict[str, Any]] = []

    # You can override the target subs via env: e.g. "stocks,investing,wallstreetbets"
    subs_env = os.getenv("REDDIT_SUBS", "all")
    subreddits = [s.strip() for s in subs_env.split(",") if s.strip()] or ["all"]

    # Split the limit across subs (roughly)
    per_sub = max(1, limit // max(1, len(subreddits)))

    query = ticker.strip()
    for sub in subreddits:
        try:
            for p in r.subreddit(sub).search(query, sort="new", limit=per_sub):
                try:
                    created = int(getattr(p, "created_utc", 0) or 0)
                    if not (s <= created <= e):
                        continue

                    title = getattr(p, "title", "") or ""
                    body = getattr(p, "selftext", "") or ""
                    if not _is_english(f"{title} {body}"):
                        continue

                    out.append(
                        {
                            "title": title,
                            "url": str(getattr(p, "url", "")),
                            "score": int(getattr(p, "score", 0) or 0),
                            "comments": int(getattr(p, "num_comments", 0) or 0),
                            "upvote_ratio": float(getattr(p, "upvote_ratio", 0) or 0.0),
                            "content": body,
                            "created_at": _dt.datetime.utcfromtimestamp(created).isoformat() + "Z",
                            "subreddit": sub,
                            "id": getattr(p, "id", ""),
                        }
                    )
                except Exception:
                    # Never let a single bad post break the response
                    continue
        except Exception:
            # Network/API hiccup on a sub shouldn't fail the whole endpoint
            continue

    return out
