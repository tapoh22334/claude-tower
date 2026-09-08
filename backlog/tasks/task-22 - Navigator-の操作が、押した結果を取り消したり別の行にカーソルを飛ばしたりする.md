---
id: TASK-22
title: Navigator の操作が、押した結果を取り消したり別の行にカーソルを飛ばしたりする
status: Done
assignee: []
created_date: '2026-09-07 12:14'
updated_date: '2026-09-07 12:14'
labels: []
dependencies: []
ordinal: 22000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
D を押すと行がすぐ消えるが数秒後に復活し、また消える。n/f/N で作ったセッションは一覧に現れず、さらにカーソルが無関係な先頭行へ飛ぶ。r は押しても数秒間なにも起きない。

いずれも「操作の結果を即座に反映し、それを取り消さない」という規則が一部の操作にしか適用されていなかったことが原因。TASK-18 が非同期化と引き換えに残した負債で、AC#2(古いキャッシュを表示しない)を未達のまま Done にしていた箇所にあたる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 D で消した行が復活しない
- [ ] #2 n/f/N で作ったセッションが即座に一覧に現れ、カーソルがそこに留まる
- [ ] #3 r が即座に状態を返す
- [ ] #4 サブフロー復帰の作法(入力フラッシュ・幅キャッシュ)が全ハンドラで揃っている
- [ ] #5 README と設計書が starting/deleting を含む実際の状態を記述している
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
世代カウンタで解決。楽観更新のたびに世代を上げ、リビルドは開始時の世代が current のときだけ publish する。世代はファイルに置く — リビルドは fork したサブシェルなので、変数だと親のバンプが見えず、それこそが塞ぎたいレースだったため。

n/f/N は _remember_session_row で新規行を starting(◐) として即座に配列へ入れる。これがないと get_selection_index が新 ID を見つけられず not-found の既定値 0 を返し、カーソルが先頭行へ飛んでいた。r は _mark_session_starting で同様に即応。

サブフロー復帰は _return_from_subflow に一本化(入力ドレイン→echo→幅キャッシュ)。従来は r が入力フラッシュを欠き、? が幅キャッシュを落としていなかった。

仕様は DR-005 として DESIGN_PHILOSOPHY.md に記録。README の状態表に starting/deleting を追加し、busy がアニメーションである旨と Escape が右ペインの話である旨を明記。設計書にだけ存在した a(フルアタッチ)キーは仕様倒れとして削除。

テスト: 新規10件追加、586 pass。既存の失敗2件(_session_label / build_session_list スピナー)は変更前から落ちている baseline で、今回の回帰ではない。
<!-- SECTION:NOTES:END -->
