#!/usr/bin/env python3
"""draft_today.json のJSON構文チェック（--fix で既知パターンの自動修復も行う）。

使い方:
  python3 tools/checkdraft.py           # チェックのみ（NGなら exit 1）
  python3 tools/checkdraft.py --fix     # 値内の半角ダブルクォート等を修復してからチェック
"""
import json
import re
import sys
import os

PATH = os.path.join(os.path.dirname(__file__), "..", "draft_today.json")


def try_load():
    try:
        with open(PATH, encoding="utf-8") as f:
            json.load(f)
        return None
    except Exception as e:
        return str(e)


def fix():
    s = open(PATH, encoding="utf-8").read()

    # 値の中の半角ダブルクォートを「」に置換（"title": "..." / "comment": "..." / flash行）
    def fix_val(m):
        key, val = m.group(1), m.group(2)
        if '"' in val:
            val = re.sub(r'"([^"]*)"', r"「\1」", val)
        return f'"{key}": "{val}"'

    s = re.sub(r'"(title|comment)":\s*"(.*)"(?=,?\s*$)', fix_val, s, flags=re.M)

    # flash配列の行（"..." または "...",）内のネストしたクォート
    def fix_flash(m):
        val = m.group(1)
        inner = re.sub(r'"([^"]*)"', r"「\1」", val)
        return f'"{inner}"{m.group(2)}'

    s = re.sub(r'^\s*"(.+)"(,?)\s*$',
               lambda m: ("          " + fix_flash(m)) if '"' in m.group(1) else m.group(0),
               s, flags=re.M)

    open(PATH, "w", encoding="utf-8").write(s)


def main():
    if not os.path.exists(PATH):
        print("NG: draft_today.json がありません")
        sys.exit(1)
    err = try_load()
    if err and "--fix" in sys.argv:
        fix()
        err = try_load()
        if not err:
            print("OK: 自動修復して構文チェック通過")
            return
    if err:
        print(f"NG: JSON構文エラー: {err}")
        print("ヒント: 文字列の値の中に半角ダブルクォート(\")を書かない。引用は「」を使う")
        sys.exit(1)
    print("OK: JSON構文チェック通過")


if __name__ == "__main__":
    main()
