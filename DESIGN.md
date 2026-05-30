# open-playlist — 設計ドキュメント

> Brave iOS の Playlist 機能を切り出し、YouTube 等から曲を追加できる
> 「iOS ミュージックアプリ風」の再生アプリを作る。
> リポジトリ名: **open-playlist** ／ ライセンス: **MPL-2.0**。
> このドキュメントは Claude Code への実装引き継ぎ資料。

---

## 1. ゴールとコンセプト

Web（主に YouTube）で見つけた動画を「曲」として Playlist に追加し、
Apple Music / iOS ミュージックアプリのように再生するアプリ。

- 追加は **アプリ内蔵の簡易ブラウザ**（WKWebView）で行う。
- 再生は **ネイティブ AVPlayer**。WebView 内再生ではない。
  これによりロック画面・コントロールセンター・バックグラウンド再生・PiP が実現できる。
- stream URL 抽出は **Brave の UserScript 方式を踏襲**する。
- **Chromium は使わない。WebKit ベースで完結**させる。
- オフライン用に **ダウンロード（保存）** も可能にする。

---

## 2. スコープ

### やること
- WKWebView による簡易ブラウザ（URL バー / 戻る・進む / 再読み込み）
- UserScript による stream URL 捕捉（YouTube 含む）
- Playlist の作成・並べ替え・削除（videoID + メタデータを保存）
- AVPlayer によるバックグラウンド再生 + ロック画面 / コントロールセンター連携
- Picture in Picture
- ダウンロード（オフライン保存）した曲のローカル再生
  - ※ ライブのストリーム再生は廃止し、**再生はダウンロード済みのみ**とする（Issue #16/#21）。
    短命な stream URL の再生直前再解決は不安定でクラッシュ要因だったため。

### やらないこと（少なくとも初期は）
- Chromium / brave-core の取り込み（UserScript と Swift の Playlist 周辺のみ）
- App Store 配布前提の設計（個人 / 学習用途。配布は別途検討）
- iCloud 同期（Brave 本体でも未実装。将来の拡張候補として保留）

---

## 3. アーキテクチャ概要

レイヤー構成（依存は上→下の一方向）。

```
┌─────────────────────────────────────────────┐
│  UI 層 (SwiftUI 主体)                          │
│   - ライブラリ/Playlist 画面                    │
│   - Now Playing / プレイヤー画面                │
│   - 簡易ブラウザ画面 (WKWebView を UIKit でラップ) │
├─────────────────────────────────────────────┤
│  ドメイン層                                     │
│   - PlaylistStore (作成/並べ替え/永続化)         │
│   - PlaybackController (再生キュー/状態管理)      │
├─────────────────────────────────────────────┤
│  サービス層                                     │
│   - StreamResolver (protocol)                  │
│       └ UserScriptStreamResolver (Brave 踏襲)   │
│   - MediaDownloader (オフライン保存)            │
│   - NowPlayingService (MPNowPlayingInfoCenter / │
│                        MPRemoteCommandCenter)   │
├─────────────────────────────────────────────┤
│  Vendor/Brave/ (隔離・ベンダリング)             │
│   - Playlist*.js (UserScript)                  │
│   - 移植した Swift の最小セット                  │
└─────────────────────────────────────────────┘
```

ポイント: **stream 解決処理は `StreamResolver` プロトコルで抽象化**する。
初期実装は UserScript 方式 1 本だが、将来別方式（純 Swift 抽出など）に
差し替えられるようにしておく。

---

## 4. リポジトリ構成と upstream 追従戦略

完全フォーク + 不要コード削除は **避ける**。削除したファイルを upstream が
更新するたびに delete/modify コンフリクトが頻発し、長期メンテが破綻するため。

代わりに **隔離ベンダリング方式**:

```
open-playlist/                 # 自分のクリーンなリポジトリ
├── App/                       # 自作コード（UI / ドメイン / サービス）
├── Vendor/
│   └── Brave/                 # Brave から持ってきたコードを隔離
│       ├── UserScripts/       # Playlist*.js（最重要・追従対象）
│       └── Swift/             # 移植した最小限の Swift
├── DESIGN.md
└── VENDOR_NOTES.md            # 取り込み元 commit / 取り込み日を記録
```

