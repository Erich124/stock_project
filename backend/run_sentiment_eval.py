# backend/run_sentiment_eval.py
from sentiment import score_posts
import csv

def label(x):
    return 'Positive' if x >= 0.10 else ('Negative' if x <= -0.10 else 'Neutral')
texts = [
 "AAPL beats earnings and raises guidance",
 "Tesla delivers a record number of vehicles in Q3",
 "NVDA revenue soars; demand remains strong",
 "Microsoft announces dividend increase",
 "Amazon posts surprise profit this quarter",
 "Meta stock jumps after strong ad sales",
 "Apple unveils new chips with better margins",
 "AAPL cuts iPhone production on weak demand",
 "TSLA recalls vehicles over safety issue",
 "NVDA faces new export restrictions",
 "Fed hints at another rate hike",
 "Snap misses revenue expectations",
 "Intel warns of weak PC demand",
 "Lucid plans share offering to raise cash",
 "AAPL hosts its annual developer conference",
 "TSLA files 10-Q with the SEC",
 "Market opens mixed on Tuesday",
 "Company schedules earnings call for next week",
 "Analyst maintains hold rating on AAPL",
 "Apple product event announced for next week",
]
expected = [
 "Positive","Positive","Positive","Positive","Positive","Positive","Positive",
 "Negative","Negative","Negative","Negative","Negative","Negative","Negative",
 "Neutral","Neutral","Neutral","Neutral","Neutral","Neutral"
]

posts = [{"title": t, "selftext": ""} for t in texts]
scored = score_posts(posts)                          # uses your existing scorer
actual = [label(float(p.get("score", 0))) for p in scored]

# Print a simple table to console
print(f"{'#':>2} | {'Input':<55} | {'Expected':<8} | {'Actual':<8}")
print("-"*90)
for i, (t, e, a) in enumerate(zip(texts, expected, actual), 1):
    print(f"{i:>2} | {t[:55]:<55} | {e:<8} | {a:<8}")

# Save a CSV you can paste into your report
with open("sentiment_eval.csv", "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["#", "Input", "Expected Output", "Actual Output"])
    for i, (t, e, a) in enumerate(zip(texts, expected, actual), 1):
        w.writerow([i, t, e, a])

acc = sum(a==e for a, e in zip(actual, expected)) / len(expected)
print("\nAccuracy:", round(acc, 3))
