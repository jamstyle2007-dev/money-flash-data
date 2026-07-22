#!/usr/bin/env python3
"""feed.json / issues.json の各記事に Pexels 画像URLを自動付与する。

- 画像が未設定（"image" キー無し）の item / article にのみ付与（冪等）
- カテゴリごとの検索キーワードプールから順繰りに選び、同じ画像の重複を避ける
- 生成AIではなくスクリプト側で決定的に実行（run_feed.sh / run_morning.sh の検証後に呼ぶ）

使い方: python3 tools/add_images.py feed.json issues.json
"""
import json
import sys
import os
import urllib.request
import urllib.parse

KEY_PATH = "/Users/jamstyle01/united-c-blog/.pexels_key"

# カテゴリ→検索キーワード（英語・エディトリアルに寄せた語彙）
KEYWORDS = {
    "market": ["stock market chart screen", "tokyo skyline business district", "financial newspaper coffee"],
    "jpstock": ["tokyo stock exchange building", "japanese business skyline", "candlestick chart monitor"],
    "usstock": ["wall street new york", "stock trading floor screens", "manhattan skyline dusk"],
    "fx": ["currency exchange money yen dollar", "world map finance network", "bank notes closeup"],
    "crypto": ["bitcoin coin dark", "cryptocurrency digital abstract", "blockchain technology light"],
    "seido": ["japanese government building", "tax documents calculator desk", "official paperwork stamp"],
    "point": ["credit cards wallet closeup", "cashless payment smartphone", "shopping points card"],
    "sidehustle": ["laptop cafe work freelance", "home office desk creative", "smartphone side business"],
    "scam": ["warning sign red dark", "hooded person smartphone dark", "phishing security lock"],
    "money": ["yen bills savings jar", "piggy bank desk light", "personal finance notebook"],
}


def pexels_search(key, query, page=1):
    url = "https://api.pexels.com/v1/search?" + urllib.parse.urlencode(
        {"query": query, "per_page": 15, "page": page, "orientation": "landscape"})
    req = urllib.request.Request(url, headers={"Authorization": key, "User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.loads(r.read()).get("photos", [])


def pick_image(key, category, used, salt):
    pool = KEYWORDS.get(category, KEYWORDS["market"])
    query = pool[salt % len(pool)]
    try:
        photos = pexels_search(key, query, page=1 + salt % 2)
    except Exception as e:
        print(f"  pexels error ({query}): {e}")
        return None
    for p in photos:
        u = p["src"].get("large")  # 940px幅・軽量
        if u and u not in used:
            used.add(u)
            return u
    return None


def process(path, key, used):
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    changed = 0
    if "items" in data:
        targets = [(it, it["category"]) for it in data["items"]]
    else:
        targets = [(a, a["category"]) for issue in data["issues"] for a in issue["articles"]]
    for i, (obj, cat) in enumerate(targets):
        if obj.get("image"):
            used.add(obj["image"])
            continue
        img = pick_image(key, cat, used, salt=i)
        if img:
            obj["image"] = img
            changed += 1
    if changed:
        with open(path, "w", encoding="utf-8") as f:
            f.write(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
    print(f"{os.path.basename(path)}: {changed}件に画像を付与")
    return changed


def main():
    key = open(KEY_PATH).read().strip()
    used = set()
    total = 0
    for path in sys.argv[1:] or ["feed.json", "issues.json"]:
        if os.path.exists(path):
            total += process(path, key, used)
    print(f"合計 {total}件")


if __name__ == "__main__":
    main()
