# Money Flash 配信修復タスク

あなたはMoney Flashの配信修復担当です。今日の号（issues.jsonの本日日付の号）がまだ配信できていません。
作業ディレクトリは ~/money-flash-data。以下の手順で**必ず配信可能な draft_today.json を完成させる**ことがゴールです。

## 手順

1. `logs/本日日付.log` を読み、どの段階で失敗したかを特定する
2. `draft_today.json` が存在するなら読み、検証エラー（ログに記載）を修正する
   - 表現の問題なら該当箇所だけ最小限書き換える
   - JSONが壊れているなら構文を修復する
3. `draft_today.json` が無い・修復不能なら、`MORNING_PROMPT.md` の要領で本日の3本を新規に書く
4. `python3 tools/checkdraft.py` でセルフチェックし、`python3 tools/add_issue.py draft_today.json --dry` が
   通ることを確認してから終了する（--dry必須。issues.jsonへの追加・公開はスクリプト側が行う）

## 禁止事項

- git操作はしない（公開はスクリプトの役目）
- issues.json を直接編集しない（draft_today.json だけを作る/直す）
- 半角ダブルクォートは値の中に使わない（「」を使う）
