# Tower v2 設計哲学

## Tower の本質

> **複数の Claude Code セッションを行き来し、並行作業を効率的に管理・指示すること**

Tower は「セッション管理ツール」であり、それ以上でも以下でもない。

## 設計原則

### 1. 単一責任の原則

Tower の責務は **セッション管理のみ**：

| Tower がやること | Tower がやらないこと |
|-----------------|---------------------|
| セッションの作成（Claude 起動） | ディレクトリの作成 |
| セッションの一覧・切り替え | git worktree の作成・管理 |
| セッションの永続化（metadata） | ブランチの作成・削除 |
| セッションの削除 | ディレクトリの削除 |

### 2. ディレクトリは「参照」するだけ

セッション = 「あるディレクトリで動く Claude Code」

- ユーザーがディレクトリを用意する
- Tower はそのディレクトリを「参照」してセッションを作成
- セッション削除時、ディレクトリは一切触らない

```
ユーザーの責任: ディレクトリの用意と片付け
Tower の責任:   そのディレクトリでの Claude セッション管理
```

### 3. KISS (Keep It Simple, Stupid)

- タイプ分類は不要（[W]/[D]/[S] の区別を廃止）
- 全セッションが同じライフサイクル
- 挙動の統一による予測可能性

## 旧設計の問題点

### Worktree 機能の結合

旧設計では Tower が git worktree を作成・管理していた：

```
[W] Worktree セッション:
  - Tower が worktree 作成
  - Tower が branch 作成 (tower/<name>)
  - 削除時に worktree + branch も削除
```

これにより：

1. **責務の肥大化**: セッション管理 + ファイルシステム管理 + git 管理
2. **削除時の挙動の複雑化**: タイプによって削除されるものが異なる
3. **依存の増加**: git への依存が必須に
4. **エレガントでない**: シンプルな「セッション管理」から逸脱

### タイプ分類の曖昧さ

```
[W] Worktree = git worktree + 永続化
[S] Simple   = それ以外 + 非永続化
```

「永続化」と「worktree 作成」が結合しており、
「git repo を直接使う永続セッション」が作れなかった。

## 新設計の利点

### 1. シンプルさ

- タイプは1つだけ（全てのセッションが同じ）
- 削除の挙動が統一
- 予測可能な動作

### 2. 責務の明確化

```
Tower = セッション管理
git   = git 管理（ユーザーが行う）
```

### 3. 柔軟性

ユーザーは任意のディレクトリでセッションを作成できる：

- 通常のディレクトリ
- git リポジトリ
- 既存の git worktree
- 一時ディレクトリ

Tower はそれがどんなディレクトリかを気にしない。

## Worktree を使いたい場合

ユーザーが自分で管理する：

```bash
# worktree 作成
git worktree add ~/.worktrees/feature-x -b feature-x

# Tower でセッション追加
tower add ~/.worktrees/feature-x

# 作業...

# セッション削除
tower rm feature-x

# worktree 削除（ユーザーが行う）
git worktree remove ~/.worktrees/feature-x
```

Tower は worktree の存在を知らないし、知る必要もない。

## 将来の拡張

worktree 管理を便利にしたい場合は、Tower とは別の CLI ツールとして提供：

```bash
# Tower とは独立した worktree ヘルパー（将来検討）
git-wt add feature-x
git-wt remove feature-x
```

Tower のコア機能をシンプルに保ちつつ、必要に応じて外部ツールで補完する。
