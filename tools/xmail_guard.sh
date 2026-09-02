#!/bin/bash
# 「本日のX投稿文メールを主機が既に送ったか」を判定する（待機機で使う）。
# 終了コード 0 = 送信済み（待機機は送らない） / 1 = 未送信（待機機が送る）
# 通信できず判定不能のときも 1 を返す＝送る側に倒す。届かないより重複のほうがまし。
set -u
TODAY="${1:-$(date +%F)}"
V=$(curl -s --max-time 20 \
  "https://api.github.com/repos/jamstyle2007-dev/money-flash-data/contents/xmail_sent.txt?ref=main" \
  -H "Accept: application/vnd.github.raw" | tr -d '[:space:]')
[ "$V" = "$TODAY" ]
