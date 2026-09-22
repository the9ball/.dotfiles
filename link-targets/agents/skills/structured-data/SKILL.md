---
name: structured-data
description: JSON などの構造化データを値や階層として読み取るときに使う。無関係なテキスト検索では発動しない。
---

# Structured data workflow

## Discovery contract

- Positive trigger: JSON の構造を解釈または値・階層を抽出する。
- Negative trigger: 単なる全文表示や通常の Markdown 検索で構造を解釈しない。
- Conditional dependency: 追加の依存契約はなく、構造化 parser の結果だけを使う。
- Failure mode: 構造化 parser で解釈できない場合はテキスト推測へ fallback せず、停止して報告する。

## Runtime contract

この Skill が discovery されたときだけ、下記の Guide section を normative contract として適用する。条件付き依存は必要な場合だけ読み込み、解決不能なら推測による代替や silent omission をせず fail-safe に停止する。

## Guide

JSON ファイルの値を調べる・抽出する前に読む。

- JSON の構造を解釈できるツールを使い、テキスト検索だけで値や階層を判定しない。
- PowerShell が使える環境では `ConvertFrom-Json` を優先し、Unix 系で `jq` が使える場合は `jq` を使う。両方使える場合は環境に適した方を選ぶ。
- grep、ripgrep、Select-String はキー名や構造を横断する検索で取りこぼし・誤ヒットが起きるため、原則として JSON の値の抽出に使わない。
- ファイル全体をテキストとして眺める、構造化ツールの入力を絞るなど、目的が明確な場合だけテキスト検索を補助的に使う。
