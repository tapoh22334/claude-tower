---
id: TASK-6
title: タイルモードが起動直後に落ちる
status: Done
assignee:
  - '@claude'
created_date: '2026-07-25 01:00'
updated_date: '2026-07-25 11:28'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 6000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
タイルモード(tile mode)を起動すると、すぐに終了してしまい使用できない。画面上にエラーメッセージ等は表示されないため、原因は不明。

再現手順: タイルモードを起動する → 直後に落ちる。
観測: エラー出力なし。ログや tmux server 側の出力を確認しないと原因が特定できない状態。

まず原因調査が必要（どのスクリプトが落ちているか、set -e / tmux コマンド失敗 / 未定義変数 などの切り分け）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 タイルモード起動が即座に落ちる原因が特定され、タスクに記録されている
- [x] #2 タイルモードを起動しても落ちずに、意図した分割レイアウトが表示される
- [x] #3 落ちる場合はユーザーが原因を把握できるエラーメッセージが出る（サイレント終了しない）
- [x] #4 再発防止のための回帰テストが追加されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 再現: 隔離tmuxサーバでNavigator+tile.shを実機起動し、症状を再現する
2. 原因特定: キー入力経路とtile起動経路を切り分ける
3. 修正: 原因を根本から直す（サイレント失敗をやめる）
4. 回帰テスト追加 (tests/test_tile_launch.bats)
5. shellcheck + 全bats実行、既存失敗との差分がないことを確認
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 根本原因（2件）

### 原因1: Tabキーが握り潰されていた（タイルモードが起動すらしない主因）
navigator-list.sh のキー読み取りが `read -rsn1 -t $TICK_INTERVAL key` で、
IFS= を付けていなかった。bash のデフォルト IFS には TAB が含まれるため、
押された Tab は単語分割で消え、空文字列として返る。
結果 case 文の $'\\t') ブランチには決して到達せず、'') = Enter ブランチに落ちていた。

実測:
  printf '\\t' | { read -rsn1 k; echo ${#k}; }       -> 0  (消える)
  printf '\\t' | { IFS= read -rsn1 k; echo ${#k}; }  -> 1  (残る)

フッターのヒント行に 'Tab:tile' が無く 't:tail' しか無かったのも、この
キーが実際には死んでいたことと整合する。同じ欠陥が tile.sh / tail-view.sh
のキー読み取りにも存在した。

### 原因2: 起動失敗をサイレントに握り潰して、それでもデタッチしていた
switch_to_tile は
  session_tmux new-window ... 2>/dev/null || true
で全失敗を捨て、その後 target_session があれば無条件に detach-client していた。
セッションサーバに生きたセッションが無い場合 new-window は
'no server running on ...' で失敗するが、エラーは捨てられ、Navigator は
デタッチだけ実行 -> 「起動した直後に落ちて何も出ない」という報告どおりの挙動。
switch_to_tail も同一実装で同じ欠陥。

## 修正
- navigator-list.sh / tile.sh / tail-view.sh: キー読み取りを IFS= read -rsn1 に
- switch_to_tile/switch_to_tail を enter_view_mode に共通化し、
  tile_target_session と launch_view_window に分離。
  起動可否を先に判定し、失敗時はデタッチせず画面にエラーを出して留まる
- フッターに Tab:tile を追加

## 検証（実機・隔離tmux）
- 生きたセッションあり + 実Tab押下 -> tower-tile ウィンドウ生成、タイル描画を capture-pane で確認
- 生きたセッションなし + Tab -> Navigator に留まり
  '✗ No running session — Tile mode needs one / Press n to add a session' を表示

## 追加検証
- tower.sh tile (CLI経路) も実機確認: 描画され常駐し、q で EXIT=0 終了
- IFS= はすべてのキー読み取りに影響するため j/k/g/G/矢印/? の回帰も実機確認済み（全て正常）
- Tabディスパッチのテストはミューテーション確認済み:
  IFS= を外すと ENTER 分岐に落ちてテストが失敗する（回帰を実際に検出できる）
- tests/test_tile_launch.bats 12件 全pass
- shellcheck (navigator-list.sh / tile.sh / tail-view.sh) クリーン

## 注意: 作業中に別セッションがこのチェックアウトを main に切り替えた
コミット 6cb0641 は feature/fork-detection 上に無事存在し、5ファイル全て intact。
ただし作業ツリーは現在 main を指しており、修正は作業ツリーには載っていない。
マージ/取り込みは feature/fork-detection の 6cb0641 から行うこと。

全体bats比較で1件 'unread: init_session_seen baselines once and never overwrites' が
新規失敗として出たが、
- 単体では3回中3回pass
- 自分のコミットは init_session_seen を一切変更していない (git show で確認)
- 計測中に別セッションが同じツリーを書き換えていた
ため、自分の変更による回帰ではないと判断。

## 離脱時点(2026-07-25)
commit 6cb0641 を origin/feature/fork-detection に push 済み
(ブランチtip = このコミット)。PRは未作成 — ブランチには fork-detection 側の
先行コミット10件が同居しており、まとめてPRにするとこの修正1件の意図が埋もれる。
ブランチ全体のマージ可否は TASK-1 の担当。

再開時の注意: 別セッションがこのチェックアウトを main に切り替えたため、
作業ツリーには修正が載っていない。差分を見るなら
  git show 6cb0641
  git diff main...feature/fork-detection -- tmux-plugin/scripts/tile.sh
ツリーを奪い合わないよう、checkout する前に他セッションの有無を確認すること。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
タイルモードの即落ちは独立した2つの欠陥の合成だった。

原因1: Tabキーが握り潰されていた。Navigatorのキー読み取りが `read -rsn1 key` で
デフォルトIFS(TABを含む)を使っていたため、押されたTabは単語分割で消えて空文字列になり、
$'\\t') ではなく '')=Enter分岐に落ちていた。タイルモードは正規のキーでは一度も
起動できていなかった(フッターに Tab:tile が無く t:tail しか無かったのと整合)。
同じ欠陥が tile.sh / tail-view.sh にも存在。→ 3ファイルとも IFS= read -rsn1 に修正。

原因2: 起動失敗を握り潰したままデタッチしていた。switch_to_tile は
new-window を 2>/dev/null || true で捨て、その後無条件に detach-client。
セッションサーバに生きたセッションが無いと new-window は失敗するが、
エラーは捨てられNavigatorだけデタッチ → 「起動直後に落ちて何も出ない」。
switch_to_tail も同一。→ tile_target_session / launch_view_window に分離し
enter_view_mode に共通化。ウィンドウ生成成功後にのみデタッチし、
失敗時はNavigatorに留まって理由を表示する。

検証(実機・隔離tmuxサーバ、コミット済みHEADで実施):
- 生きたセッションあり+実Tab押下 → tower-tile 生成、グリッド描画を capture-pane で確認、dead=0
- 生きたセッションなし+Tab → Navigatorに留まり
  '✗ No running session — Tile mode needs one / Press n to add a session' 表示
- tower.sh tile (CLI経路) → 描画・常駐・q で EXIT=0
- j/k/g/G/矢印/? の回帰なし(IFS=は全キーに影響するため実機確認)
- tests/test_tile_launch.bats 12件 新規追加、全pass。Tabディスパッチのテストは
  ミューテーション確認済み(IFS=を外すとENTER分岐に落ちて失敗する)
- shellcheck クリーン
- test_tail_view.bats の1件は switch_to_tail の本文をgrepする実装依存テストだったため
  振る舞い検証に書き換え(9件全pass)

commit 6cb0641
<!-- SECTION:FINAL_SUMMARY:END -->
