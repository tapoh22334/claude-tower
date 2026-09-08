---
id: TASK-20
title: 削除中のセッションが、消えるまで一覧に残って見えるようにする
status: Done
assignee: []
created_date: '2026-09-07 08:22'
updated_date: '2026-09-07 08:39'
labels: []
dependencies: []
ordinal: 20000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Navigator で D を押して削除すると、確認ボックスが一覧の上に描画された直後に行が消え、カーソルが別のセッションへ移り、view ペインが更新される、が同時に起きる。ユーザーには『何が起きたのか』の手がかりが残らず、削除が効いたのか誤操作で別セッションを触ったのかが一瞬わからない。削除処理そのものは同期的なので、状態が見えないことだけが実害。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 削除の実行中、対象の行が削除中と分かる形で一覧に残る
- [ ] #2 削除に成功したときだけ行が一覧から消える
- [ ] #3 削除に失敗したときは行が元の状態に戻り、一覧から消えない
<!-- AC:END -->
