# Negoto — 新規 AnkiMobile 互換デザイン

既存のデザインを引き継がず、公式 **AnkiMobile（iOS / iPadOS）** の公開マニュアルを基準に作成したUI設計。81の画面・状態、共通コンポーネント、色トークン、幅別のレイアウト、プロトタイプを含む。アプリの機能実装・実データとの接続はこの成果物の範囲に含まれない。

- [Penpot「Negoto 2」／iPhone](https://design.penpot.app/#/workspace?file-id=fd558256-f8c8-8184-8008-bfb2c62df8e9&page-id=2d12ccb2-c9ea-8013-8008-bfb7708109db)
- [iPad](https://design.penpot.app/#/workspace?file-id=fd558256-f8c8-8184-8008-bfb2c62df8e9&page-id=2d12ccb2-c9ea-8013-8008-bfb77081556d)
- [画面幅・アクセシビリティ](https://design.penpot.app/#/workspace?file-id=fd558256-f8c8-8184-8008-bfb2c62df8e9&page-id=2d12ccb2-c9ea-8013-8008-bfb77081b20a)
- [デザインシステム](https://design.penpot.app/#/workspace?file-id=fd558256-f8c8-8184-8008-bfb2c62df8e9&page-id=2d12ccb2-c9ea-8013-8008-bfb76e868efd)

## 見る・再生成する

`prototype.html` は幅を変えて操作できる設計プレビュー。学習・回答・検索・編集・統計・設定の主要動線と、全画面の一覧を備える。数値・保存・同期・音声はデモであり、Ankiデータを読み書きしない。

```sh
python3 design/penpot-v2/build.py
python3 -m http.server 8765 --bind 127.0.0.1
# http://127.0.0.1:8765/design/penpot-v2/prototype.html
```

`build.py` → `scene.json` / `proofs/*.svg` / `screen-index.js` を生成。`import.js` をPenpot MCPで評価し、`storage.fresh.setup(data)`、各画面の `importScreen(screen)`、`link()`、`addHandoff()` の順に実行する。`setup` と `addHandoff` は新しいページ・アセットを作成するため、既存ファイルへの無条件の再実行はしない。接続ファイルを確認してから使う。

`penpot-index.json` は実際のページとボードのID。`exports/*.png` / `exports/*.svg` はPenpotからの実書き出し。`proofs/` は同じ設計データから生成した参照図であり、Penpotのスクリーンショットとは区別する。

## 幅で切り替えるレイアウト

画面幅は端末モデルではなく、**現在のウインドウのコンテンツ幅（pt）** で判断する。回転・Split View・Stage Manager・ウインドウリサイズで選択中のデッキ、検索語、スクロール位置、編集中のノートを維持する。

| 幅 | ナビゲーション | コンテンツ |
| --- | --- | --- |
| 320–599 | 下部4タブ、戻るナビゲーション | 1列。ブラウズの詳細は次画面。統計は縦積み。余白20pt |
| 600–743 | 下部4タブを保持 | 1ワークスペース。余白32pt。フォームは中央、最大640–720pt |
| 744–1023 | 232ptサイドバー | サイドバー＋1ペイン。詳細はプッシュまたはシート。狭いiPadにも同じ規則 |
| 1024以上 | 232ptサイドバー | ブラウズは一覧＋詳細、編集は入力＋プレビュー、統計は2列、ホームは学習＋カレンダー |
| 高さ500未満の横向き | 学習時はナビゲーションを省略 | カード左・回答右。問題文は独立してスクロール |

Penpotの各ボードは幅ごとの状態を表す。ネイティブFlexレイアウト、左右・下端の制約、F02の折り返し可能なFlex見本を付与しているが、**Penpot自体にCSSのメディアクエリによる条件分岐はない**。切り替えの動作はHTMLプロトタイプで検証し、アプリではウインドウ幅から同じ規則を実装する。

### iPadで共通の詳細画面を開く場合

M系の設定・確認・読み込み画面は、iPadでも同じ情報と操作を維持する。通常の詳細設定は最大640ptのフォーム、短い操作メニューは起点を持つpopover、同期の置き換え・削除・復元は最大560ptの確認sheetにする。iPadの主要画面はI系に別設計済み。M系へのPenpotリンクは共通画面の参照を兼ねる。ネイティブiPad上でのpopover配置やページをまたぐPenpot Viewモードの遷移は実機検証していない。

## 機能対応表

「全機能」はAnkiMobileの公開仕様を対象とする。PC専用のアドオン管理をiOSの機能として扱わない。細かな設定値や選択肢は実装時に利用するAnki互換エンジンのバージョンと照合する。

| 機能 | 画面 |
| --- | --- |
| デッキ階層、新規・学習・復習の件数、学習開始 | M01–M02、I01–I02 |
| デッキ作成、名称、移動、サブデッキ、説明、削除 | M27、M43、M44 |
| 問題・解答、4段階評価、次回間隔、取り消し | M03–M05、I03、I03A |
| 入力式解答、音声、TTS、全画面、ズーム | M03T、M21、M21B、M39 |
| タップ9領域、上下左右スワイプ、シェイク | M21、M22 |
| キーボード、ゲームパッド、ユーザーアクション1–8 | M23、M12 |
| 手書きメモ、Pencilのみ、位置・サイズ・消去 | M38、I08 |
| 学習中の編集、フラグ、マーク、埋める、停止 | M37、M37A |
| ノート単位の操作、マークして埋める／停止 | M37A、M44 |
| カード情報、学習履歴、期限指定、新規化、位置変更 | M41 |
| 検索構文、条件、保存検索、表示列、並び順 | M06–M07、I04、R05 |
| 複数選択、デッキ変更、タグ、タイプ変更、停止 | M08、M08A |
| 基本・逆方向・穴埋め・画像穴埋め | M09–M11、M13、M40 |
| フィールド、順序、書体、入力方向、保持、HTML | M13F |
| 書式、色、上／下付き、MathJax、HTML編集 | M09–M12、M42 |
| カメラ、写真、録音、ファイル、iPadで描画添付 | M39、I06 |
| カードテンプレート、CSS、JS、プレビュー | M12、I06 |
| 統計の対象デッキ・期間・コレクション | M14–M19、I05、I07 |
| 回答数、時間、日次カレンダー、カード構成 | M14、M17、M18 |
| 復習予測、期限超過の分離、1日あたりの負荷 | M15 |
| 回答ボタン内訳、実測定着率、成熟・未成熟 | M16 |
| 復習間隔、易しさ、安定性、難易度、想起確率 | M17、M19、I07 |
| 時間帯別・学習時間の統計 | M18 |
| 新規・復習の上限、プリセット・デッキ・今日だけ | M30 |
| FSRS、保持率、最適化、評価、再スケジュール | M31、M31P |
| FSRS最大間隔、履歴除外、簡単な日、負荷試算 | M31、M31P |
| 新規・再学習ステップ、Leech、旧方式の間隔 | M32 |
| 新規・復習の取得順と表示順、兄弟カード | M32O |
| 自動送り、問題・解答時間、音声待ち、タイマー | M32A |
| 上限を増やす、忘れたカード、先取り、プレビュー | M33 |
| フィルターデッキ、検索、上限、順序、再構築・空にする | M34 |
| AnkiWebログイン、通常同期、メディア同期 | M24、M25、M24P |
| 一方向同期、どちらを残すか、置き換え確認 | M26、M26C |
| オフライン・再試行・ローカル変更の保持 | M48 |
| APKG、COLPKG、CSV・TSV、列の対応 | M27、M28、M28T |
| 学習履歴・メディアを含む書き出し、共有・AirDrop | M28E |
| 共有デッキの発見とAnkiWebへの導線 | M29 |
| 複数プロフィールと別々の同期アカウント | M35 |
| 自動バックアップ、復元、復元前確認 | M36、M36R |
| DB整合性、未使用タグ、欠損／未使用メディア | M36D、M36M |
| 通知、日付境界、先取り、言語、画像サイズ | M21G |
| ダーク・文字サイズ・アクセシビリティ | M45、M46、R06 |
| URL Scheme、Shortcuts、辞書、カスタムフォント | M42 |
| 初期状態、エラー、削除確認 | M47、M48、M44 |

細分化される選択肢（上限を親デッキから適用、新規が復習上限を無視、旧方式の間隔補正など）はM30/M32の設定グループ内で開く選択sheetとする。デッキの統計からは選択デッキを維持し、グラフの項目から同条件の検索へ遷移する。

## アクセシビリティと実装時の動作

- 主要タップ領域は44pt以上。アイコンだけの操作にも読み上げ名を付ける。プロトタイプの可視ボタンは44px以上で確認。
- 正答・難易度・新規の色に、必ず文字ラベルを併記する。統計には数値・凡例・読み上げ用の説明を付ける。
- Dynamic Typeではラベルを折り返し、KPIは縦積み、回答は2×2または縦並びへ。R06は大きな文字の別設計。
- キーボード表示中は編集中フィールドまでスクロールし、書式バーをキーボード上に置く。保存はナビゲーションに残し、下部タブは隠す。入力内容を失わず閉じられる。
- ポインタ・キーボードフォーカスを明示。Spaceで解答、1–4で評価、⌘Zで取り消し、⌘F/⌘Nをネイティブ実装に割り当てる。HTMLはSpace/1–4のデモを実装。
- VoiceOverはナビゲーション→ページ見出し→内容→主要操作の順。Reduce Motionはアニメーションを省略、Reduce Transparencyは不透明な背景へ置換。
- iOS / iPadOS 17以上を実装の基準とし、新しいOSのマテリアルは利用可能性を判定して使用する。静止画ではLiquid Glassの動的な屈折やネイティブキーボードの挙動は検証できない。

## 参照とアセット

公式仕様とAppleのリソースを2026-10-06に確認。機能名・分類は公式仕様を基に独自に再構成し、UIやアイコンを新規作成した。

- [AnkiMobile Manual](https://docs.ankimobile.net/) — [Deck List](https://docs.ankimobile.net/deck-list.html)、[Study Tools](https://docs.ankimobile.net/study-tools.html)、[Adding & Editing](https://docs.ankimobile.net/editing.html)、[Preferences](https://docs.ankimobile.net/preferences.html)
- [Anki Statistics](https://docs.ankiweb.net/stats.html)、[Deck Options](https://docs.ankiweb.net/deck-options.html)、[Editing / Image Occlusion](https://docs.ankiweb.net/editing.html)
- [Sync](https://docs.ankimobile.net/syncing.html)、[Collection Transfer](https://docs.ankimobile.net/collection-transfer.html)、[Shared Decks](https://docs.ankimobile.net/shared-decks.html)、[TTS](https://docs.ankimobile.net/tts.html)、[URL Schemes](https://docs.ankimobile.net/url-schemes.html)
- [Apple Design Resources](https://developer.apple.com/design/resources/) — 確認時の掲載はiOS / iPadOS 27、SF Symbols 27。公式キットの移植ではなく、ネイティブ向けの独自コンポーネント。Appleのフォント・キットのバイナリは配布していない。
- Penpot書体は既に利用可能だった **Noto Sans JP**。生成SVGのローカル代替はNoto Sans CJK JP。出荷アプリはシステムフォントを使う。フォント本体は追加・再配布していない。
- アイコンは `build.py` のオリジナルSVGパス。実装では `rectangle.stack`、`magnifyingglass`、`chart.bar`、`gearshape` などの対応するSF Symbolsとネイティブコントロールへ割り当てる。

## 検証記録

`validation.json` に幅別の検証結果を保存。Penpot構造の検証エラー0件、テキストのはみ出し0件、リンク切れ0件を確認。主要6画面×9幅（320〜1366px）に横方向のオーバーフローなし。744/1024pxの前後も確認した。横向き844×390、回答の表示と評価、検索、編集プレビュー、保存デモも確認。

Penpot Viewモードのクリック検証、実機でのVoiceOver・Pencil・ネイティブマテリアルの検証は未実施。Penpotの遷移はAPIでの参照整合性を確認し、操作フローの実動作はHTMLプレビューで検証した。
