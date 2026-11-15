#!/bin/bash
# X投稿文メールを送った日付を共有リポジトリに記録する（主機・待機機どちらでも実行）。
# 待機機(2台目Mac)はこのファイルを見て「主機が既に送った」と判断し、二重送信を避ける。
# 記録に失敗しても何も止めない。失敗した日は待機機が送るので、欠落ではなく重複側に倒れる。
set -u
DATE="${1:?日付}"
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
REPO=/Users/jamstyle01/money-flash-data            # 主機
[ -d "$REPO/.git" ] || REPO="$(cd "$(dirname "$0")/.." && pwd)"   # 待機機は自分の場所から解決
cd "$REPO" || exit 0
bash tools/git_heal.sh || true   # 保管場所が止まっていると印が届かず、メールが二重になる（2026-11-15・16に発生）
echo "$DATE" > xmail_sent.txt
git add xmail_sent.txt 2>/dev/null || exit 0
git commit -q -m "xmail sent $DATE" -- xmail_sent.txt 2>/dev/null || exit 0
git push -q origin main 2>/dev/null && exit 0
git pull --rebase --autostash -q origin main 2>/dev/null && git push -q origin main 2>/dev/null && exit 0
bash tools/git_heal.sh || true   # 競合で止まったままにしない
exit 0
