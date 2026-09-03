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

# 待機モード（2台目のMac用）: 主機が直近3時間以内に更新していれば何もしない
if [ "${MF_STANDBY:-0}" = "1" ]; then
  echo "[standby] リモート最新に同期"
  git fetch origin main --quiet && git reset --hard origin/main --quiet
  if curl -s --max-time 30 \
      "https://api.github.com/repos/jamstyle2007-dev/money-flash-data/contents/feed.json?ref=main" \
      -H "Accept: application/vnd.github.raw" \
    | python3 -c "
import json, sys
from datetime import datetime
try:
    u = json.load(sys.stdin).get('updated', '')
    fresh = (datetime.now() - datetime.strptime(u, '%Y-%m-%dT%H:%M')).total_seconds() < 3 * 3600
except Exception:
    fresh = False
sys.exit(0 if fresh else 1)"; then
    echo "[standby] フィードは主機が更新済み。何もせず終了"
    exit 0
  fi
  echo "[standby] フィードが古い。代わりに更新する"
fi

# 電源断などで取りこぼした回を起動時に埋めるための空振り防止（2026-09-04追加）。
# 直近3時間以内に更新済みなら何もしない。通常の3回(6:10/12:00/18:00)は6時間近く空くので
# 影響せず、再起動が続いた日にAIを何度も呼んで週間上限を食うのだけを防ぐ。
if curl -s --max-time 30 \
    "https://api.github.com/repos/jamstyle2007-dev/money-flash-data/contents/feed.json?ref=main" \
    -H "Accept: application/vnd.github.raw" \
  | python3 -c "
import json, sys
from datetime import datetime
try:
    u = json.load(sys.stdin).get('updated', '')
    fresh = (datetime.now() - datetime.strptime(u, '%Y-%m-%dT%H:%M')).total_seconds() < 3 * 3600
except Exception:
    fresh = False
sys.exit(0 if fresh else 1)"; then
  echo "フィードは3時間以内に更新済み。今回はスキップ"
  exit 0
fi

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
python3 tools/sanitize.py feed_draft.json || true
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
# 待機機が先にpushしているとリモートが進んでいて弾かれるので、その場合だけ取り込んで押し直す
git push || { git pull --rebase --autostash --quiet origin main && git push; }
if [ $? -eq 0 ]; then
  echo "フィード公開完了"
else
  echo "★push失敗"
  notify_fail "フィードpush失敗 $(date '+%H:%M')"
  exit 1
fi
