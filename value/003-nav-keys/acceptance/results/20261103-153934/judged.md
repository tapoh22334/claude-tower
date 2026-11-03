# 層 2: 実際の claude での複製の確認

基準(harness.md で実装前に固定): 複製の画面に元の会話の続きが出る。元の会話は変わらない。

手順: 使い捨てのディレクトリで、Tower の socket を使わずに claude 2.x を print モードで 2 回起動した。

1. `claude -p "Remember the secret word: kumquat. Reply only OK." --session-id <src>` → `OK`
2. `claude -p "What was the secret word? Reply with the word only." --resume <src> --fork-session --session-id <new>` → `kumquat`

結果:

- 複製は元の会話の内容を答えた。
- transcript は `<new>.jsonl`(43 行)に新しく書かれた。`<src>.jsonl` は 33 行のまま、複製の発話を含まない。
- `--resume` と `--session-id` の組み合わせは `--fork-session` を付ければ受け付けられる。

判定は合格である。対話モードでの見た目(画面に過去の会話が並ぶこと)は、同じ transcript を読むため同じ結果になると判断し、別には確かめていない。
