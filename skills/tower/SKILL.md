---
name: tower
description: >-
  Claude セッションの中から claude-tower を操作する。利用者が「このセッションの
  名前を○○にして」「これは foo プロジェクトで続けよう」「新しいプロジェクト bar を
  始めたい」のように言ったとき、`tower rename` / `tower open` / `tower project new`
  を非対話で呼び、結果の id を報告する。トリガー: セッション名 / 名前を変えて /
  rename / ○○で続けて / 別プロジェクトで / 移動して / 新しいプロジェクト /
  リポジトリを作って / project new / tower。Navigator のキー操作の代わりに使う。
---

# tower — セッションの中から Tower を動かす

Tower の Navigator は外から眺める道具で、セッションの中からは何も言えなかった。
この 3 コマンドはその口。すべて `tower` CLI(`$CLAUDE_TOWER_DIR/scripts/tower.sh`、
通常は `~/.tmux/plugins/claude-tower/tmux-plugin/scripts/tower.sh`)のサブコマンドで、
確認プロンプトを出さず、成功時は**対象セッションの id を stdout に 1 行**だけ出す。
人向けの文言は stderr。

```bash
TOWER="${CLAUDE_TOWER_DIR:-$HOME/.tmux/plugins/claude-tower/tmux-plugin}/scripts/tower.sh"
```

## 意図 → コマンド

| 利用者の言い方(例) | 意図 | 実行するもの |
|---|---|---|
| 「このセッションの名前を payments 移行にして」「名前変えて」 | **名前を変える** | `$TOWER rename "payments 移行"` |
| 「名前を戻して」「名前消して」 | 名前を外す | `$TOWER rename --clear` |
| 「これは foo で続けよう」「foo プロジェクトに移って」「別プロジェクトでやろう」 | **別プロジェクトで続ける** | 要約を書いて `$TOWER open <dir> --prompt-file -` に流す |
| 「新しいプロジェクト bar を始めたい」「bar というリポジトリを作って」 | **新しいプロジェクトを始める** | `$TOWER project new bar [--prompt-file -]` |

- `rename` は **今いるセッション**が対象になる(`TMUX_PANE` から解決)。Tower の
  pane の外で動いているときだけ `--session <id>` が要る(id は `tower list`)。
- `open` の `<dir>` は既存ディレクトリ。利用者が名前しか言わないときは
  `~/working/<name>` を候補にして `ls -d` で実在を確かめてから渡す。無ければ
  「新しいプロジェクトを始める」の意図かを一言で確認する(これは判断が分かれる
  ので聞いてよい)。
- `project new` の親は既定で `~/working`。別の場所は `--in <parent>`。GitHub 上の
  リポジトリは作らない(利用者が `gh repo create` する)。

## 引き継ぎ要約の型(open / project new の `--prompt`)

新セッションの Claude は元の会話を知らない。次の 4 項目を、元セッションの
Claude(あなた)が書く。長さの目安は 10〜25 行。

```
目的: <新セッションで何を達成するか。1〜2 行>
決めたこと:
- <この会話で確定した判断。却下した案もあれば 1 行で>
次にやること:
1. <最初の一手>
2. <その次>
参照ファイル:
- <パス>: <何が書いてあるか>
```

- 「決めたこと」には**理由**を添える。新セッションが同じ議論をやり直さないため。
- 利用者がまだ決めていないことは「未決:」として書き、勝手に決めない。
- 要約は stdin で渡す(`--prompt-file -`)。引用符や `$` を含んでも壊れない。

```bash
cat <<'EOF' | "$TOWER" open ~/working/foo --prompt-file -
目的: foo の API 設計を始める
決めたこと:
- REST(GraphQL は利用者が 1 人なので過剰と判断)
次にやること:
1. docs/api.md にエンドポイント一覧の案を書く
参照ファイル:
- ~/notes/foo-idea.md: 元セッションで出たアイデアのメモ
EOF
```

## 結果の報告

1. stdout の id(`tower_<uuid>`)を受け取る。
2. 利用者に 1〜2 行で伝える: 何をしたか、Navigator のどこに現れるか。
   - rename: 「Navigator の行名は次の再描画(数秒)で変わります」
   - open / project new: 「Navigator の選択は新セッションに移っています。
     元のこのセッションはそのまま残ります」
3. 終了コード 2 は使い方の誤り(名前が空、Tower の外、不正なプロジェクト名)、
   1 は実行時の失敗(ディレクトリが無い、既に存在、git init 失敗)。stderr の
   文言をそのまま見せ、こちらで直せる指定(パスの打ち間違い等)は直して 1 回だけ
   やり直す。

## やらないこと

- `tmux rename-session`(Tower のセッション名 `tower_<uuid>` を壊す)
- 元のセッションを閉じる・休眠にする(open は作って選択を移すだけ)
- 利用者の代わりにプロジェクトの中身(CLAUDE.md、Issue 管理)を初期化すること
