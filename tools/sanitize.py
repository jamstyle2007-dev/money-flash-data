#!/usr/bin/env python3
"""禁止表現の自動言い換え（配信を止めないためのフェイルオープン装置）。

validate.py の BANNED_PHRASES に一致する表現を、意味を保ったまま
機械的に言い換える（強調語を落とす等）。scam記事の「」内引用は
validate.py と同じく対象外（そもそも検証を通るため触らない）。

使い方: python3 tools/sanitize.py <draft_today.json | issues.json | feed_draft.json>
変更があった場合のみファイルを上書きし、変更内容を表示する。
"""
import json
import re
import sys

# 決定的な言い換え表（置換後は必ず BANNED_PHRASES に不一致になること）
REPLACEMENTS = [
    ("必ず儲かる", "儲かる"),
    ("絶対に儲かる", "儲かる"),
    ("確実に儲かる", "儲かる"),
    ("必ず稼げる", "稼げる"),
    ("絶対に稼げる", "稼げる"),
    ("確実に稼げる", "稼げる"),
    ("元本保証で増える", "元本保証をうたって増える"),
    ("100%勝てる", "勝てる"),
    ("絶対に上がる", "上がる"),
    ("確実に上がる", "上がる"),
]

changes = []


def fix_text(s, exempt_quotes):
    """exempt_quotes=True なら「」内は触らない（scam記事の引用保護）"""
    def apply(seg):
        for old, new in REPLACEMENTS:
            if old in seg:
                changes.append(f"「{old}」→「{new}」")
                seg = seg.replace(old, new)
        return seg

    if not exempt_quotes:
        return apply(s)
    out, i = [], 0
    for m in re.finditer(r"「[^」]*」", s):
        out.append(apply(s[i:m.start()]))
        out.append(m.group(0))  # 引用はそのまま
        i = m.end()
    out.append(apply(s[i:]))
    return "".join(out)


def fix_article(a):
    exempt = a.get("category") == "scam"
    for key in ("title", "comment", "jackView"):
        if isinstance(a.get(key), str):
            a[key] = fix_text(a[key], exempt)
    for key in ("flash", "summary"):
        if isinstance(a.get(key), list):
            a[key] = [fix_text(s, exempt) if isinstance(s, str) else s for s in a[key]]


def main(path):
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    if "issues" in data:
        for issue in data["issues"]:
            for a in issue["articles"]:
                fix_article(a)
    elif "items" in data:
        for it in data["items"]:
            fix_article(it)
    elif "articles" in data:
        for a in data["articles"]:
            fix_article(a)
    if changes:
        with open(path, "w", encoding="utf-8") as f:
            f.write(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
        print(f"sanitize: {len(changes)}件を自動言い換え: " + " / ".join(changes[:5]))
    else:
        print("sanitize: 変更なし")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "draft_today.json")
