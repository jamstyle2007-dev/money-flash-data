#!/bin/bash
# Money Flash 配信見張り（毎朝7:00）
# 本日号がGitHub本体(originのmain)に公開済みかを確認し、未配信なら
# ①run_morning再実行 → ②AI修復(REPAIR_PROMPT) → ③追加・公開 の順に復旧を試みる。
# 結果は成功・失敗どちらでも通知する。
set -u
cd "$(dirname "$0")"
mkdir -p logs
LOG="logs/watchdog-$(date +%F).log"
exec >> "$LOG" 2>&1
echo "===== run_watchdog $(date '+%F %T') ====="

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
TODAY=$(date +%F)

notify() {
  osascript -e "display notification \"$1\" with title \"Money Flash 見張り\" sound name \"Basso\"" 2>/dev/null || true
}

published() {
  # CDNの遅延に影響されないよう GitHub API(origin本体)で確認する
  curl -s --max-time 30 \
    "https://api.github.com/repos/jamstyle2007-dev/money-flash-data/contents/issues.json?ref=main" \
    -H "Accept: application/vnd.github.raw" \
  | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    ok = any(i['date'] == '$TODAY' for i in d['issues'])
except Exception:
    ok = False
sys.exit(0 if ok else 1)"
}

if published; then
  echo "本日号($TODAY)は配信済み。OK"
  exit 0
fi

echo "未配信を検知。復旧を開始"
notify "本日号が未配信。復旧を開始します"

# ① 通常パイプラインを再実行（生成2試行+自動修復+publishリトライを内包）
bash ./run_morning.sh || true
if published; then
  echo "復旧完了（run_morning再実行）"
  notify "復旧完了: 本日号を配信しました"
  python3 ~/money-flash/xpost/xpost.py --draft || true  # 遅延配信日もX投稿文をJACKへ
  exit 0
fi

# ② AI修復: ログとドラフトを調査して draft_today.json を完成させる
echo "--- AI修復フェーズ ---"
claude -p "$(cat REPAIR_PROMPT.md)" \
  --allowedTools "Read" "Write" "WebSearch" "WebFetch" "Bash(date:*)" "Bash(python3 tools/validate.py:*)" "Bash(python3 tools/checkdraft.py:*)" "Bash(python3 tools/checkfresh.py:*)" "Bash(python3 tools/add_issue.py:*)" \
  --max-turns 40
echo "repair claude exit: $?"

# ③ 修復されたドラフトを機械検証つきで追加・公開
if [ -f draft_today.json ]; then
  python3 tools/checkdraft.py --fix || true
  python3 tools/sanitize.py draft_today.json || true
  if python3 tools/add_issue.py draft_today.json; then
    python3 tools/add_images.py issues.json || true
    if python3 tools/validate.py issues.json || { python3 tools/sanitize.py issues.json; python3 tools/validate.py issues.json; }; then
      ./publish.sh "Auto publish $TODAY (watchdog repair)" || true
    fi
  fi
fi

if published; then
  echo "復旧完了（AI修復）"
  notify "復旧完了: AI修復で本日号を配信しました"
  python3 ~/money-flash/xpost/xpost.py --draft || true  # 遅延配信日もX投稿文をJACKへ
  exit 0
fi

echo "★復旧失敗。手動対応が必要"
notify "復旧失敗（$TODAY）。手動対応が必要です"
exit 1
