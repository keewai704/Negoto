# Negoto

iPhone と iPad（Split View・Stage Manager の可変ウィンドウを含む）に対応した、Anki 互換の単語帳アプリです。
Anki のデッキファイルをそのまま読み込み、Anki と同じ見た目・同じスケジュールで学習できます。

## 対応している Anki ファイル

| 形式 | 中身 | 由来 |
| --- | --- | --- |
| `.apkg`（最新形式） | `collection.anki21b`（zstd 圧縮・スキーマ18）+ protobuf のメディア表 + zstd 圧縮メディア | Anki 2.1.50 以降の既定 |
| `.apkg`（互換形式） | `collection.anki21`（スキーマ11）+ JSON のメディア表 | 「旧バージョンと互換」で書き出したもの |
| `.apkg`（Anki 2.0 形式） | `collection.anki2`（スキーマ11・v1 スケジューラ） | Anki 2.0、genanki など |
| `.colpkg` | コレクション全体（上記いずれかの形式） | 「コレクションを書き出す」 |
| `.anki2` / `.anki21` / `.anki21b` | コレクションファイル単体 | |

アプリが持つコレクションは常に 1 つです。

- `.apkg` を読み込むと、Anki と同じようにその中身をコレクションに**統合**します。すでにあるノート（同じ GUID）は重複して追加しません。ノートタイプ・デッキ・デッキオプション・学習の進み具合・復習履歴も引き継ぎます。
- `.colpkg` などコレクション全体のファイルは、「今のデッキと統合する」か「置き換える」かを選べます。
- 同じ名前で中身の違うメディアファイルは、自動で別名に変えて取り込みます。
- 旧バージョン（1.0.6 以前）でデッキごとに分かれていたコレクションは、起動時に自動で 1 つにまとめます。

### 画面構成

デザインは「Adaptive iOS/iPadOS Flashcards」を元にしています。落ち着いたティール（青緑）をアクセントに、カードやリストは不透明な面、Liquid Glass はナビゲーション層（タブバー・サイドバー・学習画面のヘッダーとツールバー）にだけ使っています。iOS 17〜18 では同じ部分をすりガラス（Material）で表示します。

レイアウトは端末の種類ではなく**ウィンドウの実際の幅**で決まります（境界で行ったり来たりしないよう ±16pt の余裕つき）。

| 幅 | レイアウト | 例 |
| --- | --- | --- |
| 600pt 未満 (Compact) | 1 列 + 下のタブバー（デッキ・ブラウズ・統計・設定・検索） | iPhone 縦、iPad の小さいウィンドウ |
| 600〜1023pt (Medium) | タブ + 一覧と詳細の 2 列 | iPad 縦・Split View、iPhone 横 |
| 1024pt 以上 (Wide) | サイドバー（ライブラリ・デッキ・タグ）+ 一覧 + 詳細の 3 列 | iPad 横・フルスクリーン |

- **デッキ**: 「今日の学習」カード（残り枚数・所要時間の目安・新規/学習中/復習・進み具合）と、デッキの一覧（件数バッジつき、並べ替え可）。デッキの詳細では件数、学習を始める・カスタム学習・オプション、今後 7 日間の予測、デッキ情報（平均保持率・成熟カード・未学習・一時停止）を表示します
- **学習画面**: カードは読みやすい最大幅 680pt の面に表示し、上にガラスのヘッダー（残り件数、iPad では取り消し・フラグ・カード情報）。「答えを表示」はカードをタップしても OK。回答ボタンは次回の間隔つきで、「もう一度」と「難しい」の間だけ広めに空けています。iPad ではカード情報（次回の間隔・復習回数・ラプス・安定度・難易度・履歴・タグ）をインスペクタに表示。iPhone の横向きでは回答ボタンを右に 2×2 で並べます
- **カードの追加・編集**: ノートタイプとデッキを選び、太字・斜体・下線・穴埋め（`{{c1::…}}`）・画像の挿入、タグ、表/裏のプレビュー。追加・編集・削除したカードも iCloud で同期されます
- **ブラウズ**: Anki の検索式（`deck:` `tag:` `is:due` `is:new` `prop:ivl>=10` `rated:7:1` `added:3` `フィールド名:値` `-` 否定、`or` など）と、デッキ・状態・タグ・並び順のチップ。広い画面では表と編集パネル（自動保存）を並べて表示します
- **統計**: デッキと期間（1か月・3か月・1年・全期間）を選んで、今日・保持率・回答ボタンの使用割合・学習カレンダー（連続日数）・今後 7 日間・復習間隔の分布・カードの状態を、最小幅 320pt のカードのグリッドで表示
- **設定**: アカウントと同期、1 日の新規カード・最大復習数・目標保持率・回答ボタン（4 / 2 ボタン）、ハプティクス、次回間隔の表示、スワイプで回答、テーマなど

