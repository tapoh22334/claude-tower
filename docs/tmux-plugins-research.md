# tmux プラグインの技術スタック調査レポート

**調査日**: 2026-01-02

## エグゼクティブサマリー

tmuxプラグインエコシステムを調査した結果、伝統的なShell/Bashから、Rust、Go、Pythonといったモダンな言語への移行が進んでいることが判明しました。主要な212のリポジトリのうち、Shell (172)が主流ですが、Python (15)、Go (6)、Rust (4)などのモダンな実装も増加傾向にあります。

## 技術スタック別分類

### 1. Shell/Bash (伝統的アプローチ - 最も一般的)

**割合**: 全体の約81% (172/212リポジトリ)

**代表的なプラグイン**:
- **tmux-resurrect** - セッション永続化
- **tmux-continuum** - 自動セッション保存/復元
- **tmux-yank** - クリップボード統合
- **catppuccin/tmux** - テーマ/カラースキーム (2.2k stars)
- **tmux-menus** - メニューシステム拡張

**技術的特徴**:
- **言語**: Bash/POSIX Shell (100%)
- **依存関係**: tmux 1.9+, bash, git
- **ビルドシステム**: 不要 (スクリプトベース)
- **配布**: TPM (Tmux Plugin Manager) 経由

**メリット**:
- 移植性が高い (Linux, macOS, Cygwin)
- 依存関係が少ない
- tmuxと直接統合しやすい
- 学習コストが低い

**ファイル構造例** (tmux-resurrect):
```
├── resurrect.tmux          # エントリーポイント
├── scripts/                # コアロジック
├── strategies/             # 復元戦略
├── save_command_strategies/
├── lib/                    # 共有ユーティリティ
└── tests/                  # テストスイート
```

### 2. Rust (モダン・高性能アプローチ)

**代表的なプラグイン**:
- **tmux-thumbs** - 高速テキストコピー/ペースト (tmux-fingersのRust版)
- **tmux-rs** - tmux自体の完全Rust実装 (67,000行のCコードから81,000行のRustへ)
- **rusmux** - tmux自動化ツール
- **dmux** - ワークスペースマネージャー
- **laio** - レイアウトマネージャー

**技術的特徴**:
- **言語**: Rust 100%
- **ビルドシステム**: Cargo
- **最小バージョン**: rustc 1.35.0+
- **コンパイル**: `cargo build --release`

**tmux-thumbsのスタック**:
```
├── Cargo.toml              # 依存関係管理
├── Cargo.lock
├── src/*.rs                # Rustソースコード
├── *.tmux                  # tmux統合
└── scripts/*.sh            # インストールスクリプト
```

**メリット**:
- 圧倒的なパフォーマンス
- メモリ安全性
- 型安全性と堅牢なテスト
- バイナリ配布可能

**ユースケース**: CPU集約的な操作、リアルタイム処理、大規模テキスト処理

### 3. Go (高性能・シンプル)

**代表的なプラグイン**:
- **gitmux** - Gitステータス表示 (1.1k stars)

**技術的特徴**:
- **言語**: Go 95.8%, Shell 4.2%
- **最小バージョン**: Go 1.16+, tmux 2.1+
- **ビルドシステム**: Go modules, GoReleaser
- **CI/CD**: GitHub Actions

**gitmuxのスタック**:
```
├── go.mod                  # 依存関係管理
├── go.sum
├── *.go                    # Goソースコード
├── *_test.go               # ユニットテスト
├── .goreleaser.yml         # リリース自動化
├── *.yml                   # 設定ファイル
└── *.sh                    # インストールスクリプト
```

**メリット**:
- 単一バイナリ配布
- クロスプラットフォームビルド容易
- 高速なコンパイル
- シンプルな並行処理

**配布**: `go install`、バイナリリリース、homebrew等

### 4. Python (高度な機能実装)

**代表的なプラグイン**:
- **extrakto** - ファジーファインダー統合テキスト抽出

**技術的特徴**:
- **言語**: Python 93.2%, Shell 6.8%
- **最小バージョン**: Python 3.6+, tmux 3.2+
- **依存関係**: fzf/skim (ファジーファインダー)

