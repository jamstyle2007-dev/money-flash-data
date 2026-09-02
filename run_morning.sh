#!/bin/bash
# Money Flash 毎朝の完全自動配信
# 方針（JACK指示 2026-07-28）: 毎日配信の信用が第一。検証は「止める」ためでなく
# 「自動修正して必ず出す」ための検出器。生成→自動修復→再生成の多段リカバリで
# 配信到達を最優先する。構造破損（アプリが読めないJSON）だけは公開しない。
set -u
cd "$(dirname "$0")"
mkdir -p logs
LOG="logs/$(date +%F).log"
exec >> "$LOG" 2>&1
echo "===== run_morning $(date '+%F %T') ====="

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
TODAY=$(date +%F)

# 待機モード（2台目のMac用）: MF_STANDBY=1 のとき
#   ①判断前に必ずリモート最新へ同期する（ローカルの分岐を残さない）
#   ②本日号がGitHubで公開済みなら何もせず終了＝主機が動いていれば二重生成しない
# 注意: この同期はコミットしていない変更を消す。開発時は先にコミットしてから実行すること。
if [ "${MF_STANDBY:-0}" = "1" ]; then
  echo "[standby] リモート最新に同期"
  git fetch origin main --quiet && git reset --hard origin/main --quiet
  if curl -s --max-time 30 \
      "https://api.github.com/repos/jamstyle2007-dev/money-flash-data/contents/issues.json?ref=main" \
      -H "Accept: application/vnd.github.raw" \
    | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    ok = any(i['date'] == '$TODAY' for i in d['issues'])
except Exception:
    ok = False
sys.exit(0 if ok else 1)"; then
    echo "[standby] 本日号は主機が配信済み。何もせず終了"
    exit 0
  fi
  echo "[standby] 主機が未配信。代わりに生成する"
fi

notify() {
  osascript -e "display notification \"$1\" with title \"Money Flash 配信\" sound name \"Basso\"" 2>/dev/null || true
}

# ローカルに本日号が既にある場合: 公開済みなら終了、未公開ならpushリトライだけ行う
if python3 - <<EOF
import json, sys
data = json.load(open("issues.json"))
sys.exit(0 if any(i["date"] == "$TODAY" for i in data["issues"]) else 1)
EOF
then
  if git diff --quiet HEAD -- issues.json 2>/dev/null; then
    echo "本日号は既に公開済み。終了"
  else
    echo "本日号はローカルにあるが未push。publishをリトライ"
    ./publish.sh "Auto publish $TODAY (retry)" && echo "公開完了(リトライ)" || notify "push失敗（$TODAY）。手動確認を"
  fi
  exit 0
fi

# 生成→修復→追加を最大2回試行（2回目は検証エラーをAIにフィードバック）
ERRFILE="/tmp/mf_add_err.txt"
for ATTEMPT in 1 2; do
  echo "--- 生成試行 $ATTEMPT ---"
  rm -f draft_today.json

  PROMPT="$(cat MORNING_PROMPT.md)"
  if [ "$ATTEMPT" = "2" ] && [ -s "$ERRFILE" ]; then
    PROMPT="$PROMPT

【重要】前回の生成は以下の検証エラーで失敗した。同じ誤りを繰り返さないこと:
$(cat "$ERRFILE")"
  fi

  claude -p "$PROMPT" \
    --allowedTools "WebSearch" "WebFetch" "Read" "Write" "Bash(date:*)" "Bash(python3 tools/validate.py:*)" "Bash(python3 tools/checkdraft.py:*)" "Bash(python3 tools/checkfresh.py:*)" \
    --max-turns 40
  echo "claude exit: $?"

  if [ ! -f draft_today.json ]; then
    echo "draft_today.json が無い（試行$ATTEMPT）"
    echo "ドラフトファイルが生成されなかった" > "$ERRFILE"
    continue
  fi

  # 自動修復2段: 引用符など構文修復 → 禁止表現の自動言い換え
  python3 tools/checkdraft.py --fix || true
  python3 tools/sanitize.py draft_today.json || true

  # 鮮度チェック（検出器）: 古いネタは試行1なら差し替え再生成。試行2は警告のみで配信続行
  FRESHERR="/tmp/mf_fresh_err.txt"
  if ! python3 tools/checkfresh.py > "$FRESHERR" 2>&1; then
    cat "$FRESHERR"
    if [ "$ATTEMPT" = "1" ]; then
      cp "$FRESHERR" "$ERRFILE"
      echo "鮮度NG（試行1）。より新しいネタで再生成する"
      continue
    fi
    echo "鮮度NG（試行2）。配信優先で続行"
    notify "本日号に古いネタの疑いあり。配信は継続（$TODAY）"
  fi

  if python3 tools/add_issue.py draft_today.json > "$ERRFILE" 2>&1; then
    cat "$ERRFILE"
    echo "追加OK（試行$ATTEMPT）"
    break
  fi
  cat "$ERRFILE"
  echo "検証NG（試行$ATTEMPT）"
  if [ "$ATTEMPT" = "2" ]; then
    echo "★2回失敗。7時の見張りタスクが再試行します"
    notify "朝の生成が2回失敗（$TODAY）。7時の見張りが再試行します"
    exit 1
  fi
done

# 本日号がissues.jsonに入ったか最終確認
if ! python3 - <<EOF
import json, sys
data = json.load(open("issues.json"))
sys.exit(0 if any(i["date"] == "$TODAY" for i in data["issues"]) else 1)
EOF
then
  echo "★本日号を追加できず終了"
  notify "本日号の生成に失敗（$TODAY）。7時の見張りが再試行します"
  exit 1
fi

# 画像付与（失敗しても公開は止めない）
python3 tools/add_images.py issues.json || echo "（画像付与に失敗。画像なしで公開続行）"
# 画像付与後の最終検証: NGでも sanitize で救えるなら救う。構造破損のみ公開中止
if ! python3 tools/validate.py issues.json; then
  python3 tools/sanitize.py issues.json || true
  if ! python3 tools/validate.py issues.json; then
    echo "★最終検証NG（構造問題の可能性）。公開せず見張りに委ねる"
    notify "最終検証NG（$TODAY）。7時の見張りが再試行します"
    exit 1
  fi
fi

# 公開
if ./publish.sh "Auto publish $TODAY"; then
  echo "公開完了: $TODAY"
  rm -f draft_today.json "$ERRFILE"
else
  echo "★publish失敗"
  notify "push失敗（$TODAY）。ネットワーク/認証を確認してください"
  exit 1
fi
