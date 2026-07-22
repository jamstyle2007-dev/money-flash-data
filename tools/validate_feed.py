#!/usr/bin/env python3
"""feed.json の検証。壊れたフィードを配信しないための publish 前チェック。"""
import json
import re
import sys

CATEGORIES = ["market", "jpstock", "usstock", "fx", "crypto", "seido", "point", "sidehustle", "scam"]
TIME_RE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$")
MARKET_SYMBOLS = ["N225", "TOPIX", "USDJPY", "SPX", "BTC"]

# jackLink（JACKサービスへの導線）の許可URL。この接頭辞以外は配信しない
JACKLINK_ALLOWED = [
    "https://jack-invest.com/learning/",
    "https://jack-invest.com/lp/jack-ios-apps.html",
    "https://jack-invest.com/lp/lp_china_import.html",
    "https://jack-invest.com/core-member",
    "https://jack-invest.com/books",
    "https://jack-money-lab.com",
    "https://note.com/jackinvest",
]

# 導線の上限（しつこさ防止）：feed全体でjackLink付きitemは6件まで
JACKLINK_MAX_TOTAL = 6

BANNED_PHRASES = [
    "必ず儲かる", "絶対に儲かる", "確実に儲かる", "必ず稼げる", "絶対に稼げる",
    "確実に稼げる", "元本保証で増える", "100%勝てる", "絶対に上がる", "確実に上がる",
    "買うべきです", "売るべきです", "今すぐ買", "推奨銘柄",
]


def fail(msg):
    print(f"NG: {msg}")
    sys.exit(1)


def main(path):
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except Exception as e:
        fail(f"JSONとして読めません: {e}")

    if not TIME_RE.match(data.get("updated", "")):
        fail("updated が YYYY-MM-DDTHH:MM ではありません")

    market = data.get("market", [])
    syms = [m.get("symbol") for m in market]
    if syms != MARKET_SYMBOLS:
        fail(f"market は {MARKET_SYMBOLS} の順で5件必要です（現在{syms}）")
    for m in market:
        for key in ["name", "value", "change", "changePct"]:
            if key not in m or m[key] in ("", None):
                fail(f"market {m.get('symbol')}: {key} がありません")

    items = data.get("items", [])
    if not (10 <= len(items) <= 60):
        fail(f"items は10〜60件にしてください（現在{len(items)}件）")
    seen = set()
    for it in items:
        iid = it.get("id", "?")
        if iid in seen:
            fail(f"{iid}: id 重複")
        seen.add(iid)
        if not TIME_RE.match(it.get("time", "")):
            fail(f"{iid}: time が YYYY-MM-DDTHH:MM ではありません")
        if it.get("category") not in CATEGORIES:
            fail(f"{iid}: category 不正 {it.get('category')}")
        if not it.get("title", "").strip():
            fail(f"{iid}: title が空です")
        summary = it.get("summary", [])
        if not (2 <= len(summary) <= 4) or any(not s.strip() for s in summary):
            fail(f"{iid}: summary は2〜4行・空行なし")
        if not it.get("sources"):
            fail(f"{iid}: sources 必須")
        for s in it["sources"]:
            if not s.get("url", "").startswith("https://"):
                fail(f"{iid}: source url がhttpsではない")
        jv = it.get("jackView", "")
        if not isinstance(jv, str) or not (20 <= len(jv.strip()) <= 160):
            fail(f"{iid}: jackView は20〜160字で必須です（現在{len(jv.strip()) if isinstance(jv, str) else '型不正'}）")
        if "――" in jv:
            fail(f"{iid}: jackView にダッシュ――は使わない")
        jl = it.get("jackLink")
        if jl is not None:
            if not jl.get("title", "").strip():
                fail(f"{iid}: jackLink.title が空")
            if not any(jl.get("url", "").startswith(p) for p in JACKLINK_ALLOWED):
                fail(f"{iid}: jackLink.url が許可リスト外です（{jl.get('url')}）")
        text = it["title"] + " ".join(summary) + jv
        for ng in BANNED_PHRASES:
            if ng in text:
                fail(f"{iid}: 禁止表現「{ng}」")

    times = [i["time"] for i in items]
    if times != sorted(times, reverse=True):
        fail("items は時刻の新しい順に並べてください")

    n_links = sum(1 for i in items if i.get("jackLink"))
    if n_links > JACKLINK_MAX_TOTAL:
        fail(f"jackLink付きitemが多すぎます（{n_links}件 > 上限{JACKLINK_MAX_TOTAL}件）。しつこい宣伝はNG")

    print(f"OK: market 5指標・items {len(items)}件の検証を通過")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "feed.json")
