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

読み込んだコレクションは変換せずにそのまま使うため、ノートタイプ・デッキオプション・学習履歴がすべて保たれます。

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
