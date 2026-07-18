#!/usr/bin/env python3
"""issues.json の検証。壊れたデータを配信しないための publish 前チェック。"""
import json
import re
import sys

REQUIRED_CATEGORIES = ["money", "sidehustle", "scam"]
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


def fail(msg):
    print(f"NG: {msg}")
    sys.exit(1)


def main(path):
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except Exception as e:
        fail(f"JSONとして読めません: {e}")

    issues = data.get("issues")
    if not isinstance(issues, list) or not issues:
        fail("issues が空です")

    seen_ids = set()
    seen_numbers = set()
    for issue in issues:
        iid = issue.get("id", "?")
        if not DATE_RE.match(issue.get("date", "")):
            fail(f"{iid}: date が YYYY-MM-DD ではありません")
        if issue.get("id") != issue.get("date"):
            fail(f"{iid}: id は date と一致させてください")
        if iid in seen_ids:
            fail(f"{iid}: id が重複しています")
        seen_ids.add(iid)
        num = issue.get("number")
        if not isinstance(num, int) or num < 1:
            fail(f"{iid}: number が不正です")
        if num in seen_numbers:
            fail(f"{iid}: number {num} が重複しています")
        seen_numbers.add(num)

        articles = issue.get("articles", [])
        if len(articles) != 3:
            fail(f"{iid}: 記事は3本必要です（現在{len(articles)}本）")
        cats = [a.get("category") for a in articles]
        if cats != REQUIRED_CATEGORIES:
            fail(f"{iid}: カテゴリ順は {REQUIRED_CATEGORIES} 固定です（現在{cats}）")
        for a in articles:
            aid = a.get("id", "?")
            if not a.get("title", "").strip():
                fail(f"{aid}: title が空です")
            if aid != f"{iid}-{a['category']}":
                fail(f"{aid}: 記事idは「{iid}-{a['category']}」形式にしてください")
            flash = a.get("flash", [])
            if not (2 <= len(flash) <= 4) or any(not s.strip() for s in flash):
                fail(f"{aid}: flash は2〜4行・空行なしにしてください")
            if len(a.get("comment", "").strip()) < 40:
                fail(f"{aid}: JACKの視点(comment)が短すぎます（40字以上）")
            sources = a.get("sources", [])
            if not sources:
                fail(f"{aid}: sources（一次情報リンク）が必要です")
            for s in sources:
                if not s.get("url", "").startswith("https://"):
                    fail(f"{aid}: source url が https ではありません: {s.get('url')}")
            if a["category"] == "scam":
                joined = a["comment"] + a["title"] + " ".join(flash)
                words = ["詐欺", "フィッシング", "手口", "悪質", "被害", "なりすまし"]
                if not any(w in joined for w in words):
                    fail(f"{aid}: scam記事の内容を確認してください（詐欺関連語が見当たりません）")

    dates = [i["date"] for i in issues]
    if dates != sorted(dates, reverse=True):
        fail("issues は日付の新しい順に並べてください")

    print(f"OK: {len(issues)}号・全{len(issues) * 3}記事の検証を通過")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "issues.json")
