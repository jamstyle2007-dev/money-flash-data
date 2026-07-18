# Money Flash 毎朝の運用手順（RUNBOOK）

配信の全体像：**生成 → JACK承認 → 公開** の3ステップ。公開までClaude Code（私）が実行し、JACKの作業は承認だけ。

## 毎朝のフロー

1. **JACKがトリガー**（例：「今朝の号を作って」）
2. **私がドラフト生成**
   - MONEY枠: 市況・制度変更から「個人の財布に影響する変化」を1本（金融庁・日銀・国税庁・大手報道を巡回）
   - SIDE HUSTLE枠: AI副業・アプリ・コンテンツ販売等でJACKの実録知見が乗るネタを1本
   - SCAM ALERT枠: `~/jack-scam-engine` の radar ＋ 金融庁/警察庁/消費者庁の注意喚起から最新手口を1本
   - 各記事 = title / flash（3行要約）/ comment（JACKの視点・一人称は「私」）/ sources（一次情報URL必須）
3. **JACKに候補提示 → 承認**
   - 詐欺記事は承認ルール準拠：記事化前に候補提示・最新案件のみ・実名業者の断定は金融庁警告リスト等の一次情報がある場合のみ
   - 修正指示があれば反映して再提示
4. **公開**（承認後は追加確認なしで実行）
   ```bash
   python3 tools/add_issue.py draft.json   # 自動採番で issues.json に追加＋検証
   ./publish.sh                            # 検証 → commit → push
   ```
5. アプリは次回起動時に自動で最新号を取得（審査再提出は不要）

## 記事の書き方ルール

- 一人称は「私」。断定は一次情報がある場合のみ
- flash は事実のみ、comment に意見・判断を書く（事実と意見の分離）
- 「必ず儲かる」等の断定的利益表現は禁止（投資助言非該当を守る）
- scam記事のタイトルは【警戒】プレフィックス
- 大人向け表記（漢字使用、子供向け平仮名にしない）

## データ形式

`issues.json` — アプリが取得する全データ。形式は `tools/validate.py` が唯一の正。
draft.json の形式:

```json
{
  "date": "2026-07-19",
  "articles": [
    { "category": "money",      "title": "...", "flash": ["...", "...", "..."], "comment": "...", "sources": [{"title": "...", "url": "https://..."}] },
    { "category": "sidehustle", "title": "...", "flash": ["..."], "comment": "...", "sources": [...] },
    { "category": "scam",       "title": "【警戒】...", "flash": ["..."], "comment": "...", "sources": [...] }
  ]
}
```

## 配信先

- リポジトリ: https://github.com/jamstyle2007-dev/money-flash-data （公開）
- アプリ取得URL: https://raw.githubusercontent.com/jamstyle2007-dev/money-flash-data/main/issues.json
- アプリ側フォールバック: リモート失敗時はキャッシュ → 同梱データの順で表示（配信事故でもアプリは死なない）
- **注意: raw.githubusercontent.com はCDNキャッシュ最大5分（max-age=300）。** 通知時刻（デフォルト朝7時）の5分以上前に publish.sh を済ませること
