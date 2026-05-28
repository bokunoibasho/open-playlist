# Vendor Notes

`Vendor/Brave/` 配下に取り込んだ Brave 由来コードの出所を記録する（DESIGN.md §4）。
取り込みは upstream を merge せず、必要なファイルだけを手動 / cherry-pick で反映する。

- Upstream: `brave/brave-core`（現行コードは `src/brave/ios/brave-ios` 配下）
- 旧 `brave/brave-ios` は 2024-05 にアーカイブ済み（read-only。参照のみ）
- 取り込んだファイルは元の MPL-2.0 ヘッダを保持する

## 取り込み履歴

| 取り込み日 | upstream commit | 取り込んだパス | 反映先 (Vendor/Brave/) | 備考 |
|-----------|-----------------|---------------|------------------------|------|
| 2026-05-28 | `fd18de0d8c4338e9c880eb4f9929b71a1673b4f9` (master) | `ios/brave-ios/Sources/Brave/Frontend/UserContent/UserScripts/Scripts_Dynamic/Scripts/Paged/PlaylistScript.js` | `UserScripts/PlaylistScript.js` | verbatim。stream 検出本体 |
| 2026-05-28 | `fd18de0d8c4338e9c880eb4f9929b71a1673b4f9` (master) | `…/Scripts_Dynamic/Scripts/Paged/PlaylistSwizzlerScript.js` | `UserScripts/PlaylistSwizzlerScript.js` | verbatim。MediaSource を無効化し progressive src を露出 |

### Phase 3 での適用メモ
- `PlaylistScript.js` は Brave の `window.__firefox__`（`includeOnce`/`$`/`$.postNativeMessage`）と `$<...>` プレースホルダ・`SECURITY_TOKEN` に依存する。Brave 本体の bootstrap UserScript は取り込まず、`UserScriptMediaDetector` が最小シムを自前注入し、プレースホルダ／トークン置換を Swift 側で行う（`PlaylistScriptHandler.swift` の `secureScript` 相当）。
- 参考にした Swift 受け口: `…/Scripts_Dynamic/ScriptHandlers/Paged/PlaylistScriptHandler.swift`（移植はせず payload 仕様の参照のみ）。
- 注入条件は Brave 踏襲: `injectionTime = .atDocumentStart`, `forMainFrameOnly = false`, `WKContentWorld = .page`。
