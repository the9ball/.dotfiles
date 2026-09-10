# .NET テスト実行

`.NET` の build・test を実行する前に読む。

- `dotnet test` はビルド込みでタイムアウトしやすいため、実装後は原則 `dotnet build` と `dotnet test --no-build` の2段階で実行する。
- build と test の構成を一致させ、必要に応じて両方へ `-c Debug` など同じ構成を指定する。
- build と test のツール側タイムアウトは、I/O による一時的な遅延を考慮した調整可能な初期値として原則 `300000ms`（5分）にする。これは固定閾値や承認の代替ではない。
