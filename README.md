# open-playlist

**English | [日本語](#日本語)**

An iOS app that turns media you find on the web (YouTube and other sites) into a
personal music library you can play back like the native Music app — background
playback, lock‑screen controls, Picture in Picture, and offline downloads.

> ⚠️ Work in progress. A personal / learning project.

## Why

iOS browsers don't make it easy to turn web media into a proper, background‑playable
music library. Brave's iOS Playlist feature does, so **open-playlist** reuses that
approach — WebKit plus injected UserScripts to detect the media stream — in a small,
focused, music‑player‑style app. No Chromium; it's WebKit all the way down.

## Features (planned)

- Built‑in lightweight browser (WKWebView) to find and add media
- Save tracks into playlists; reorder and delete
- Background audio with lock‑screen / Control Center controls
- Picture in Picture
- Stream or download (offline) playback
- Works across sites, not just a single provider

## Tech

- Swift / SwiftUI, SwiftData
- WKWebView + UserScripts for stream detection
- AVFoundation (AVPlayer, Now Playing, Picture in Picture)
- iOS 26+

## Built on

Stream detection reuses Brave's iOS Playlist UserScripts, vendored under
`Vendor/Brave/` and kept under their original MPL‑2.0 headers. See
[`DESIGN.md`](./DESIGN.md) for the architecture and the upstream‑tracking strategy.

## License

[MPL‑2.0](./LICENSE). Chosen for compatibility with the vendored Brave code, and
because it is a copyleft license that — unlike GPL — does not conflict with App
Store distribution.

## Disclaimer

For personal / educational use. Extracting media streams from sites such as YouTube
may conflict with their Terms of Service; respect the terms of the sites you use.

---

# 日本語

**[English](#open-playlist) | 日本語**

Web 上（YouTube など）で見つけたメディアを、自分用の音楽ライブラリとして保存し、
iOS 純正のミュージックアプリのように再生する iOS アプリです。バックグラウンド再生、
ロック画面コントロール、Picture in Picture、オフライン保存に対応します。

> ⚠️ 開発中。個人 / 学習目的のプロジェクトです。

## なぜ作るのか

iOS のブラウザでは、Web のメディアを「バックグラウンド再生できるちゃんとした音楽
ライブラリ」に変えるのが簡単ではありません。Brave の iOS Playlist 機能はそれが
できるので、**open-playlist** はそのアプローチ（WebKit と、注入した UserScript で
メディアのストリームを検出する仕組み）を流用し、小さく音楽プレイヤーに特化した
アプリとして作り直します。Chromium は使わず、WebKit ベースで完結させます。

## 機能（予定）

- メディアを探して追加するための軽量な内蔵ブラウザ（WKWebView）
- トラックをプレイリストに保存・並べ替え・削除
- ロック画面 / コントロールセンター操作付きのバックグラウンド再生
- Picture in Picture
- ストリーム再生 / ダウンロード（オフライン）再生
- 単一サービスだけでなく、複数サイトに対応

## 技術

- Swift / SwiftUI, SwiftData
- ストリーム検出に WKWebView + UserScript
- AVFoundation（AVPlayer, Now Playing, Picture in Picture）
- iOS 26 以上

## ベース

ストリーム検出は Brave の iOS Playlist UserScript を流用し、`Vendor/Brave/` 配下に
隔離して取り込み、元の MPL‑2.0 ヘッダを保持します。アーキテクチャと upstream
追従戦略は [`DESIGN.md`](./DESIGN.md) を参照してください。

## ライセンス

[MPL‑2.0](./LICENSE)。取り込む Brave のコードと互換性があり、かつ GPL と違って
App Store 配布と衝突しないコピーレフトライセンスであるため、これを選びました。

## 免責

個人 / 教育目的での利用を想定しています。YouTube などのサイトからメディアの
ストリームを抽出する行為は、各サイトの利用規約に抵触する場合があります。利用する
サイトの規約を尊重してください。
