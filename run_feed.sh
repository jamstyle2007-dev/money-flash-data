#!/bin/bash
# Money Flash フィード更新（1日3回: 6:10 / 12:00 / 18:00）
# AIはfeed_draft.jsonの生成まで。検証を通過した場合のみfeed.jsonへ反映して公開する。
set -u
cd "$(dirname "$0")"
mkdir -p logs
LOG="logs/feed-$(date +%F).log"
exec >> "$LOG" 2>&1
echo "===== run_feed $(date '+%F %T') ====="

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

notify_fail() {
  osascript -e "display notification \"$1\" with title \"Money Flash フィード失敗\" sound name \"Basso\"" 2>/dev/null || true
}

rm -f feed_draft.json

claude -p "$(cat FEED_PROMPT.md)" \
  --allowedTools "WebSearch" "WebFetch" "Read" "Write" "Bash(date:*)" "Bash(python3 tools/validate_feed.py:*)" \
  --max-turns 50
echo "claude exit: $?"

if [ ! -f feed_draft.json ]; then
  echo "★feed_draft.json が無い。生成失敗のため公開せず終了"
  notify_fail "フィード未生成 $(date '+%H:%M')"
  exit 1
fi
if ! python3 tools/validate_feed.py feed_draft.json; then
  echo "★検証NG。公開せず終了（feed_draft.json を残置）"
  notify_fail "フィード検証NG $(date '+%H:%M')"
  exit 1
fi

mv feed_draft.json feed.json
python3 tools/add_images.py feed.json || echo "（画像付与に失敗。画像なしで公開続行）"
python3 tools/validate_feed.py feed.json || { echo "★画像付与後の検証NG"; notify_fail "画像付与後の検証NG"; exit 1; }
git add feed.json
git commit -m "Feed update $(date '+%F %H:%M')"
if git push; then
  echo "フィード公開完了"
else
  echo "★push失敗"
  notify_fail "フィードpush失敗 $(date '+%H:%M')"
  exit 1
fi