### 追従の運用
1. Brave の upstream を git remote として追加（参照のみ、merge はしない）。
   - 現行コードは `brave-core` 内の `src/brave/ios/brave-ios` 配下。
   - 旧 `brave-ios` リポジトリは 2024-05 にアーカイブ済み（read-only）。
2. 追従して価値が高いのは **UserScript（YouTube 仕様変更対応）**。
   Swift 側は大改修が稀なので全追従しない。
3. 該当パスの diff を定期的に確認し、必要分だけ手動 / cherry-pick で `Vendor/Brave/` に反映。
4. 反映ごとに `VENDOR_NOTES.md` に取り込み元 commit を記録する。

> 境界（Vendor ディレクトリ）を切ることで、自作コードと混ざらず diff 適用が楽になる。

### ライセンス
プロジェクト全体を **MPL-2.0（確定）** とする。Brave 由来ファイルは元々 MPL-2.0 なので
MPL ヘッダを保持したまま `Vendor/Brave/` 内に隔離すれば衝突なく流用できる。
MPL はファイル単位の弱いコピーレフトで「コピーレフトにしたい / MIT は避けたい」を満たし、
かつ GPL と違い App Store 配布と衝突しない（将来の配布も視野に入れやすい）。

---

## 5. データモデル

**stream URL は保存しない**（YouTube の stream URL は署名付き・短命で失効するため）。
保存するのは videoID とメタデータ。stream URL は **ダウンロード時にのみ** resolver で解決し、
以後の再生は保存したローカルファイル（`localFileURL`）からのみ行う。
再生直前のライブ再解決は廃止した（短命 URL に依存し不安定だったため。Issue #16/#21）。

```swift
struct Track: Identifiable, Codable {
    let id: UUID
    let sourceURL: URL        // 元ページ URL (例: youtube.com/watch?v=...)
    let providerID: String?   // 例: YouTube videoID（再解決のキー）
    var title: String
    var author: String?
    var durationSeconds: Double?
    var thumbnailURL: URL?
    var localFileURL: URL?    // ダウンロード済みなら設定（オフライン再生用）
    var dateAdded: Date
}

struct Playlist: Identifiable, Codable {
    let id: UUID
    var name: String
    var trackIDs: [UUID]      // 並べ替え可能
}
```

永続化: **SwiftData（確定）**。
データモデルが単純（Track と Playlist の 1 関係のみ）なので、SwiftData が苦手な
複雑クエリ・細かいマイグレーション制御に当たらず、SwiftUI（`@Query`）と自然に統合できる。
最小 iOS 26 前提なので成熟度も問題なし。Core Data は今回オーバースペック。

---

## 6. 主要コンポーネント

### 6.1 簡易ブラウザ (WKWebView)
- URL バー、戻る / 進む / リロード、ローディング表示。
- `WKWebViewConfiguration.userContentController` に Playlist の UserScript を注入。
- 動画ページで stream を検出したら「＋ 追加」ボタンを活性化（Brave のアドレスバー音符アイコン相当）。

### 6.2 StreamResolver（UserScript 方式・Brave 踏襲）
```swift
protocol StreamResolver {
    /// ページ内のメディアから再生可能な stream を検出
    func detectStreams(in webView: WKWebView) async throws -> [DetectedStream]
    /// 保存済み Track の stream URL を再解決（再生直前に呼ぶ）
    func resolve(_ track: Track) async throws -> URL
}
```
- `Vendor/Brave/UserScripts/Playlist.js` / `PlaylistSwizzler.js` を注入し、
  `WKScriptMessageHandler` で抽出結果（src / title / duration 等）を Swift に渡す。
- Brave の UserScript は security token を埋め込む前提。切り出し時は
  `$<security_token>` 系の置換ロジックも一緒に移植するか、トークン無しに簡略化する。

### 6.3 PlaybackController + Player
- 単一 `AVPlayer` + 自前キューで再生キューを管理。
- **ダウンロード済みのローカルファイルのみ再生**（resolver 依存なし）。キューはダウンロード済みの
  曲だけで構成し、自動送り / 次へ / 前へが未ダウンロード曲で止まらないようにする。
