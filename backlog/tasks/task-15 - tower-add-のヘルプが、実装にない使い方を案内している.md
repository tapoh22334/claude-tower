---
id: TASK-15
title: tower add のヘルプが、実装にない使い方を案内している
status: Done
assignee: []
created_date: '2026-08-04 13:36'
updated_date: '2026-08-29 16:40'
labels:
  - bug
  - cli
dependencies: []
ordinal: 15000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
tower CLI のヘルプ (tmux-plugin/scripts/tower:24, :31-35) は次を謳っている:

  tower add <path> [-n name]
  tower add .
  tower add /path/to/project
  tower add . -n my-project

しかし session-add.sh の引数ループ (:15-26) が解釈するのは --print-id / --fork-dir <dir> / --new-in-dir の 3 つだけ。tower は 'exec session-add.sh "$@"' で丸投げする (tower:51) ため、'.' も '/path/to/project' も '-n my-project' も黙って捨てられ、対話ピッカーが開く。

つまりヘルプ通りに打った人は「パスを指定したのにピッカーが出る」という挙動に遭う。エラーも警告も出ないので、無視されたことにすら気づけない。

どちらかに寄せる必要がある:
(a) session-add.sh に位置引数と -n を実装し、ヘルプ通りに動くようにする。CLI としてはこちらが本来の姿で、Navigator を開かずに登録できる価値がある
(b) ヘルプを実装に合わせて 'tower add' (引数なし) だけに削る

README は今回の書き直しで (b) 相当の記述にし、'takes no path or name yet, despite what its own --help suggests' と注記した。ヘルプ側が直れば README のその注記も外せる。
<!-- SECTION:DESCRIPTION:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
session-add.sh に位置引数と -n/--name を実装し、tower --help が最初から案内していた 'tower add <path> [-n name]' が実際に動くようにした。従来はパスも名前も黙って捨てられピッカーが開いていた。不明なオプションもエラーにした。検証: tower add <dir> -n my-alias --print-id でセッションが作られ session_name=my-alias がレジストリに記録されることを実機確認、回帰テスト5件を追加。
<!-- SECTION:FINAL_SUMMARY:END -->
