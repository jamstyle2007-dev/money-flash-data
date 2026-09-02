#!/usr/bin/env python3
"""公開済みの本日号から、X投稿文（コピペ用）を作って標準出力とファイルに書く。

秘密情報を持たない版。2台目のMac（待機機）でも使えるよう money-flash-data に置く。
本機の ~/money-flash/xpost/xpost.py と出力は同じ形式。

使い方: python3 tools/xdraft.py [出力ファイルパス]
終了コード: 0=作成 / 2=本日号がまだ無い(スキップ)
"""
import json, re, subprocess, sys, unicodedata
import urllib.request
from datetime import datetime, timezone, timedelta

LIVE = ("https://raw.githubusercontent.com/jamstyle2007-dev/"
        "money-flash-data/main/issues.json")
LP_URL = "https://jack-invest.com/lp/money-flash-lp.html"
JST = timezone(timedelta(hours=9))
MAX_WEIGHT, TITLE_MAX, URL_WEIGHT = 280, 24, 23


def today_issue():
    with urllib.request.urlopen(LIVE, timeout=30) as r:
        d = json.load(r)
    issues = d["issues"] if isinstance(d, dict) else d
    newest = max(issues, key=lambda i: i["date"])
    return newest if newest["date"] == datetime.now(JST).strftime("%Y-%m-%d") else None


def weighted_len(text):
    total = 0
    for line in text.split("\n"):
        if line.strip().startswith("http"):
            total += URL_WEIGHT
        else:
            total += sum(2 if unicodedata.east_asian_width(c) in ("W", "F", "A") else 1
                         for c in line)
    return total + text.count("\n")


def fallback(title):
    t = re.split(r"[。｡]", title)[0].replace("【警戒】", "")
    return t if len(t) <= TITLE_MAX else t[:TITLE_MAX - 1] + "…"


def shorten(titles):
    prompt = (
        "次の3本のニュース見出しを、それぞれ全角24文字以内に短縮してください。\n"
        "条件: 固有名詞と数字は残す/意味が通る自然な日本語/語の途中で切らない/"
        "記号【】は外す/半角ダブルクォート禁止。\n"
        '出力はJSON配列のみ: ["見出し1","見出し2","見出し3"]\n\n'
        + "\n".join(f"{i+1}. {t}" for i, t in enumerate(titles)))
    for claude in ("/opt/homebrew/bin/claude", "claude"):
        try:
            r = subprocess.run([claude, "-p", prompt], capture_output=True,
                               text=True, timeout=180)
            arr = json.loads(re.search(r"\[.*\]", r.stdout, re.S).group(0))
            assert len(arr) == 3 and all(isinstance(t, str) and '"' not in t for t in arr)
            return [t.strip() for t in arr]
        except Exception:
            continue
    return [fallback(t) for t in titles]


def compose(issue):
    short = shorten([a["title"] for a in issue["articles"]])
    marks = ["①", "②", "③"]
    def build(items):
        body = "\n".join(m + t for m, t in zip(marks, items))
        return (f"今朝のMoney Flash、注目の3本。\n\n{body}\n\n"
                f"全記事、私の解説付きで読めます（無料）\n{LP_URL}")
    text = build(short)
    while weighted_len(text) > MAX_WEIGHT:
        short = [s[:-2] + "…" if len(s) > 10 else s for s in short]
        text = build(short)
    return text


def main():
    issue = today_issue()
    if issue is None:
        print("今日の号がまだありません。スキップします。")
        sys.exit(2)
    text = compose(issue)
    print(f"--- 投稿文 (weight={weighted_len(text)}/{MAX_WEIGHT}) ---")
    print(text)
    if len(sys.argv) > 1:
        with open(sys.argv[1], "w") as f:
            f.write(text + "\n")
        print("written:", sys.argv[1])


if __name__ == "__main__":
    main()
