# Feature Specification: Claude Tower - セッション管理

**Feature Branch**: `001-tower-v2-simplify`
**Created**: 2026-02-05
**Status**: Draft
**Input**: User description: "Claude Tower: Claude Codeセッションの作成・削除・一覧表示をCLIとNavigatorで管理する。Towerはディレクトリを参照するだけで、ディレクトリの作成や管理は行わない。"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - CLIでセッションを追加する (Priority: P1)

ユーザーは任意のディレクトリを指定して、そのディレクトリでClaude Codeセッションを開始できる。Towerはディレクトリを「参照」するだけで、ディレクトリの作成や管理は行わない。

**Why this priority**: セッション作成は最も基本的な機能であり、Towerの設計哲学「ディレクトリは参照するだけ」を体現する中核機能。

**Independent Test**: `tower add /path/to/dir`コマンドを実行し、Navigatorでセッションが表示され、Claude Codeが起動していることを確認できる。

**Acceptance Scenarios**:

1. **Given** 存在するディレクトリがある, **When** `tower add /path/to/dir`を実行, **Then** セッションが作成されClaude Codeが起動する
2. **Given** セッションを追加したい, **When** `tower add . -n my-session`を実行, **Then** カレントディレクトリで指定名のセッションが作成される
3. **Given** 存在するディレクトリがある, **When** `tower add /path/to/dir`を実行, **Then** metadataが保存され、tmux再起動後も復元できる

---

### User Story 2 - CLIでセッションを削除する (Priority: P1)

ユーザーはCLIからセッションを削除できる。削除時、Towerはディレクトリを一切触らず、セッション情報（metadata）のみを削除する。

**Why this priority**: セッション削除も基本機能であり、「Towerはディレクトリを触らない」原則を明確にする重要な機能。

**Independent Test**: `tower rm session-name`コマンドを実行し、セッションが削除されるがディレクトリは残っていることを確認できる。

**Acceptance Scenarios**:

1. **Given** アクティブなセッションがある, **When** `tower rm session-name`を実行, **Then** 確認プロンプト後にセッションが削除される
2. **Given** セッションがある, **When** `tower rm session-name -f`を実行, **Then** 確認なしで即座に削除される
3. **Given** セッションを削除した, **When** ディレクトリを確認, **Then** ディレクトリは削除されずそのまま残っている

---

### User Story 3 - Navigatorでセッション一覧を確認する (Priority: P2)

ユーザーはNavigatorでセッション一覧を確認できる。各セッションにはセッション名とディレクトリパスが表示される。

**Why this priority**: 一覧表示は作業効率に直結する機能だが、セッション作成・削除の基盤が先に必要なためP2。

**Independent Test**: `prefix + t`でNavigatorを開き、セッション名とパスが表示されることを確認できる。

**Acceptance Scenarios**:

1. **Given** 複数のセッションがある, **When** Navigatorを開く, **Then** セッション名とパスが一覧表示される
2. **Given** アクティブとドーマントのセッションがある, **When** Navigatorを開く, **Then** アクティブは▶、ドーマントは○で表示される
3. **Given** Navigatorを開いている, **When** j/kキーを押す, **Then** セッション間を移動できる

---

### User Story 4 - Navigatorからセッションにアタッチする (Priority: P2)

ユーザーはNavigatorからセッションを選択してアタッチできる。

**Why this priority**: アタッチはNavigatorの主要操作であり、一覧表示と同時に提供する。

**Independent Test**: NavigatorでセッションをEnterで選択し、そのセッションにアタッチできることを確認。

**Acceptance Scenarios**:

1. **Given** Navigatorでセッションを選択, **When** Enterを押す, **Then** そのセッションにアタッチされる
2. **Given** ドーマントセッションを選択, **When** rを押す, **Then** セッションが復元されアクティブになる

---

### Edge Cases

- 存在しないパスを指定した場合、エラーメッセージを表示
- ディレクトリではなくファイルを指定した場合、エラーメッセージを表示
- 同名セッションが既に存在する場合、エラーメッセージを表示
- metadataが壊れている場合、セッションをスキップして警告表示
- tmuxセッションが異常終了した場合、metadataはドーマント状態として保持

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: システムは`tower add <path>`コマンドで指定ディレクトリのセッションを作成できなければならない
- **FR-002**: システムは`tower add <path> -n <name>`でセッション名を明示的に指定できなければならない
- **FR-003**: システムはセッション作成時、指定パスの存在とディレクトリであることを検証しなければならない
- **FR-004**: システムは同名セッションが存在する場合、作成を拒否しエラーを返さなければならない
- **FR-005**: システムは`tower rm <name>`コマンドでセッションを削除できなければならない
- **FR-006**: システムはセッション削除時、確認プロンプトを表示しなければならない（`-f`オプションでスキップ可能）
- **FR-007**: システムはセッション削除時、ディレクトリを一切変更してはならない
- **FR-008**: Navigatorはセッション名とパスを表示しなければならない
- **FR-009**: セッションの作成・削除はCLI（`tower add`/`tower rm`）経由でのみ行う
- **FR-011**: metadataは`session_id`, `session_name`, `directory_path`, `created_at`のフィールドを持たなければならない
- **FR-012**: 全セッションは同一の種別として扱い、種別による区別は行わない

### Key Entities

- **Session**: Claude Codeが動作する作業単位。セッションID、名前、ディレクトリパス、作成日時を持つ
- **Metadata**: セッションの永続化情報。`~/.claude-tower/metadata/<session_id>.meta`に保存
- **Navigator**: セッション一覧を表示し、操作するためのUI

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: ユーザーは2コマンド以内でセッションを作成・削除できる
- **SC-002**: Navigatorの表示項目がセッション名とパスで構成され、必要十分な情報を提供する
- **SC-003**: セッション削除後、元のディレクトリが100%保持される
- **SC-005**: セッション管理に必要な機能がCLIとNavigatorで完結する

## Assumptions

- ユーザーはディレクトリの作成・管理を自身で行う（git worktree含む）
- tmux 3.2以上がインストールされている
- Claude Code CLIがインストールされている
- ユーザーはBashシェル互換の環境で作業している
