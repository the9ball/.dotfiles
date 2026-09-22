---
name: dotnet-testing
description: .NET の build または test を実行するときにタイムアウトと構成の契約を適用する。無関係な実行では発動しない。
---

# .NET testing workflow

## Discovery contract

- Positive trigger: .NET project の build または test を実行する。
- Negative trigger: .NET 以外の検証や、コマンドを実行しない説明だけを行う。
- Conditional dependency: 追加の依存契約はない。
- Failure mode: build・test の構成または実行条件を確定できない場合は無理に実行せず、停止して報告する。

## Runtime contract

この Skill が discovery されたときだけ、下記の Guide section を normative contract として適用する。条件付き依存は必要な場合だけ読み込み、解決不能なら推測による代替や silent omission をせず fail-safe に停止する。

## Guide

`.NET` の build・test を実行する前に読む。

- `dotnet test` はビルド込みでタイムアウトしやすいため、実装後は原則 `dotnet build` と `dotnet test --no-build` の2段階で実行する。
- build と test の構成を一致させ、必要に応じて両方へ `-c Debug` など同じ構成を指定する。
- build と test のツール側タイムアウトは、I/O による一時的な遅延を考慮した調整可能な初期値として原則 `300000ms`（5分）にする。これは固定閾値や承認の代替ではない。