#### デザインから変えたところ

- アプリ名はデザイン上の仮称（Kioku）ではなく Negoto のままです
- 「フィルタデッキ」は Anki との互換性のため（読み込み時にカードを元のデッキへ戻しています）持たず、代わりに**カスタム学習**で「今日の上限を増やす」「苦手なカード」「最近忘れたカード」「先取り復習」を練習できるようにしました（練習では次回の復習日は変わりません）
- 学習画面のインスペクタの「メモ」は Anki のデータに存在しないため、ノートの「タグ」と「ノートを編集」に置き換えました
- 中間幅でデッキの件数を「復習数」だけにする案は、新規カードが見えなくなるため 3 つの件数をそのまま表示しています
- ダークモードのデッキ一覧の文字が薄すぎる部分は、通常の文字色に揃えてコントラストを確保しています
- 検索タブは「ブラウズ」と重複しないよう、デッキとカードをまとめて探す画面にしました

### カードの表示

Anki のテンプレートエンジン（rslib）を Swift に移植しています。

- `{{Field}}`、`{{#Field}}…{{/Field}}`、`{{^Field}}…{{/Field}}`、`{{FrontSide}}`、`{{Tags}}` `{{Deck}}` `{{Subdeck}}` `{{Card}}` `{{Type}}` `{{CardFlag}}`、旧形式の `{{=<% %>=}}`
- フィルタ: `text` `hint` `furigana` `kana` `kanji` `cloze` `cloze-only` `type` `type:cloze` `type:nc` `tts`
- クローズ削除（入れ子・ヒント・複数番号 `{{c1,2::…}}`・MathJax 内のクローズ・`{{#c1}}` 条件）
- 画像オクルージョン（Anki 23.10 以降の形式）
- 音声 `[sound:…]`（mp3 / m4a / wav / aac / flac / **ogg vorbis**）、動画（インライン再生）、TTS（`{{tts ja_JP:Field}}` を iOS の読み上げで再生）
- 数式: MathJax（`\(…\)` `\[…\]`、オフライン同梱）、LaTeX（パッケージ内の生成済み画像を使用し、無ければ MathJax で表示）
- 入力式（type-in）の解答比較、カード CSS・Web フォント・カード内 JavaScript、`.nightMode` / `.mobile` / `.iphone` / `.ipad` クラス
- メディアのファイル名は Unicode 正規化（NFC/NFD）・%エンコード・大文字小文字の違いを吸収して解決

### スケジューリング

- Anki v3 スケジューラの SM-2（学習ステップ・再学習・易しさ・ファズ・リーチ・1日の上限・親デッキの上限）
- FSRS（v4.5 / v5 / v6 のパラメータに対応、カードの記憶状態を引き継ぎ）
- 取り消し（Undo）、延期、保留、フラグ、日付の切り替え時刻（rollover）

実装の正しさは、公式 Anki ライブラリ（`pip install anki`）で生成した各形式のパッケージと、
Anki 自身が出力したレンダリング結果・次回間隔を正解データとして比較するテストで確認しています（`scripts/fixtures`）。

## インストール

