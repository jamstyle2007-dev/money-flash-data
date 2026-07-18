#!/usr/bin/env python3
"""下書き号（1号分のJSON）を issues.json の先頭に追加する。

使い方:
  python3 tools/add_issue.py draft.json          # 追加（numberは自動採番）
  python3 tools/add_issue.py draft.json --dry    # 検証のみ

draft.json は {"date": "YYYY-MM-DD", "articles": [...3本...]} 形式。
id/number/記事id は自動で振る。追加後に validate.py で全体検証する。
"""
import json
import subprocess
import sys
import os

os.chdir(os.path.join(os.path.dirname(__file__), ".."))


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    draft_path = sys.argv[1]
    dry = "--dry" in sys.argv

    with open(draft_path, encoding="utf-8") as f:
        draft = json.load(f)
    with open("issues.json", encoding="utf-8") as f:
        data = json.load(f)

    date = draft["date"]
    if any(i["date"] == date for i in data["issues"]):
        print(f"NG: {date} の号は既に存在します")
        sys.exit(1)

    issue = {
        "id": date,
        "number": max(i["number"] for i in data["issues"]) + 1,
        "date": date,
        "articles": [],
    }
    for a in draft["articles"]:
        a = dict(a)
        a["id"] = f"{date}-{a['category']}"
        issue["articles"].append(a)

    data["issues"].insert(0, issue)
    data["issues"].sort(key=lambda i: i["date"], reverse=True)

    out = json.dumps(data, ensure_ascii=False, indent=2) + "\n"
    if dry:
        tmp = "/tmp/mf_issues_check.json"
        with open(tmp, "w", encoding="utf-8") as f:
            f.write(out)
        subprocess.run([sys.executable, "tools/validate.py", tmp], check=True)
        print(f"（--dry のため issues.json は変更していません）")
        return

    with open("issues.json", "w", encoding="utf-8") as f:
        f.write(out)
    subprocess.run([sys.executable, "tools/validate.py", "issues.json"], check=True)
    print(f"追加しました: #{issue['number']:03d} {date}（公開は ./publish.sh）")


if __name__ == "__main__":
    main()
