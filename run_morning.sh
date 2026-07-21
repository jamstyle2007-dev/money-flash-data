#!/bin/bash
# Money Flash 毎朝の完全自動配信（JACK決定 2026-07-19・案C）
# AIはドラフト生成まで。公開は validate.py を通過した場合のみスクリプトが行う。
set -u
cd "$(dirname "$0")"
mkdir -p logs
LOG="logs/$(date +%F).log"
exec >> "$LOG" 2>&1
echo "===== run_morning $(date '+%F %T') ====="

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
TODAY=$(date +%F)

# 既に本日号があれば何もしない（多重起動ガード）
if python3 - <<EOF
import json, sys
data = json.load(open("issues.json"))
sys.exit(0 if any(i["date"] == "$TODAY" for i in data["issues"]) else 1)
EOF
then
  echo "本日号は既に存在。終了"
  exit 0
fi

rm -f draft_today.json

notify_fail() {
  osascript -e "display notification \"$1\" with title \"Money Flash 配信失敗\" sound name \"Basso\"" 2>/dev/null || true
}

# 1) AIがドラフト生成（git操作は許可しない）
claude -p "$(cat MORNING_PROMPT.md)" \
  --allowedTools "WebSearch" "WebFetch" "Read" "Write" "Bash(date:*)" "Bash(python3 tools/validate.py:*)" "Bash(python3 tools/checkdraft.py:*)" \
  --max-turns 40
echo "claude exit: $?"

# 2) ドラフト検証＋追加（NGなら自動修復を1回試してから止まる）
if [ ! -f draft_today.json ]; then
  echo "★draft_today.json が無い。生成失敗のため公開せず終了"
  notify_fail "ドラフト未生成（$TODAY）。ログを確認してください"
  exit 1
fi
python3 tools/checkdraft.py --fix || true
if ! python3 tools/add_issue.py draft_today.json; then
  echo "★検証NG。公開せず終了（draft_today.json を残置）"
  notify_fail "検証NGで未配信（$TODAY）。draft_today.json を確認してください"
  exit 1
fi

# 3) 公開
if ./publish.sh "Auto publish $TODAY"; then
  echo "公開完了: $TODAY"
  rm -f draft_today.json
else
  echo "★publish失敗"
  notify_fail "push失敗（$TODAY）。ネットワーク/認証を確認してください"
  exit 1
fi
