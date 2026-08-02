---
id: TASK-11
title: 同梱 claude-flow ヘルパーのシェルインジェクションを上流へ報告する
status: To Do
assignee: []
created_date: '2026-08-02 07:38'
labels:
  - security
  - upstream
dependencies: []
ordinal: 11000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ローカルの .claude/helpers/github-safe.js (claude-flow 同梱、gitignore 対象で claude-tower のコードではない) に、シェルインジェクションの実行経路がある。101行目と105行目で execSync に `gh ${args.join(' ')}` を渡しており、引数がシェルに素通りする。

実証済み: node .claude/helpers/github-safe.js issue view '123;echo INJECTED' で INJECTED が出力される。

同ファイル群には他に、memory.js:26 と session.js:30,62 の writeFileSync が mode 0600 を指定していない点、session.js:15 の session-${Date.now()} が予測可能な ID である点がある。

claude-tower 自体には JS ファイルが 1 つも無く、この件は当プロジェクトの脆弱性ではない。実害はエージェントが信頼できない文字列をこのヘルパーに渡した場合に限られるため緊急度は低いが、上流 (claude-flow) に報告する価値はある。

この記録は、同内容を 22 回出力した監査 JSON 群を削除する際に、唯一残す価値のある信号として抽出したもの。
<!-- SECTION:DESCRIPTION:END -->
