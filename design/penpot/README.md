# Negoto — Penpot design

iOS / iPadOS の次期デザイン。公式 AnkiMobile の公開機能を基準に、標準 Anki の編集・統計・スケジューリングを含めて設計しています。
これは**デザイン成果物**です。Swift アプリへの機能追加や AnkiWeb 接続の実装を意味しません。

## 成果物

- [Penpot「Negoto」](https://design.penpot.app/#/workspace?file-id=3e981c57-46d6-803d-8008-bf1d62818b30&page-id=b16bcfc9-1baa-8054-8008-bf8ce0a6feaa): 編集用の正本。ネイティブのボード・テキスト・図形・プロトタイプ遷移を保持。
- `preview.html`: 全画面を切り替えて確認できる、外部ライブラリ不要の SVG プレビュー。
- `proofs/`: 代表画面の SVG。`exports/` は Penpot から実際に書き出した PNG。
- `build.py`: 画面・レスポンシブ見本・設計ガイドを生成するソース。
- `import.js`: Penpot Plugin API で編集可能な要素と遷移を生成するインポーター。
- `penpot-index.json`: 作成先ファイル・ページ・ボードの ID、検証結果。

全90ボード：iPhone 67、iPad 12、可変幅・回転4、ダーク3、設計ガイド4。
数値、デッキ、プロフィール、統計はサンプルです。プロトタイプは主要操作の導線確認用で、検索・計算・同期を実行するアプリではありません。

Penpot上に `Negoto · verified · 90 boards / 615 interactions` の保存バージョンを作成済み。
Penpot 2.18.2 と MCPプラグインのAPI差により `.penpot` アーカイブの書き出しは `No matching clause` で失敗したため、このディレクトリにアーカイブは含めていません。正本と再生成ソースは保存しています。

## 画面と機能

| 機能 | 主な画面 | 設計範囲 |
| --- | --- | --- |
| デッキ | M01–03, M46–47, M67, I01, I10 | 階層、件数、作成、名称・親の変更、削除、共有デッキ、説明、学習開始 |
| 学習 | M04–09, M49–52, I02 | 表裏、4段階回答、間隔、Undo、入力比較、完了、音声再生・停止・シーク・録音、手書き |
| 学習ツール | M07–08, M17, M51, M66 | フラグ、マーク、カード/ノートの延期・保留と解除、期日、新規に戻す、カード情報、履歴、ユーザー操作 |
| ブラウズ | M10–12, M18, M56–57, I03 | Anki検索式、フィルタ、保存検索、タグ階層、並べ替え・表示列、複数選択、デッキ/ノートタイプ変更、検索置換 |
| ノート編集 | M13–16, M19, M58–59, I06–07, I11 | フィールド、基本/逆向き/穴埋め/入力/画像穴埋め、書式、HTML、数式、画像・音声・カメラ・手書き、テンプレートとCSS/JS/TTS、プレビュー |
| 統計 | M20–26, I04–05, I12 | 今日、復習数、学習時間、カレンダー、将来予定、カード状態、回答割合、時間帯、実際の保持率、間隔、SM-2 Ease、FSRS安定度・難易度・想起確率 |
| デッキ設定 | M31–33, M61, I08 | プリセット、日別/デッキ別上限、学習・再学習、リーチ、兄弟延期、収集/表示順、音声、タイマー、自動送り、Easy Days、カスタムスケジューリング、SM-2/FSRS |
| FSRS | M32, M61 | 目標保持率、パラメータ最適化・評価、履歴の除外日、再スケジュール、学習量シミュレーション |
| 集中学習 | M34–35 | 上限増加、忘れたカード、新規プレビュー、先取り、状態/タグ、任意検索・第2フィルタ、再スケジュール有無、構築・再構築・空にする |
| 同期 | M36–37, M55, M62, M70, I09 | AnkiWeb、メディア、オフライン、再試行、一方向の送信/受信、競合時の対象確認と事前バックアップ |
| データ移行 | M38–41, M63–65 | APKG/COLPKG/CSV/TSV、統合/置換、重複、フィールド対応、差分・結果、メディア/スケジュールの書き出し、バックアップ復元 |
| 設定 | M42, M44–45, M53, M60, M66 | プロフィール、テーマ、Dynamic Type、音声、TTS、タップ9領域×表裏、スワイプ、バー、ゲームパッド・キーボード、通知、日付切替、URLスキーム |
| 保守・例外 | M43, M48, M54–55, M67–69 | DB確認、欠落/未使用メディア、空カード、削除の対象確認、初期状態、通信エラー |

PC版のアドオン実行や外部LaTeXコンパイルは公式AnkiMobileの範囲外です。テンプレート、MathJax、既存のLaTeX画像、メディア表示は互換設計に含めています。
既存Negotoとの差分にはフィルタデッキ、AnkiWeb同期、複数プロフィールなどがあります。実装段階で別途対応が必要です。

## 可変幅と操作

- **320–599ptを目安とするcompact**: 下部タブ、1列、詳細へpush、編集フォームは全画面。iPadの狭いウィンドウも同じ構成。
- **600–999ptを目安とするregular**: サイドバーと詳細。コンテンツ幅に応じて統計を1〜2列にし、プレビューは切り替え。
- **1,000pt以上**: カードとインスペクタ、編集とプレビュー、複数列の統計。
- **1,300pt以上**: ブラウズをナビゲーション・一覧・編集の3ペインに。
- 実装では数値の境界より`horizontalSizeClass`と利用可能幅を優先します。R01–04で320pt、507pt、834pt縦、852pt横を確認できます。
- Penpot内のボタンはFlex Layout、コンテンツは左右伸縮制約を持ちます。画面構成の切り替えは各幅のボードとF03に明示。Penpot自体にアプリの実行時ブレークポイントを実装したものではありません。
- 長い統計・フォームはスクロール全体の設計図。実機ではSafe Areaを考慮し、ナビゲーションと主要操作を可視領域に保持します。
- 操作領域は原則44pt以上。大きい文字では縦積み、回答は2×2に切り替えます。VoiceOver順序・グラフの数値表・キーボード操作・Reduce MotionをF03で指定。

## 再生成

```sh
python3 design/penpot/build.py
```

Python標準ライブラリのみを使用します。`generated/`に各ボードのJSONとmanifestを生成します。
接続済みのPenpot MCPで`import.js`の内容を`execute_code`に渡し、次に各JSONを以下の形で渡します。

```js
return await storage.negoto.importScreen(scene);
```

作成後に`storage.negoto.linkAll()`を実行します。同じキー・内容はスキップし、変更したボードだけ再作成します。再生成は手編集の上書きにつながるため、手編集後は別ファイルか保存バージョンを残して実行してください。
`build.py`は成果物を更新するため、リポジトリの変更は通常のレビュー・コミット対象です。

## 参照した公式資料

2026-10-06確認。非公式の追加機能を公式機能として扱わないよう、以下を基準にしています。

- [AnkiMobile — Deck List](https://docs.ankimobile.net/deck-list.html)
- [AnkiMobile — Study Tools](https://docs.ankimobile.net/study-tools.html)
- [AnkiMobile — Adding & Editing](https://docs.ankimobile.net/editing.html)
- [AnkiMobile — Preferences](https://docs.ankimobile.net/preferences.html)
- [AnkiMobile — Cloud Sync](https://docs.ankimobile.net/syncing.html)
- [AnkiMobile — Collection Transfer](https://docs.ankimobile.net/collection-transfer.html)
- [Anki — Statistics](https://docs.ankiweb.net/stats.html)
- [Anki — Deck Options](https://docs.ankiweb.net/deck-options.html)
- [Anki — Filtered Decks](https://docs.ankiweb.net/filtered-decks.html)
- [Anki — Card Templates](https://docs.ankiweb.net/templates/intro.html)