[Releases](../../releases) から最新の `Negoto-x.y.z.ipa` をダウンロードしてください。
IPA は署名されていないため、[AltStore](https://altstore.io/) / [SideStore](https://sidestore.io/) /
[Sideloadly](https://sideloadly.io/) などでご自身の Apple ID で署名してインストールします。

デッキは次のいずれかの方法で読み込めます。

- アプリ右上のインポートボタン（ファイルアプリから選択、複数選択可）
- ファイルアプリやメール・Safari などで `.apkg` を開き「Negoto」を選ぶ
- ファイルアプリの「このiPhone内 › Negoto」フォルダに `.apkg` を置いてアプリを開く

## iCloud 同期

デッキ（メディアを含む）と学習の進み具合を、iPhone / iPad の間で同期します。
アプリは起動時に**自分の署名を読み取り**（`embedded.mobileprovision`）、使える方法を自動で選びます。

| 署名の方法 | 同期の方法 |
| --- | --- |
| iCloud を含むプロビジョニングプロファイル（有料の Apple Developer アカウント。下記の CI 署名、Xcode、Sideloadly など） | **iCloud コンテナ**を自動で使用。設定不要で、iCloud Drive に「Negoto」フォルダとして表示されます |
| 無料の Apple ID（AltStore / SideStore / Sideloadly）や iCloud 権限のない署名 | 設定 › 「iCloud 同期」で **iCloud Drive のフォルダを選択**（例: `iCloud Drive/Negoto`）。すべての端末で同じフォルダを選びます |

設定画面の「署名とiCloud」で、署名の種類・チーム・有効期限と、iCloud コンテナが使えるか（使えない場合はその理由）を確認できます。

- アプリの起動・復帰時、バックグラウンドへの移行時、学習の終了時、デッキの読み込み後に自動で同期します（設定でオフにできます）。デッキ一覧を下に引っ張るか、同期ボタンで手動でも同期できます。
- 各端末は自分専用の変更ファイル（`NegotoSync/collections/<ID>/changes/<端末ID>.json`）だけを書き込むため、iCloud 上でファイルの競合が起きません。
- 同じカードを複数の端末で学習した場合は、後から操作した方の状態が残ります。復習履歴はすべての端末の分が統合され、取り消し（Undo）も他の端末に反映されます。
- 学習オプション・デッキ名・FSRS の切り替えも同期されます。デッキの読み込みや削除をした端末は、共有のコレクションを新しく書き出します。他の端末はそれを受け取り、自分の学習記録を重ねて反映します。
- 複数の端末で同時にデッキを読み込んでも、両方の内容が残ります。同期を始める前から端末にあったデッキも、重複しないように統合されます。

### 署名済み IPA を CI で作る（任意）

リポジトリの Settings › Secrets and variables › Actions に次の 3 つを登録すると、CI が未署名 IPA に加えて
`Negoto-x.y.z-signed.ipa` を作り、Release に添付します。バンドル ID と iCloud コンテナはプロファイルから読み取ります。

| Secret | 内容 |
| --- | --- |
| `IOS_CERTIFICATE_P12` | 署名用証明書（.p12）を base64 にしたもの（`base64 -i cert.p12 | pbcopy`） |
| `IOS_CERTIFICATE_PASSWORD` | .p12 のパスワード |
| `IOS_PROVISIONING_PROFILE` | プロビジョニングプロファイル（.mobileprovision）を base64 にしたもの |

iCloud コンテナを使うには、Apple Developer でアプリ ID に iCloud（CloudKit / iCloud Documents）を有効にし、
コンテナ（例: `iCloud.<バンドルID>`）を割り当ててからプロファイルを作成してください。
Xcode でビルドする場合は、ビルド設定 `CODE_SIGN_ENTITLEMENTS` に `Negoto/Negoto.entitlements` を指定するか、iCloud capability を追加します。

## 開発

```
NegotoCore/        Swift Package（インポート・描画・スケジューラ。Linux でもテスト可能）
Negoto/            iOS アプリ（SwiftUI）
project.yml        XcodeGen のプロジェクト定義
scripts/fixtures/  公式 Anki でテスト用パッケージと正解データを生成するスクリプト
```

```sh
# コアのテスト（macOS / Linux）
swift test --package-path NegotoCore

# Xcode プロジェクトの生成
brew install xcodegen
xcodegen generate
open Negoto.xcodeproj
```

テスト用パッケージの再生成:

```sh
python -m venv venv && . venv/bin/activate && pip install anki genanki pillow
python scripts/fixtures/generate_fixtures.py
```

## CI/CD

`.github/workflows/ci.yml`:

1. Linux と macOS で `NegotoCore` のテスト
2. XcodeGen でプロジェクトを生成し、iOS 向けに Release ビルド → 未署名 IPA を作成
3. `main` への push では `v1.0.<ビルド番号>`、`v*` タグの push ではそのバージョンで GitHub Release を作成し IPA を添付

## ライセンスと謝辞

- [MathJax](https://www.mathjax.org/)（Apache License 2.0）
- [stb_vorbis](https://github.com/nothings/stb)（パブリックドメイン）
- [ZIPFoundation](https://github.com/weichsel/ZIPFoundation)（MIT）
- [zstd](https://github.com/facebook/zstd)（BSD）

Anki は Ankitects Pty Ltd の製品です。Negoto は Anki とは無関係の非公式アプリです。