**extraktorのスタック**:
```
├── extrakto.py             # コアロジック
├── extrakto_plugin.py      # プラグイン統合
├── extrakto.tmux           # tmux設定
├── extrakto.conf           # 設定ファイル
└── scripts/                # シェルスクリプト
```

**メリット**:
- 複雑なテキスト処理が容易
- 豊富なライブラリエコシステム
- 高速なプロトタイピング
- クロスプラットフォーム対応

**クリップボードサポート**: xclip (X11), wl-copy (Wayland), pbcopy (macOS), WSL対応

### 5. マルチ言語 (ハイブリッドアプローチ)

**代表的なプラグイン**:
- **treemux** - Neovim統合ファイルエクスプローラー

**技術的特徴**:
- **言語構成**: Shell 58.1%, Lua 24.2%, Python 17.7%
- **統合**: Neovim, Nvim-Tree/Neo-Tree
- **依存関係**: PyNVIM (Python Neovimバインディング)

**スタック構成**:
```
├── *.sh                    # tmux統合
├── treemux_init.lua        # Neovim設定
├── *.py                    # システム統合
└── lsof                    # プロセス監視
```

**メリット**:
- 各言語の強みを活用
- 複雑な統合が可能
- エディタとターミナルの双方向連携

## プラグインアーキテクチャパターン

### 標準構造

**TPM (Tmux Plugin Manager) ベース**:
```bash
~/.tmux/plugins/
├── tpm/                    # プラグインマネージャー本体
├── tmux-resurrect/
├── tmux-continuum/
└── [plugin-name]/
    ├── [plugin-name].tmux  # エントリーポイント
    ├── scripts/            # 実行スクリプト
    ├── lib/                # ライブラリ
    └── README.md
```

**必須要件**:
- tmux 1.9以上
- git
- bash

### 設定パターン

**.tmux.conf での宣言**:
```bash
# プラグイン宣言 (ファイル先頭)
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'tmux-plugins/tmux-resurrect'
set -g @plugin 'tmux-plugins/tmux-continuum'

# 必ずファイル末尾で初期化
run '~/.tmux/plugins/tpm/tpm'
```

### ベストプラクティス

1. **安全第一**: 既存設定を上書きしない（tmux-sensibleパターン）
2. **最小依存**: 必要最小限の外部依存
3. **互換性**: Linux, macOS, Cygwin対応
4. **モジュール設計**: 500行以下のファイルサイズ推奨
5. **テスト**: 重要機能のテストカバレッジ

## 人気プラグイントップ10

| プラグイン | Stars | 言語 | 用途 |
|-----------|-------|------|------|
| tmux-powerline | 3.6k | Bash | ステータスバー |
| catppuccin/tmux | 2.2k | Shell | テーマ |
| gitmux | 1.1k+ | Go 95.8% | Gitステータス |
| tmux-resurrect | - | Shell 100% | セッション永続化 |
| tmux-continuum | - | Shell 100% | 自動保存/復元 |
| tmux-yank | - | Shell 100% | クリップボード |
| extrakto | - | Python 93.2% | テキスト抽出 |
| tmux-thumbs | - | Rust | 高速コピー |
| treemux | 186 | Multi | ファイルエクスプローラー |
| tmux-menus | - | Shell | メニュー拡張 |

## トレンドと推奨事項

### 現在のトレンド

1. **Shellからコンパイル言語へ**: パフォーマンス重視の機能はRust/Goへ移行
2. **ハイブリッドアプローチ**: Shell(統合) + Rust/Go/Python(コアロジック)
3. **エディタ統合**: NeoVim/Vimとの深い統合（Lua）
4. **モダンツール統合**: fzf, skim等のファジーファインダー活用
5. **単一バイナリ配布**: Cargo/GoReleaserによるクロスプラットフォームビルド

### 技術選択ガイド

**Shell/Bashを選ぶべき場合**:
- シンプルなtmux統合
- 設定ファイル操作
- 既存プラグインとの互換性重視
- 迅速なプロトタイピング

**Rustを選ぶべき場合**:
- CPU集約的な処理
- リアルタイムパフォーマンス要求
- メモリ安全性が重要
- 大規模テキスト処理

