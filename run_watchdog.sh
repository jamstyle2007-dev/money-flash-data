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

# 待機モード（2台目のMac用）: 判断前に必ずリモート最新へ同期する
if [ "${MF_STANDBY:-0}" = "1" ]; then
  git fetch origin main --quiet && git reset --hard origin/main --quiet
fi

notify() {
  osascript -e "display notification \"$1\" with title \"Money Flash 見張り\" sound name \"Basso\"" 2>/dev/null || true
}

# 0=配信済み / 1=未配信 / 2=判定不能（GitHubに到達できない）
# 「通信できない」を「未配信」と断定しないこと。2026-09-19に一時的な通信断で
# 配信済みの日に復旧フェーズが走り、AIを無駄に呼んだうえ誤警報を出した。
published() {
  # CDNの遅延に影響されないよう GitHub API(origin本体)で確認する
  local body
  body=$(curl -sf --max-time 30 \
    "https://api.github.com/repos/jamstyle2007-dev/money-flash-data/contents/issues.json?ref=main" \
    -H "Accept: application/vnd.github.raw") || return 2
  [ -n "$body" ] || return 2
  printf '%s' "$body" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(2)
sys.exit(0 if any(i['date'] == '$TODAY' for i in d['issues']) else 1)"
}

STATE=0; published || STATE=$?
if [ "$STATE" = "2" ]; then
  # 通信が無ければ記事の生成自体ができないので、ここで騒がず次の見張りに委ねる
  echo "GitHubに到達できず判定不能。復旧は行わない（次回の見張りで再確認）"
  exit 0
fi

if [ "$STATE" = "0" ]; then
  echo "本日号($TODAY)は配信済み。OK"
  # 配信済みでもX投稿文メールが未送信なら、ここで送る。
  # 2026-09-08にGitHub認証が切れて6:30のxpostが「本日号なし」でスキップし、
  # その後に配信された結果、メールを送る係が誰もいなくなった。
  # 送信済み判定は「共有マーカー(他機が送った)」と「このMacのフラグ」の両方で見る。
  if ! bash tools/xmail_guard.sh "$TODAY" && [ ! -f "$HOME/money-flash/xpost/logs/mailed_$TODAY.flag" ]; then
    echo "X投稿文メールが未送信。送る"
    python3 "$HOME/money-flash/xpost/xpost.py" --draft || true
  fi
  exit 0
fi

# push直後のGitHub APIは数秒だけ古い値を返すことがある。復旧後の確認はこれで待つ。
# 単発で判定すると「未配信」と誤検知してAI修復フェーズに入り、AIの週間上限を無駄に食う
# （2026-09-04に実際に発生）。
# 戻り値は published と同じ（2=判定不能）。判定不能を失敗として通知しないため。
published_retry() {
  local st=1
  for _ in 1 2 3; do
    published && return 0
    st=$?
    sleep 10
  done
  return $st
}


echo "未配信を検知。復旧を開始"
notify "本日号が未配信。復旧を開始します"

# ① 通常パイプラインを再実行（生成2試行+自動修復+publishリトライを内包）
bash ./run_morning.sh || true
ST=0; published_retry || ST=$?
if [ "$ST" = "0" ]; then
  echo "復旧完了（run_morning再実行）"
  notify "復旧完了: 本日号を配信しました"
  python3 ~/money-flash/xpost/xpost.py --draft || true  # 遅延配信日もX投稿文をJACKへ
  exit 0
fi
if [ "$ST" = "2" ]; then
  # 通信が無い状態ではAI修復も必ず失敗する。無駄打ちと誤警報を避けて次回に委ねる
  echo "通信不可で確認できない。AI修復は行わず終了（次回の見張りで再確認）"
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

ST=0; published_retry || ST=$?
if [ "$ST" = "0" ]; then
  echo "復旧完了（AI修復）"
  notify "復旧完了: AI修復で本日号を配信しました"
  python3 ~/money-flash/xpost/xpost.py --draft || true  # 遅延配信日もX投稿文をJACKへ
  exit 0
fi
if [ "$ST" = "2" ]; then
  echo "通信不可で確認できない。誤警報を避けるため通知しない（次回の見張りで再確認）"
  exit 0
fi

echo "★復旧失敗。手動対応が必要"
notify "復旧失敗（$TODAY）。手動対応が必要です"
exit 1
