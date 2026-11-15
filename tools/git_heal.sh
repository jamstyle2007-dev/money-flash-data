#!/bin/bash
# 保管場所が壊れた形で止まっていたら、GitHub の本体（origin/main）に合わせ直す。
#
# 2026-11-14 19:08、2台のMacがほぼ同時にフィードを更新し、主機の「取り込んでから押し直す」が
# 競合で途中停止した。主機は枝から外れたままになり、以後2日間、号・フィード・送った印の
# どれも GitHub に届かなかった。号は待機機が代わりに出し、X投稿文メールは毎朝2通になった。
# 失敗は毎回ログに出ていたが、止まった状態を片づける係がいなかったのが原因。
#
# issues.json / feed.json / xmail_sent.txt は GitHub の本体が正。競合するのは相手のMacが
# 同じ仕事を先に済ませた時だけなので、手元の版は取り下げてよい。
# 取り下げる前に、手元だけの履歴は heal-backup-* の枝に、コミット前の変更は stash に残す。
#
# 使い方: bash tools/git_heal.sh
#   ・各ジョブの先頭で呼ぶ（壊れていなければ何もしない）
#   ・「取り込んでから押し直す」が失敗した直後にも呼ぶ（競合で止まっていれば片づける）
# 終了コードは常に 0。直せなくても本体のジョブは止めない。
set -u
cd "$(cd "$(dirname "$0")/.." && pwd)" || exit 0
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

why=""
if [ -d .git/rebase-merge ] || [ -d .git/rebase-apply ]; then
  why="取り込みが競合で途中停止している"
elif [ -f .git/MERGE_HEAD ]; then
  why="取り込みの合流が途中で止まっている"
elif ! git symbolic-ref -q HEAD >/dev/null 2>&1; then
  why="枝から外れている"
elif [ "$(git symbolic-ref -q --short HEAD 2>/dev/null)" != "main" ]; then
  why="main 以外の枝にいる"
fi
[ -z "$why" ] && exit 0

echo "[heal] $why → GitHub の本体に合わせ直す"
notify() {
  osascript -e "display notification \"$1\" with title \"Money Flash 保管場所\" sound name \"Basso\"" 2>/dev/null || true
}

# 本体を取れない時は触らない（合わせる先が古いまま合わせ直すと、手元の新しい版を失う）
if ! git fetch origin main --quiet; then
  echo "[heal] GitHub に届かない。今回は見送り（次のジョブでもう一度試す）"
  exit 0
fi

STAMP=$(date +%Y%m%d-%H%M%S)
git branch -f "heal-backup-$STAMP" HEAD >/dev/null 2>&1 && echo "[heal] 手元だけの履歴を heal-backup-$STAMP に残した"
# 取り込みの途中だと、押し直そうとしていたコミットは HEAD ではなく orig-head の側にある
for f in .git/rebase-merge/orig-head .git/rebase-apply/orig-head; do
  [ -f "$f" ] && git branch -f "heal-backup-$STAMP-orig" "$(cat "$f")" >/dev/null 2>&1
done

# コミット前の変更が残っていれば先に stash へ（取り込みを取り消すと消えるため、取り消しより前に行う）。
# 競合の印が付いたままだと stash できないので、その時は生成物の写しを logs に残す。
if ! git diff --quiet HEAD 2>/dev/null; then
  if git stash push --quiet -m "heal-$STAMP" >/dev/null 2>&1; then
    echo "[heal] コミット前の変更を stash（heal-$STAMP）に残した"
  else
    mkdir -p "logs/heal-$STAMP" && cp -p issues.json feed.json xmail_sent.txt "logs/heal-$STAMP/" 2>/dev/null
    echo "[heal] stash できないので、生成物の写しを logs/heal-$STAMP に残した"
  fi
fi

git rebase --abort >/dev/null 2>&1 || git rebase --quit >/dev/null 2>&1 || true
git merge --abort >/dev/null 2>&1 || true
rm -rf .git/rebase-merge .git/rebase-apply 2>/dev/null

if git checkout --quiet --force -B main origin/main && git branch --quiet --set-upstream-to=origin/main main; then
  echo "[heal] 合わせ直した: $(git log -1 --format='%h %s')"
  notify "保管場所が止まっていたので GitHub の本体に合わせ直しました"
else
  echo "[heal] ★合わせ直せなかった。手で確認が必要"
  notify "保管場所を合わせ直せません。手で確認を"
fi

# 14日より古い控えの枝は片づける（枝の名前の日付で見る）
CUT=$(date -v-14d +%Y%m%d 2>/dev/null || echo 0)
git for-each-ref --format='%(refname:short)' 'refs/heads/heal-backup-*' 2>/dev/null \
| while read -r name; do
    day=${name#heal-backup-}; day=${day%%-*}
    case "$day" in (*[!0-9]*|'') continue;; esac
    [ "$day" -lt "$CUT" ] && git branch -D "$name" >/dev/null 2>&1
  done
exit 0