- 再生前に `AVURLAsset` で再生可否（`isPlayable` + 音声/映像トラックの有無）を検証。壊れたファイルは
  破棄して再ダウンロードを促す。
- `AVAudioSession` を `.playback` カテゴリで設定。

### 6.4 NowPlayingService
- `MPNowPlayingInfoCenter`: タイトル / アーティスト / アートワーク / 再生位置。
- `MPRemoteCommandCenter`: 再生・停止・次・前・シーク（ロック画面 / コントロールセンター / イヤホン操作）。

### 6.5 PiP
- 映像付き再生時は `AVPictureInPictureController`。
- 音声のみ用途が主なので、PiP は「映像も見たいとき」のオプション扱いで可。

### 6.6 MediaDownloader（オフライン保存）
- progressive（mp4/m4a 直リンク）: `URLSession` のダウンロードタスク。
- HLS（m3u8）: `AVAssetDownloadURLSession`（HLS 資産のオフライン化用）。
- 保存後は `Track.localFileURL` を設定し、以後は再解決不要。

---

## 7. プラットフォーム設定

- **Background Modes**: `Audio, AirPlay, and Picture in Picture` を有効化
  （Info.plist の `UIBackgroundModes` に `audio`）。
- `AVAudioSession` を `.playback` で有効化（バックグラウンド継続再生に必須）。
- 最小 iOS: **26**（個人利用 / 開発者デバイスが iOS 26+。最新 AVKit / SwiftData / PiP API をフル活用）。
- 端末の WKWebView を使用（Chromium 不要）。

---

## 8. Brave から移植する対象（着手時に実体を確認）

`brave-core` の development ブランチ、`src/brave/ios/brave-ios` 配下を clone して特定する。

- UserScripts（**SwiftPM ターゲットの `resources: [.copy(...)]` でバンドル済み**。取り込み後は `Bundle.module` 経由でロード）:
  - `Frontend/UserContent/UserScripts/.../Playlist.js`, `PlaylistSwizzler.js`
  - `.../Scripts_Dynamic/Scripts/DomainSpecific/Paged/PlaylistFolderSharingScript.js`
  - `DomainSpecific` 配下のサイト別スクリプト（YouTube 等）→ YouTube 以外対応の要
  - ※ 旧 `Client/Frontend/.../UserScripts/Playlist.js` は旧 brave-ios の構造。現行は上記パス。
- Swift（参考・最小移植）:
  - PlaylistItem 相当のデータモデル
  - VideoPlayer / プレイヤー UI（再生 UI の参考。SwiftUI で作り直すなら参照のみ）
  - stream 検出と WKScriptMessageHandler 連携部分

> 全部を持ってこない。UserScript と「stream 検出 → Swift 受け渡し」のロジックが核心。

---

## 9. 実装フェーズ（マイルストーン）

> **リリース運用**: **Phase N = `v0.N.0`** に対応させる。Phase 1〜4 はリリース済み
> （`v0.1.0`〜`v0.4.0`、Issue #7 のパッチが `v0.4.1`）。Phase 5 は本ブランチで実装。
> 公開済みタグ・コミットメッセージは履歴として書き換えない（Phase 0 を `v0.1.0` で
> 開始した経緯で、過去の注釈には旧番号が残る）。

- **Phase 1**（`v0.1.0` 済）: Xcode プロジェクト雛形、Background Modes / AVAudioSession 設定、リポジトリ構成。
- **Phase 2**（`v0.2.0` 済）: WKWebView 簡易ブラウザ（URL バー・ナビゲーション）。
- **Phase 3**（`v0.3.0` 済）: Brave UserScript を `Vendor/Brave/` に移植・注入。stream 検出結果を画面に表示。
- **Phase 4**（`v0.4.0` 済）: データモデル + PlaylistStore（追加・並べ替え・永続化）。
- **Phase 5**（`v0.5.0`）: AVPlayer 再生 + NowPlayingService（バックグラウンド・ロック画面）。
  保存済み Track の stream URL はオフスクリーン WKWebView で UserScript を再実行して再生直前に
  再解決（`StreamResolver` / `UserScriptStreamResolver`）。単一 AVPlayer + 自前キューで都度解決。
  ミニプレイヤー + 全画面 Now Playing。
