---
id: TASK-8
title: セッションタイトルに Claude のコマンド展開マークアップが漏れる
status: Done
assignee:
  - '@claude'
created_date: '2026-07-25 03:38'
updated_date: '2026-07-25 03:49'
labels:
  - fork-detection
  - navigator
dependencies: []
priority: high
type: bug
ordinal: 8000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
get_session_title が Claude のスラッシュコマンド展開をそのまま行に出すことがある。fork したセッションは親の会話を引き継ぐが新しい sessionId を持つため history.jsonl に自分名義のプロンプトが無く、transcript にフォールバックする。fork の最初の user メッセージは Claude が展開したコマンド (<command-message>...</command-name><command-args>...) なので、マークアップが Navigator の行に生で表示される。

さらに履歴側も弾きすぎている: _first_meaningful_sentence は '/' 始まりを一律棄却するため、'/brainstorming ボードサイズが…' のように引数へ本文が入っている場合でも、一番良いタイトルを捨てて transcript へ落ちる。

同種の混入として <local-command-caveat> の定型文もある。

修正は feature/fork-detection の 409b378 に実装済み・検証済み (当時の全 transcript 走査で混入ゼロ)。main には未反映。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Navigator の行に command-message / command-args / local-command-caveat のマークアップが一切表示されない
- [x] #2 履歴が全てスラッシュコマンドの場合、引数本文がタイトルとして採用される (例: '/brainstorming XをY したい' -> 'XをY したい')
- [x] #3 引数なしのスラッシュコマンド (/init) は従来どおり棄却され、実プロンプトが優先される既存挙動が変わらない
- [x] #4 ローカル全 transcript の走査でマークアップ混入がゼロ
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 409b378 (feature/fork-detection) の claude-sessions.sh 差分のうち、タイトル生成部分のみを main に移植する。main では find_session_jsonl が別途書き換わっているため cherry-pick ではなく該当ロジックのみ手で適用する。
2. _strip_command_markup: <command-args> は中身へアンラップ / command-message・command-name は要素ごと破棄 / <local-command-caveat> は要素を除去し後続本文を残す。
3. _slash_command_argument: 履歴が全てスラッシュコマンドの場合の最後の手段として引数を抽出。既存の walk-forward 優先は変更しない。
4. get_session_title の 3 経路 (履歴・最後の手段・transcript フォールバック) 全てでマークアップ除去を通す。
5. 回帰テスト 7 件を tests/test_list_readability.bats に移植。
6. 全 transcript 走査でマークアップ混入ゼロを再検証 + make test の失敗数がベースラインから増えないことを確認。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: main の ba34b56。feature/fork-detection の 409b378 と同等だが、main では find_session_jsonl が別途書き換わっているため cherry-pick せずタイトル生成部分のみ手で移植した。

検証エビデンス:
- bats tests/test_list_readability.bats: 22/22 pass (新規回帰テスト 6 件を含む)
- 全 transcript 走査: get_session_title のフォールバック経路を生の transcript 553 件に対して実行し、command-message / command-args / command-name / local-command-caveat の混入 0 件
- make test の失敗数: 修正あり 20 / 修正なし 20 (git stash で比較) → 新規失敗なし。20 件は未追跡の test_coverage_gaps_*.bats 等に起因する既存failure
- shellcheck -e SC2034,SC1091,SC2317: clean

判断: _first_meaningful_sentence の '/' 一律棄却は変更せず、最後の手段として引数抽出を追加した。既存テスト (rejects bare slash commands) が /fork do the thing の棄却を意図的に assert しており、そこを緩めると walk-forward 優先の設計判断ごと壊れるため。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
get_session_title が Claude のコマンド展開マークアップをそのまま表示行に出す不具合を修正 (main: ba34b56)。_strip_command_markup を追加し、タイトル生成の全経路 (履歴・最後の手段・transcript フォールバック) でマークアップを除去。あわせて履歴が全てスラッシュコマンドの場合に引数本文をタイトルとして採用する _slash_command_argument を追加した。検証: bats 22/22 pass、生 transcript 553 件へフォールバック経路を実行してマークアップ混入 0 件、make test の失敗数は既存ベースライン 20 から増加なし、shellcheck clean。
<!-- SECTION:FINAL_SUMMARY:END -->
