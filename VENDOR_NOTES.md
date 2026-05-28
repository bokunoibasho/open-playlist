# Vendor Notes

`Vendor/Brave/` 配下に取り込んだ Brave 由来コードの出所を記録する（DESIGN.md §4）。
取り込みは upstream を merge せず、必要なファイルだけを手動 / cherry-pick で反映する。

- Upstream: `brave/brave-core`（現行コードは `src/brave/ios/brave-ios` 配下）
- 旧 `brave/brave-ios` は 2024-05 にアーカイブ済み（read-only。参照のみ）
- 取り込んだファイルは元の MPL-2.0 ヘッダを保持する

## 取り込み履歴

| 取り込み日 | upstream commit | 取り込んだパス | 反映先 (Vendor/Brave/) | 備考 |
|-----------|-----------------|---------------|------------------------|------|
| –         | –               | –             | –                      | Phase 2 で記入 |
