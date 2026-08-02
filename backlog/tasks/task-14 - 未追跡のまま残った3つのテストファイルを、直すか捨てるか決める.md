---
id: TASK-14
title: 未追跡のまま残った3つのテストファイルを、直すか捨てるか決める
status: To Do
assignee: []
created_date: '2026-08-02 07:54'
labels:
  - test
dependencies: []
ordinal: 14000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
リポジトリ整理の際、未追跡だった bats ファイル6件のうち3件は通ったのでコミットしたが、残り3件は現状では入れられないと判断して退避した。中身には価値があるので、直して入れるか捨てるかを決める必要がある。

退避先: /tmp/claude-1000/-home-iwase-working-claude-tower/4a9ad97c-0372-4d1e-af7f-3d3f717ba861/scratchpad/ (セッション用の一時領域なので、扱うなら早めに)

test_coverage_gaps_11.bats — 19件中17件が失敗。原因は自己完結していて直せる: setup() が source_common を呼んで TOWER_DEBUG を readonly にした後、source_tile_functions() が tile.sh を読み、その22行目が common.sh を再び source して 'readonly variable' で落ちる。ファイル内の sed ヘルパーは main は削るが common.sh の source 行は削っていない。tile.sh の関数群 (対象) は実在するので、sed を直すか setup() から source_common を外せば生きる。

test_coverage_gaps_7.bats — 19件中8件が TODO 本体の skip で、ファイル自身が 'skeletons: fill in the TODO bodies before relying on them' と書いている。実際に走る11件のうち、session-delete.sh/session-restore.sh の引数検証は test_coverage_gaps_6.bats と、classify_error/try_with_retry は今回コミットした test_error_recovery.bats と重複する。重複しない実テストは render_list 系3件と get_selection_index 系2件。この5件だけ救って残りを捨てるのが妥当。

test_coverage_gaps_10.bats — 10件中3件がそもそも実行されず終了 (exit 127)。run bash -c "... | resolve_picked_id ..." が新しい bash を起動するため source した関数が見えない。resolve_picked_id 自体は session-add.sh:105 に実在するので、declare -f で渡すかプロセス内パイプにすれば直る。走る7件のうち3件も失敗し、うち --json の空配列テストは環境を隔離しておらず開発機の実セッションを拾うため CI でも不安定になる。残り2件は 'documents known gap' と名乗り、現在の挙動を推測で書いて外している。救えるのは save_metadata 2件と add_existing_session のみ。

判断材料: 公開リポジトリの CI は現在 main で赤い (TASK-12)。失敗するテストや TODO 骨組みを足すと状況が悪化するため、今回は入れなかった。
<!-- SECTION:DESCRIPTION:END -->
