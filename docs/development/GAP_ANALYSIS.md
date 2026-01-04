# 仕様書と実装の差分分析

> **ARCHIVED**: This document is historical. All gaps have been resolved.
> Current version: SPECIFICATION.md v3.2, PSEUDOCODE.md v3.2

Date: 2026-01-02 (Updated: 2026-01-04)
Based on: SPECIFICATION.md v3.2, PSEUDOCODE.md v3.2

**Status: 完了・アーカイブ** - 全 Phase 完了。v3.2への更新も完了。

---

## 1. ファイル名の不一致 ✅ 完了

| 仕様書 | 現在の実装 | アクション |
|--------|-----------|-----------|
| `navigator-view.sh` | ~~`navigator-preview.sh`~~ → `navigator-view.sh` | ✅ 完了 |
| `view-focus.conf` | ~~`inner-tmux.conf`~~ → `view-focus.conf` | ✅ 完了 |

---

## 2. 用語の不一致 ✅ 完了

### 2.1 フォーカス状態

| 仕様書 | 現在の実装 | 影響箇所 |
|--------|-----------|---------|
| `"view"` | ~~`"preview"`~~ → `"view"` | ✅ 完了 |

**修正済みファイル:**
- ✅ `tmux-plugin/lib/common.sh` - コメントを `"view"` に統一
- ✅ `tmux-plugin/scripts/navigator-list.sh` - `focus_view()` に関数名変更、`"view"` を使用
- ✅ テストファイル全て (`preview` → `view` に更新)

### 2.2 セッション状態 ✅ 完了

| 仕様書 | 実装 | 状態 |
|--------|------|------|
| `active` | `active` | ✅ 一致 |
| `exited` | `exited` | ✅ 一致 |
| `dormant` | `dormant` | ✅ 一致 |

**実施済み:**
- `running/idle` を `active` に統合（common.sh）
- テストを更新（test_navigator.bats, test_display_snapshot.bats）

---

## 3. 機能の差分

### 3.1 仕様書にあって実装にない ✅ 完了

| 機能 | 仕様書セクション | 優先度 | 状態 |
|------|----------------|--------|------|
| インラインセッション作成 | 4.7 create_session | HIGH | ✅ 完了 |

**修正済み:**
- ✅ `navigator-list.sh` の `create_session_inline()` でインライン入力を実装
- ✅ popup 方式を廃止
- ✅ 名前入力 + worktree 選択をインラインで実行

### 3.2 実装にあって仕様書にない ✅ 解決済み

| 機能 | 対応 | 状態 |
|------|------|------|
| Tile view (`Tab` key) | 仕様書に追加 (v3.1) | ✅ 完了 |
| Running/Idle 状態分離 | `active` に統合 | ✅ 完了 |

---

## 4. キーバインドの差分

### 4.1 Navigator (focus: list)

| キー | 仕様書 | 実装 | 状態 |
|------|--------|------|------|
| `j` / `↓` | 次を選択 | ✅ | 一致 |
| `k` / `↑` | 前を選択 | ✅ | 一致 |
| `g` | 最初を選択 | ✅ | 一致 |
| `G` | 最後を選択 | ✅ | 一致 |
| `Enter` | Full Attach | ✅ | 一致 |
| `i` | focus:view | ✅ | 一致（用語のみ要修正） |
| `n` | 新規セッション | ✅ | インライン実装に統一 |
| `d` | 削除 | ✅ | 一致 |
| `R` | Claude再起動 | ✅ | 一致 |
| `Tab` | Tile view | ✅ | 仕様書に追加 (v3.1) |
| `q` | 終了 | ✅ | 一致 |
| `?` | ヘルプ | ✅ | 一致 |

### 4.2 Navigator (focus: view)

| キー | 仕様書 | 実装 | 状態 |
|------|--------|------|------|
| `Escape` | focus:list に戻る | ✅ | 一致 |
| その他 | セッションに送信 | ✅ | 一致 |

---

## 5. 状態ファイルの差分 ✅ 完了

| ファイル | 仕様書 | 実装 | 状態 |
|----------|--------|------|------|
| `/tmp/claude-tower/caller` | ✅ | ✅ | 一致 |
| `/tmp/claude-tower/selected` | ✅ | ✅ | 一致 |
| `/tmp/claude-tower/focus` | `"list"` or `"view"` | `"list"` or `"view"` | ✅ 一致 |

---

## 6. 修正計画

### Phase 1: 用語統一（破壊的変更なし） ✅ 完了

1. ✅ **common.sh** - コメントを `view` に統一
2. ✅ **navigator-list.sh** - `focus_view()` に変更
3. ✅ **ファイルリネーム** - `navigator-view.sh`, `view-focus.conf`
4. ✅ **テスト修正** - 全テストで `preview` → `view`

### Phase 2: インラインセッション作成 ✅ 完了

1. ✅ **navigator-list.sh** - `create_session_inline()` を実装

### Phase 3: 仕様書・実装統合 ✅ 完了

1. **SPECIFICATION.md v3.1**
   - ✅ セッション状態を3状態に統合 (`active`, `exited`, `dormant`)
   - ✅ Tile view を正式に追加 (`Tab` キー)
   - ✅ tile_view のキーバインド定義

2. **実装の調整**
   - ✅ `common.sh`: `running/idle` を `active` に統合
   - ✅ `navigator-list.sh`: `T` → `Tab` に変更
   - ✅ `tile.sh`: Full Attach 削除、list_view 復帰動作を実装
   - ✅ テストを更新

---

## 7. 推奨アクション優先順位

| 優先度 | アクション | 影響範囲 | 状態 |
|--------|-----------|---------|------|
| 1 | ファイルリネーム + 参照更新 | 小 | ✅ 完了 |
| 2 | フォーカス用語統一 (`preview` → `view`) | 小 | ✅ 完了 |
| 3 | インラインセッション作成の実装 | 中 | ✅ 完了 |
| 4 | セッション状態統合 (`running/idle` → `active`) | 中 | ✅ 完了 |
| 5 | Tile view 正式化 (`Tab` キー、仕様書追加) | 中 | ✅ 完了 |

---

## 8. テスト観点

全項目検証済み:

1. ✅ **Navigator起動**: `prefix + t, c` でNavigatorが表示される
2. ✅ **セッション選択**: `j/k` で選択が移動し、view paneが更新される
3. ✅ **フォーカス切替**: `i` でview paneに入力可能、`Escape` で戻る
4. ✅ **Full Attach**: `Enter` でNavigatorを離れてセッションにアタッチ
5. ✅ **終了**: `q` でcallerに戻る
6. ✅ **セッション作成**: `n` でインライン入力からセッション作成
7. ✅ **Tile view**: `Tab` でtile_viewに切替、1-9/Enter/Tab でlist_viewに戻る
8. ✅ **セッション状態**: 3状態 (active, exited, dormant) で正常表示

---

## 9. 完了サマリー

**実施内容**:
- SPECIFICATION.md v3.0 → v3.1 に更新
- セッション状態を4状態から3状態に簡略化
- Tile view を正式な機能として仕様書に追加
- 実装とテストを仕様書に合わせて更新

**テスト結果**: 171/175 (97.7% - 4件スキップ)
