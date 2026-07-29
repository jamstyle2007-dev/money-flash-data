#!/usr/bin/env python3
"""draft_today.json の鮮度チェック（検出器）。

古いニュースを「新着」として配信しないための検査。配信を止める用途では使わない——
run_morning.sh は試行1でNGなら再生成し、試行2では警告のみで配信を続行する
（毎日配信の信用が第一・フェイルオープン方針）。

チェック内容:
  1. 各記事に sourceDate（一次ソースの発行日）があり、カテゴリ別の許容日数以内か
     - money / sidehustle: 2日以内（月曜は週末をまたぐため+2日）
     - scam: 7日以内（公的な注意喚起は発表間隔が長いため）
  2. sources 先頭（一次ソース）のURLに古い日付コードが埋まっていないか
     （例: news/260601 → 2026-06-01、/241218/ → 2024-12-18）
  3. 例外: effectiveDate（施行日）が今日か明日の制度変更ネタは 1,2 を免除

使い方:
  python3 tools/checkfresh.py            # draft_today.json を検査（NGなら exit 1）
  python3 tools/checkfresh.py path.json  # 任意ファイルを検査
"""
import json
import os
import re
import sys
from datetime import date, timedelta

DEFAULT_PATH = os.path.join(os.path.dirname(__file__), "..", "draft_today.json")
MAX_AGE_DAYS = {"money": 2, "sidehustle": 2, "scam": 7}

# URL内の日付コード。誤検出を避けるため前後に数字が続く並びは対象外にする
URL_DATE_PATTERNS = [
    # 20260601 / 2026-06-01 / 2026/06/01
    re.compile(r"(?<![0-9])(20[2-9][0-9])[/\-.]?(0[1-9]|1[0-2])[/\-.]?(0[1-9]|[12][0-9]|3[01])(?![0-9])"),
    # 260601（yymmdd・2024〜2029年のみ）
    re.compile(r"(?<![0-9])(2[4-9])(0[1-9]|1[0-2])(0[1-9]|[12][0-9]|3[01])(?![0-9])"),
]


def parse_ymd(s):
    try:
        y, m, d = s.split("-")
        return date(int(y), int(m), int(d))
    except Exception:
        return None


def url_dates(url, today):
    """URLから読み取れる日付コード（未来日は無視）"""
    found = []
    for pat in URL_DATE_PATTERNS:
        for m in pat.finditer(url):
            y = int(m.group(1))
            if y < 100:
                y += 2000
            try:
                d = date(y, int(m.group(2)), int(m.group(3)))
            except ValueError:
                continue
            if d <= today:
                found.append(d)
    return found


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_PATH
    if not os.path.exists(path):
        print(f"NG: {path} がありません")
        sys.exit(1)
    try:
        with open(path, encoding="utf-8") as f:
            draft = json.load(f)
    except Exception as e:
        print(f"NG: JSONとして読めません: {e}")
        sys.exit(1)

    today = date.today()
    monday_extra = 2 if today.weekday() == 0 else 0
    errors = []
    warnings = []

    for a in draft.get("articles", []):
        cat = a.get("category", "?")
        title = a.get("title", "?")[:25]
        limit = MAX_AGE_DAYS.get(cat, 2) + monday_extra

        # 例外: 施行・開始・締切が今日か明日の制度変更ネタは鮮度チェック免除
        eff = parse_ymd(a.get("effectiveDate", ""))
        if eff and today <= eff <= today + timedelta(days=1):
            continue

        sd = parse_ymd(a.get("sourceDate", ""))
        if sd is None:
            errors.append(
                f"{cat}「{title}…」: sourceDate（一次ソースの発行日 YYYY-MM-DD）がありません。"
                f"ソースページを開いて発行日を確認し、記事に追加すること"
            )
        elif sd > today:
            errors.append(f"{cat}「{title}…」: sourceDate {sd} が未来の日付です")
        elif (today - sd).days > limit:
            errors.append(
                f"{cat}「{title}…」: 一次ソースが{(today - sd).days}日前（{sd}）で古すぎます。"
                f"{cat}枠は{limit}日以内の新着だけ採用すること。新しいネタに差し替える"
            )

        # URL日付コードの検査（一次ソース=先頭はNG、2本目以降の古い参考リンクは警告のみ）
        for idx, s in enumerate(a.get("sources", [])):
            url = s.get("url", "")
            dates = url_dates(url, today)
            if not dates:
                continue
            newest = max(dates)
            if (today - newest).days > limit:
                msg = (
                    f"{cat}「{title}…」: source{idx + 1} のURLに古い日付コード"
                    f"（{newest}とみられる）: {url}"
                )
                if idx == 0:
                    errors.append(msg + " → 一次ソースは新着に差し替えること")
                else:
                    warnings.append(msg + "（参考リンクのため警告のみ）")

    for w in warnings:
        print(f"警告: {w}")
    if errors:
        for e in errors:
            print(f"NG: {e}")
        sys.exit(1)
    print(f"OK: 鮮度チェック通過（{len(draft.get('articles', []))}記事）")


if __name__ == "__main__":
    main()
