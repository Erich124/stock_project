import os
from dotenv import load_dotenv
import praw

# Load credentials from .env
load_dotenv("backend/.env")

reddit = praw.Reddit(
    client_id=os.getenv("REDDIT_CLIENT_ID"),
    client_secret=os.getenv("REDDIT_CLIENT_SECRET"),
    user_agent=os.getenv("REDDIT_USER_AGENT"),
)

# Simple test: search for "AAPL" posts
print("Fetching posts for AAPL...")
for i, post in enumerate(reddit.subreddit("all").search("AAPL", sort="new", limit=5), start=1):
    print(f"{i}. {post.title[:100]} (score: {post.score})")

print("✅ Done! If you see post titles above, Reddit API is working.")

