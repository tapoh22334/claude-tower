# 受入シナリオ — Claude セッションの中から Tower を操作する
#
# タグ規約:
#   @UF-001-NNN   由来のユーザフロー。必須・ちょうど1個
#   @REQ-001-NNN  検証する要求。必須・1個以上
#   @core / @important / @peripheral  フロー優先度
#
# 実行系: tests/e2e/test_acceptance_001.bats(各 @test の名前はシナリオ名と同一)
# ランナ: value/001-tower-session-cli/acceptance/run.sh

機能: セッションの中から Tower を操作する
  Navigator に戻らずに、セッション名を実態に合わせ、アイデアを別プロジェクトの
  新セッションに文脈ごと移し、新しいプロジェクトを 1 コマンドで始める。

  背景:
    前提 Tower のセッションサーバと Navigator サーバはテスト専用の socket で動いている
    かつ claude の代わりに CLAUDE_TOWER_PROGRAM が使われる

  @UF-001-001 @REQ-001-001 @REQ-001-002 @REQ-001-003 @REQ-001-005 @REQ-001-013 @core
  シナリオ: セッションの中から引数なしで自分の名前を付け替える
    前提 Tower セッション tower_A が動作し、その pane の中にいる
    もし tower rename "payments 移行" を実行する
    ならば 標準出力は tower_A の 1 行だけである
    かつ tower_A の metadata の session_name は "payments 移行" である
    かつ created_at と launch_dir は変わっていない
    かつ 次の再構築で Navigator の行名が "payments 移行" を含む

  @UF-001-001 @REQ-001-020 @core
  シナリオ: Tower の外で --session なしの rename は失敗して何も変えない
    前提 Tower セッションの pane の外にいる
    もし tower rename foo を実行する
    ならば 終了コードは 2 である
    かつ 標準エラー出力に "--session" が含まれる
    かつ どの metadata も変わっていない

  @UF-001-002 @REQ-001-004 @REQ-001-013 @peripheral
  シナリオ: 付けた名前を --clear で外す
    前提 tower_A に session_name が付いている
    もし tower rename --clear --session tower_A を実行する
    ならば tower_A の metadata に session_name が無い
    かつ 標準出力は tower_A の 1 行だけである

  @UF-001-003 @REQ-001-006 @REQ-001-007 @REQ-001-008 @REQ-001-010 @REQ-001-013 @core
  シナリオ: 別プロジェクトで新セッションを開始し要約を最初のプロンプトとして渡す
    前提 セッション tower_H が動作し、プロジェクトディレクトリ foo が存在する
    もし 要約を標準入力に流して tower open foo --prompt-file - を実行する
    ならば 標準出力に新しいセッション id が 1 行出る
    かつ 新セッションの tmux セッションが foo を作業ディレクトリとして動作している
    かつ 新セッションの metadata の launch_dir は foo である
    かつ 保存されたプロンプトファイルの内容は流した要約と一致する
    かつ 新セッションの pane に打たれた起動コマンドはそのプロンプトファイルを参照している
    かつ Navigator の selected は新セッションを指す
    かつ tower_H は動作したままで metadata も変わっていない

  @UF-001-003 @REQ-001-009 @important
  シナリオ: Navigator が動作していれば open 後に view が新セッションに切り替わる
    前提 Navigator セッションが動作し、view pane が tower_H に付いている
    もし tower open foo を実行する
    ならば view pane の client は新セッションに付いている

  @UF-001-003 @REQ-001-028 @core
  シナリオ: Navigator が動作していなくても open は成功する
    前提 Navigator サーバが動作していない
    もし tower open foo を実行する
    ならば 終了コードは 0 である
    かつ Navigator の selected は新セッションを指す

  @UF-001-003 @REQ-001-023 @core
  シナリオ: 存在しないディレクトリへの open は失敗しセッションを作らない
    前提 ディレクトリ typo は存在しない
    もし tower open typo を実行する
    ならば 終了コードは 1 である
    かつ 標準エラー出力に typo が含まれる
    かつ Tower セッションの数は変わっていない

  @UF-001-004 @REQ-001-011 @REQ-001-012 @REQ-001-013 @core
  シナリオ: 新しいプロジェクトを 1 コマンドで始める
    前提 親ディレクトリに bar は存在しない
    もし tower project new bar --prompt "bar の初期設計を始める" を実行する
    ならば 親ディレクトリに bar と bar/.git ができている
    かつ 標準出力に新しいセッション id が 1 行出る
    かつ 新セッションの tmux セッションが bar を作業ディレクトリとして動作している
    かつ 保存されたプロンプトファイルの内容は "bar の初期設計を始める" である

  @UF-001-004 @REQ-001-025 @core
  シナリオ: 既に存在する名前での project new は失敗し何も触らない
    前提 親ディレクトリに bar が存在し、中にファイルがある
    もし tower project new bar を実行する
    ならば 終了コードは 1 である
    かつ 標準エラー出力に "既に存在" が含まれる
    かつ bar の中身は変わらず、.git は作られていない
    かつ Tower セッションの数は変わっていない

  @UF-001-005 @REQ-001-014 @REQ-001-016 @core
  シナリオ: スキルから非対話で呼べる文面と契約が揃っている
    前提 skills/tower/SKILL.md が存在する
    ならば SKILL.md は 3 つの意図のトリガー語と tower rename / tower open / tower project new を含む
    かつ 引き継ぎ要約の型(目的・決めたこと・次にやること・参照ファイル)を含む
    かつ 標準入力を閉じて tower rename --session tower_A x を実行しても確認待ちにならず完走する

  @UF-001-005 @REQ-001-021 @REQ-001-022 @REQ-001-024 @REQ-001-026 @REQ-001-027 @core
  シナリオ: 入力が不正なときは理由と終了コードで区別できて失敗する
    もし 空の名前で tower rename --session tower_A "" を実行する
    ならば 終了コードは 2 である
    もし 登録されていない id で tower rename --session tower_zzz x を実行する
    ならば 終了コードは 1 である
    もし 読めないプロンプトファイルで tower open foo --prompt-file /nonexistent を実行する
    ならば 終了コードは 1 でありセッションは作られない
    もし 不正な名前で tower project new ../evil を実行する
    ならば 終了コードは 2 であり何も作られない
    もし git init が失敗する環境で tower project new baz を実行する
    ならば 終了コードは 1 でありセッションは作られない

  @UF-001-006 @REQ-001-015 @peripheral
  シナリオ: help に 3 コマンドが載っている
    もし tower help を実行する
    ならば 出力に rename と open と "project new" が含まれる
