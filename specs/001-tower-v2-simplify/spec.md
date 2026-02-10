# Feature Specification: Tower v2 - セッション管理の簡素化

**Feature Branch**: `001-tower-v2-simplify`
**Created**: 2026-02-05
**Status**: Draft
**Input**: User description: "Tower v2: セッション管理に特化したシンプルな設計への移行。Worktree管理機能を廃止し、ディレクトリは参照するだけとする。"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - CLIでセッションを追加する (Priority: P1)

ユーザーは任意のディレクトリを指定して、そのディレクトリでClaude Codeセッションを開始できる。Towerはディレクトリを「参照」するだけで、ディレクトリの作成や管理は行わない。

**Why this priority**: セッション作成は最も基本的な機能であり、Tower v2の設計哲学「ディレクトリは参照するだけ」を体現する中核機能。

**Independent Test**: `tower add /path/to/dir`コマンドを実行し、Navigatorでセッションが表示され、Claude Codeが起動していることを確認できる。

**Acceptance Scenarios**:

1. **Given** 存在するディレクトリがある, **When** `tower add /path/to/dir`を実行, **Then** セッションが作成されClaude Codeが起動する
2. **Given** セッションを追加したい, **When** `tower add . -n my-session`を実行, **Then** カレントディレクトリで指定名のセッションが作成される
3. **Given** 存在するディレクトリがある, **When** `tower add /path/to/dir`を実行, **Then** metadataが保存され、tmux再起動後も復元できる

---

### User Story 2 - CLIでセッションを削除する (Priority: P1)

ユーザーはCLIからセッションを削除できる。削除時、Towerはディレクトリを一切触らず、セッション情報（metadata）のみを削除する。

**Why this priority**: セッション削除も基本機能であり、v2の「Towerはディレクトリを触らない」原則を明確にする重要な機能。

**Independent Test**: `tower rm session-name`コマンドを実行し、セッションが削除されるがディレクトリは残っていることを確認できる。

**Acceptance Scenarios**:

1. **Given** アクティブなセッションがある, **When** `tower rm session-name`を実行, **Then** 確認プロンプト後にセッションが削除される
2. **Given** セッションがある, **When** `tower rm session-name -f`を実行, **Then** 確認なしで即座に削除される
3. **Given** セッションを削除した, **When** ディレクトリを確認, **Then** ディレクトリは削除されずそのまま残っている

---

### User Story 3 - Navigatorでセッション一覧を確認する (Priority: P2)

ユーザーはNavigatorでセッション一覧を確認できる。表示はシンプルになり、タイプアイコン（[W]/[S]）は廃止され、代わりにパスが表示される。

**Why this priority**: 一覧表示は作業効率に直結する機能だが、既存機能の改善なのでP2。

**Independent Test**: `prefix + t`でNavigatorを開き、セッション名とパスが表示されることを確認できる。

**Acceptance Scenarios**:

1. **Given** 複数のセッションがある, **When** Navigatorを開く, **Then** セッション名とパスが一覧表示される
2. **Given** アクティブとドーマントのセッションがある, **When** Navigatorを開く, **Then** アクティブは▶、ドーマントは○で表示される
3. **Given** Navigatorを開いている, **When** j/kキーを押す, **Then** セッション間を移動できる

---

### User Story 4 - Navigatorからセッションにアタッチする (Priority: P2)

ユーザーはNavigatorからセッションを選択してアタッチできる。

**Why this priority**: アタッチは既存機能であり、変更なしで継続動作する。

**Independent Test**: NavigatorでセッションをEnterで選択し、そのセッションにアタッチできることを確認。

**Acceptance Scenarios**:

1. **Given** Navigatorでセッションを選択, **When** Enterを押す, **Then** そのセッションにアタッチされる
2. **Given** ドーマントセッションを選択, **When** rを押す, **Then** セッションが復元されアクティブになる

---

### User Story 5 - 既存v1セッションの後方互換性 (Priority: P3)

既存のv1形式のmetadata（Worktreeセッション等）を持つユーザーは、v2でも引き続きセッションを使用できる。ただし削除時の挙動は新仕様（ディレクトリを削除しない）に従う。

**Why this priority**: 既存ユーザーへの配慮だが、新規機能ではないためP3。

**Independent Test**: v1形式のmetadataを持つセッションがNavigatorに表示され、操作できることを確認。

**Acceptance Scenarios**:

1. **Given** v1形式のmetadataがある, **When** Navigatorを開く, **Then** セッションが正しく表示される
2. **Given** v1のWorktreeセッションがある, **When** 削除する, **Then** metadataのみ削除されworktreeディレクトリは残る

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
- **FR-009**: Navigatorからの`n`（新規作成）と`D`（削除）キーバインドは廃止しなければならない
- **FR-010**: システムはv1形式のmetadataを読み込み、後方互換性を維持しなければならない
- **FR-011**: metadataは`session_id`, `session_name`, `directory_path`, `created_at`のフィールドを持たなければならない
- **FR-012**: タイプ分類（[W]/[S]）は廃止し、全セッションを同一に扱わなければならない

### Key Entities

- **Session**: Claude Codeが動作する作業単位。セッションID、名前、ディレクトリパス、作成日時を持つ
- **Metadata**: セッションの永続化情報。`~/.claude-tower/metadata/<session_id>.meta`に保存
- **Navigator**: セッション一覧を表示し、操作するためのUI

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: ユーザーは2コマンド以内でセッションを作成・削除できる
- **SC-002**: Navigatorの表示項目がセッション名とパスのみになり、情報量が削減される
- **SC-003**: セッション削除後、元のディレクトリが100%保持される
- **SC-004**: v1形式のmetadataを持つ既存セッションが引き続き動作する
- **SC-005**: コードベースからWorktree関連の関数・定数が削除され、保守性が向上する

## Assumptions

- ユーザーはディレクトリの作成・管理を自身で行う（git worktree含む）
- tmux 3.2以上がインストールされている
- Claude Code CLIがインストールされている
- ユーザーはBashシェル互換の環境で作業している
