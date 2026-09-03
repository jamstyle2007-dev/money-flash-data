#!/bin/bash
# issues.json を検証して GitHub へ公開する。
# 検証NGなら push しない（壊れたデータを全ユーザーに配らないため）。
# 使い方:  ./publish.sh           （メッセージ自動）
#          ./publish.sh "コメント"  （コミットメッセージ指定）
set -e
cd "$(dirname "$0")"

echo "▶ 検証中..."
python3 tools/validate.py issues.json || { echo "✋ 検証NGのため公開を中止しました。"; exit 1; }

if git diff --quiet issues.json && git diff --cached --quiet issues.json; then
  echo "（issues.json に変更なし。公開するものがありません）"
  exit 0
fi

MSG="${1:-Publish issue $(date +%F)}"
git add issues.json
git commit -m "$MSG"
echo "▶ push 中..."
# 待機機(2台目Mac)が先にpushしているとリモートが進んでいて弾かれる。
# その場合だけ取り込んでから押し直す（--autostash で未コミットの変更があっても止まらない）
if ! git push; then
  echo "▶ リモートが進んでいたので取り込んでから再push"
  git pull --rebase --autostash --quiet origin main && git push
fi
echo "✅ 公開しました。アプリは次回起動時に最新号を取得します。"
