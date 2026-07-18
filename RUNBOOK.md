# Money Flash 毎朝の運用手順（RUNBOOK）

**2026-07-19より完全自動運用（JACK決定・案C）。** 毎朝6:00にlaunchd（`com.jack.moneyflash.morning`）が `run_morning.sh` を実行し、生成→機械検証→公開まで無人で完了する。JACKの作業はゼロ（事後チェックのみ）。

## 自動フロー（毎朝6:00）

1. `run_morning.sh` 起動（ログ: `logs/YYYY-MM-DD.log`。本日号が既にあれば何もしない）
2. ヘッドレスClaude（`MORNING_PROMPT.md`）が3記事のドラフト `draft_today.json` を生成。**AIにはgit操作を許可していない**
3. `add_issue.py` → `validate.py` の機械検証（3本構成・一次情報リンク・禁止表現・scamルール）。**NGなら公開されず終了**
4. 検証通過時のみ `publish.sh` で公開。アプリは次回起動時に自動取得
5. 事後修正: issues.json を直して `./publish.sh` すれば数分で全ユーザーに反映される

## 手動フォールバック（自動が失敗した朝や差し替えたい時）

1. **JACKがトリガー**（例：「今朝の号を作って」）
2. **私がドラフト生成**
   - MONEY枠: 「個人の財布・資産形成に効く変化」を1本（JACK指示 2026-07-18で対象を拡大）
     - 市況: 株価の動き・為替の動き・企業決算の動き（個人投資家の判断に影響するもの）
     - 制度: NISA・税制・金利など制度変更（金融庁・日銀・国税庁）
     - 資産形成の有益情報: ポイ活・マイル・クレジットカード（還元率変更・改悪/改善・キャンペーン等も資産形成として扱う）
     - 巡回先: 大手経済報道・公的機関に加え、ポイント/カード系の一次情報（各社公式リリース）
   - SIDE HUSTLE枠: AI副業・アプリ・コンテンツ販売等でJACKの実録知見が乗るネタを1本
   - SCAM ALERT枠: 次の4系統から最新手口を1本（JACK指示 2026-07-18）
     1. `~/jack-scam-engine` の radar（ネタ仕入れの主経路）
     2. **金融庁「無登録で金融商品取引業を行う者」警告リスト**（https://www.fsa.go.jp/ordinary/chuui/mutoroku.html ・radar.py の fsa_names() で取得可。実名を出せる唯一の確定情報源）
     3. **JACK公式ブログ（jack-invest.com）の警告記事**（例: ドバイ事業投資話の警告。アプリ記事化で相互送客にもなる）
     4. 警察庁/消費者庁の注意喚起
   - 各記事 = title / flash（3行要約）/ comment（JACKの視点・一人称は「私」）/ sources（一次情報URL必須）
3. **公開**（Money Flashアプリ配信は事前承認不要＝JACK決定2026-07-19。jack-investブログ記事は従来通り承認制）
   - 詐欺記事の実名は金融庁無登録リスト等の公的公表がある場合のみ・最新案件のみ（自動/手動共通ルール）
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
