# Fork セッションの自動検出とネスト表示 — 設計

**日付**: 2026-07-24
**ブランチ**: feature/unread-state (作業は新ブランチへ)
**対象**: Claude Code 2.1.218 の `/fork` 新仕様

## 背景と問題

Claude Code の `/fork`(および `--fork-session`)の挙動が変わった。実際に
`--fork-session` を走らせて transcript を解剖し、以下を実証確認した:

- fork は **新しい sessionId + 新しい transcript ファイル** を作る。
- 親のメッセージを **`uuid` ごとコピー** し、各行の `sessionId` を fork の ID に
  書き換える。(実測: fork `5c878742` の先頭 8 メッセージの uuid が親
  `64c519ad` と一致、sessionId は全行 fork 側)
- `forkedFrom:{sessionId,messageUuid}` はバイナリ内に存在するが **jsonl には
  永続化されない**(メモリ内変換のみ)。
- `~/.claude/sessions/<pid>.json` に fork 固有フィールドは無い。`kind:"bg"` は
  Task ツールの背景エージェント(`jobId`/`agent` 付き)であり fork ではない。

現行 Tower は `count_unregistered_processes_in_dir` でディレクトリ内の未登録
live プロセス数を数え、プロジェクトヘッダに `⚡N` と出すだけ。**どの既存
セッションの分岐なのか(親子関係)を一切表示していない。** 新仕様では親子
リンクを transcript から復元できる(共有 uuid プレフィックス)ので、これを
使って「この fork はどのセッションから分かれたか」を正確に表示する。

## 検出シグナル(唯一の on-disk 手段)

同じプロジェクトディレクトリ内で、**先頭メッセージの `uuid` が別の(より古い)
transcript と共有されている transcript = fork**。共有相手が親、後から作られた
方が fork。

- **なぜ uuid 共有か**: `forkedFrom` は jsonl に残らないため使えない。fork は
  親メッセージを uuid ごとコピーするので、これが唯一残る痕跡。
- **compaction 誤検出の回避**: compaction は同一 sessionId 内でファイルを
  分けず、cross-file の uuid 共有を起こさない。fork だけが起こす。

## アーキテクチャ

登録セッションの列挙(`list_all_sessions`)は変更しない。fork の検出と表示は
`lib/claude-sessions.sh`(検出)と `navigator-list.sh`(表示)に閉じる。

### コンポーネント 1: 検出 (`lib/claude-sessions.sh`)

**`find_fork_parent <child_session_id>` → 親 Claude sessionId / 1**

- 子 transcript の先頭 N 行(N=5)の `uuid` を集合として取得。
- 同一プロジェクトディレクトリ内の他 `*.jsonl` を、mtime が子より **古い** もの
  だけ走査。先頭 N 行の uuid が子の集合と 1 つでも一致すれば親候補。
- 複数候補があれば mtime が子に最も近い(=直近の親)ものを返す。
- 何も無ければ 1 を返す。
- 依存: `find_session_jsonl`, `get_session_cwd`(dir 特定)。
- 性能: 各ファイル先頭 N 行のみ。全 uuid は読まない。

**`list_fork_sessions <dir>` → `<child_sid>\t<parent_sid>\t<pid>` 行**

- `list_live_claude_processes` を引き、cwd == dir かつ未登録
  (`has_metadata tower_<sid>` が false)なプロセスを対象。
- 各 sid に `find_fork_parent` を適用し、親が取れたものだけ出力。親が
  取れない未登録プロセスは出力しない(=従来の `⚡N` フォールバックに残る)。

### コンポーネント 2: 表示 (`navigator-list.sh`)

グループ組み立てループ(現 282–290 行付近)で、各メンバー行を出した直後に
その sid を親とする fork を `list_fork_sessions` の結果から探して挿入する。

- fork 行の見た目: `↳` プレフィクス + 既存 `◇`(NAV_C_EXTERNAL)+
  `get_session_title` のタイトル + 右カラムに `⚡`。
- fork 行は選択可能。SESSION_IDS には fork の Claude sessionId をそのまま
  (tower_ 無しで)積み、選択時の resume は既存 external resume 経路を再利用
  して fork の sessionId に対して `--resume` する。
- **親が Tower 未登録のとき**: ネストできないため、そのグループ末尾に `↳`
  無しの単独 `◇` external 行として出す(情報を落とさない)。
- 親が見つからない未登録 live プロセスは従来どおり `⚡N` ヘッダ集計に残す
  (挙動後退なし)。

### 境界とエラー処理

- 子 transcript が消えている/読めない → スキップ。
- 循環・多段 fork: 親探索は **1 ホップのみ**。fork の fork は各々の直近の親に
  付く(親も fork 行なら、その親行の下にネストするのではなく、登録済み祖先
  グループ内で最も近い表示行の下、という深追いはしない — v1 スコープ外)。
- fork が既に Tower に登録済み(ユーザーが add 済み)なら通常の `tower_*` 行
  として既に出るので、`list_fork_sessions` の未登録フィルタで自然に除外。

## テスト (bats)

`tests/test_fork_detection.bats`(新規):

- fixture: 本日生成した parent/fork ペアをサニタイズして
  `tests/scenarios/` に配置(親 transcript, fork transcript)。
- `find_fork_parent` が fork に対して親 sid を返す。
- 通常の独立セッション(uuid 非共有)では 1 を返す。
- compaction ペア(同一 sessionId、cross-file uuid 共有なし)では 1 を返す。
- `list_fork_sessions` が未登録 fork のみ列挙し、登録済みは除外する
  (`has_metadata` をスタブ)。

## スコープ外 (YAGNI)

- 多段 fork のツリー表示(1 ホップのみ)。
- fork の親子を跨いだ diff / マージ支援。
- `forkedFrom` を jsonl から読む経路(永続化されないため不可能)。