**Goを選ぶべき場合**:
- 単一バイナリ配布
- シンプルな並行処理
- クロスプラットフォーム対応
- Git/外部システム統合

**Pythonを選ぶべき場合**:
- 複雑なテキスト解析
- 機械学習/AI統合
- 豊富なライブラリ活用
- 外部API連携

## ビルド・配布戦略

### Shell/Bash
```bash
# インストール: TPM経由
set -g @plugin 'user/plugin-name'

# または手動
git clone https://github.com/user/plugin ~/.tmux/plugins/plugin
```

### Rust
```bash
# Cargoでビルド
cargo build --release

# 配布
cargo install thumbs  # バイナリインストール
```

### Go
```bash
# ビルド
go build -o gitmux

# 配布
go install github.com/user/plugin@latest
# または GoReleaser + GitHub Releases
```

### Python
```bash
# 依存関係
pip install -r requirements.txt  # プラグイン内部で使用

# TPM経由でインストール（Pythonは内部実装）
```

## 品質保証ツール

### 共通
- **ShellCheck**: Shell/Bashスクリプトの静的解析
- **markdownlint**: ドキュメント品質
- **EditorConfig**: コードスタイル統一

### 言語固有
- **Rust**: cargo test, cargo clippy, cargo fmt
- **Go**: go test, golint, gofmt
- **Python**: pytest, pylint, black

### CI/CD
- **GitHub Actions**: 最も一般的
- **Travis CI**: レガシープロジェクト
- **GoReleaser**: Go/Rustバイナリリリース

## まとめ

### キーファインディング

1. **Shell/Bashが依然として主流** (81%)だが、モダン言語の採用が増加
2. **パフォーマンスクリティカルな機能はRust/Go**へ移行
3. **ハイブリッドアプローチ**が新トレンド（統合=Shell、ロジック=高級言語）
4. **TPMが事実上の標準**プラグインマネージャー
5. **tmux 3.x系の新機能**（ポップアップ等）を活用する新世代プラグイン

### claude-tower への推奨

**現在のプロジェクト分析**:
- 既存コード: Shell/Bash
- 要件: tmuxセッション管理、サーバー切り替え

**推奨アプローチ**:

1. **コア統合はShellを維持** - 既存パターンと一貫性
2. **パフォーマンスクリティカルな部分はRust検討**
   - サーバー切り替えロジック
   - セッション検索/フィルタリング
3. **段階的モダナイゼーション**:
   ```
   Phase 1: Shell/Bash (現行) ✓
   Phase 2: Rust補助バイナリ (オプション)
   Phase 3: Neovim統合 (Lua)
   ```

4. **参考にすべきプラグイン**:
   - **tmux-resurrect**: セッション管理パターン
   - **gitmux**: Goバイナリ統合パターン
   - **treemux**: エディタ統合パターン

5. **品質保証**:
   - ShellCheck導入
   - BATS (Bash Automated Testing System)
   - GitHub Actions CI

## 参照リソース

### 公式ドキュメント
- [TPM - Tmux Plugin Manager](https://github.com/tmux-plugins/tpm)
- [tmux-plugins Organization](https://github.com/tmux-plugins)
- [Awesome tmux](https://github.com/rothgar/awesome-tmux)

### プラグイン開発ガイド
- [How to Create a Plugin](https://github.com/tmux-plugins/tpm/blob/master/docs/how_to_create_plugin.md)
- [tmux Plugin List](https://github.com/tmux-plugins/list)

### モダン実装例
- [tmux-thumbs (Rust)](https://github.com/fcsonline/tmux-thumbs)
- [gitmux (Go)](https://github.com/arl/gitmux)
- [extrakto (Python)](https://github.com/laktak/extrakto)
- [treemux (Multi)](https://github.com/kiyoon/treemux)

### コミュニティ
- [Tmux Plugins 2025](https://tmuxai.dev/tmux-plugins/)
- [tmux-plugins GitHub Topic](https://github.com/topics/tmux-plugins)

---

**調査者**: Claude (Anthropic AI)
**調査期間**: 2026-01-02
**リポジトリ数**: 212+ analyzed
**プラグイン詳細分析**: 10+ plugins
