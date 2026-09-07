---
id: TASK-19
title: 新規セッションが、生成中も本来のプロジェクトグループに表示されるようにする
status: To Do
assignee: []
created_date: '2026-09-07 08:22'
labels: []
dependencies: []
ordinal: 19000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Navigator で n / f / N から新規セッションを作ると、行がいったん unknown グループ(最下部)に現れ、数秒後に本来のプロジェクトグループへ跳ぶ。セッションの所属ディレクトリは Claude の transcript から導出しているが、claude 起動直後は transcript がまだ書かれておらず導出できないため。ユーザーから見ると『作ったセッションがどこに行ったか分からず、目で追っていると突然移動する』状態で、作成直後のいちばん注意を向けている瞬間に一覧が信用できなくなる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 新規作成した行が、最初の描画から本来のプロジェクトグループに出る(unknown を経由しない)
- [ ] #2 transcript がまだ無い起動直後のセッションは、確立済みのセッションと区別できる状態として表示される
- [ ] #3 transcript が現れた後は、従来どおり transcript から導出した情報が使われる
- [ ] #4 launch_dir を持たない既存のメタデータファイルが、従来どおり読める
<!-- AC:END -->