- **Phase 6**（`v0.6.0`）: PiP 対応。映像付きストリーム再生時に Now Playing へ実映像を表示し、
  `AVPictureInPictureController` + `AVPlayerLayer` で PiP を起動（手動ボタン + バックグラウンド自動移行）。
  音声のみの曲はサムネ表示にフォールバック。
- **Phase 7**: MediaDownloader（オフライン保存）。progressive（mp4/m4a）を `URLSession` で取得し
  `Track.localFileURL` を設定。ダウンロード結果は HTTP ステータス / MIME（webm・HLS・text 等は拒否）/
  非空 / `AVAsset` 再生可否で検証する。
  - **方針転換（Issue #16）**: 再生直前のライブ再解決は短命 URL に依存し不安定だったため、
    PR#18 を機に **再生はダウンロード済みのみ**へ転換し、ライブ再生は廃止。
  - **クラッシュ修正（Issue #21）**: Now Playing 情報の更新（`MPNowPlayingInfoCenter`）が
    バックグラウンド `Task` の継続（アートワーク取得や再生準備の `await` 後）からメインスレッド外で
    実行され `_dispatch_assert_queue_fail` でクラッシュしていた。該当 `Task` を明示的に
    `@MainActor` 化してメインアクターへホップさせて解消。
- **Phase 8**（`v0.8.0`）: ミュージックアプリ風 UI 仕上げ。Apple Music 風の Now Playing
  （ぼかしアートワーク背景 + 再生/一時停止で拡縮する正方形アートワーク + 細いスクラバー +
  シャッフル/リピート）、ミニプレイヤーの進捗ライン、ライブラリ/プレイリストの
  アートワーク表示と再生/シャッフルヘッダー。アセットカタログ（アクセント色 +
  アプリアイコン）を追加（Issue #4）。`Track.author` を YouTube oEmbed で取得し
  アーティスト行を表示（Issue #26）。再生はダウンロード済みのみの方針は維持。

---

## 10. Claude Code 最初のタスク

1. Phase 1: Xcode プロジェクト作成、Background Modes 有効化、リポジトリ構成
   （`App/` と `Vendor/Brave/` の骨組み、`VENDOR_NOTES.md`）。
2. `brave-core` を clone し、`src/brave/ios/brave-ios` 配下から
   Playlist UserScript と stream 検出ロジックを特定 → `Vendor/Brave/` に取り込み。
3. Phase 2: WKWebView の簡易ブラウザを動かす。
4. Phase 3: UserScript を注入し、YouTube ページで stream 検出ログが出る所まで。

---

## 11. 注意点・リスク

- **stream URL は短命**。Track には保存せず、ダウンロード時にのみ解決する。再生直前のライブ再解決は
  不安定（クラッシュ要因）だったため廃止し、再生はダウンロード済みのローカルファイルのみとする（Issue #16/#21）。
- **MediaPlayer / AVPlayer はメインアクター専用**。`MPNowPlayingInfoCenter` の更新はメインキュー上で
  行う必要があり、違反すると `_dispatch_assert_queue_fail` でクラッシュする。バックグラウンドの
  `Task` 継続（`await` 後）から触れる場合は closure を明示的に `Task { @MainActor in … }` として
  メインアクターへ確実にホップさせる（**継承された isolation だけに頼らない**。Issue #21 の原因）。
  `MPRemoteCommandCenter` ハンドラや AVKit/KVO コールバックも非メインで呼ばれ得るため
  `MainActor.assumeIsolated` は使わない。
- **YouTube は仕様変更が頻繁**。UserScript が壊れることがある → upstream の UserScript 追従が保守の肝。
- **利用規約 / 配布**: YouTube の ToS はストリーム抽出を制限。個人 / 学習用途は範囲内だが、
  App Store 配布は「YouTube ダウンローダー」と見なされリジェクト対象になり得る。配布は別途検討。
- ダウンロード機能があると失効問題は回避できるが、規約面の留意は同じ。
