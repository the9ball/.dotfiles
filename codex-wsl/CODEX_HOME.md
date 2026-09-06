# `.codex-wsl`のセットアップ

この手順は任意です。
WSL側のRemote Control専用ホームを作成し、standalone版のCodex、認証情報、WSL固有の指示を配置します。

## 前提

先に[`codex-wsl/SETUP.md`](SETUP.md)の「WSL基盤を確認する」を完了してください。
対象ディストリビューションでAquaと通常のCodex CLIを実行できる状態が必要です。

Windowsの自動起動登録は、この手順でログイン状態を確認した後に行います。

## 専用ホームを使う理由

WSL側では`CODEX_HOME=$HOME/.codex-wsl`を使用します。
Windows側の`CODEX_HOME`（通常は`C:\Users\<ユーザー名>\.codex-personal`）と同じ物理ディレクトリを参照することもできますが、現在のWindows設定にはWSLで解釈できないパスが含まれています。

専用ホームを使うと、WSL固有の`AGENTS.md`を置きながら、Windows側の設定、ログ、セッション、SQLite状態を変更せずに済みます。

この分離はアカウントを分けるためではありません。
Windows側とWSL側で同じChatGPTアカウントを使用できます。

## standalone版を導入する

WSLの対話型シェルで次を実行します。

~~~sh
cd "$HOME/.dotfiles"
export AQUA_GLOBAL_CONFIG="$HOME/.dotfiles/aqua.yaml"
export PATH="$HOME/.local/share/aquaproj-aqua/bin:$PATH"
export CODEX_HOME="$HOME/.codex-wsl"
mkdir -p "$CODEX_HOME"
(
    export CODEX_INSTALL_DIR="$CODEX_HOME/bin"
    # インストーラーが起動スクリプトへPATHを追記しないよう、実行中だけ追加する。
    export PATH="$PATH:$CODEX_INSTALL_DIR"
    curl -fsSL https://chatgpt.com/codex/install.sh | sh
)
hash -r 2>/dev/null || true

export CODEX_STANDALONE="$CODEX_HOME/packages/standalone/current/codex"
test -x "$CODEX_STANDALONE"
"$CODEX_STANDALONE" --version
~~~

`aqua install`は通常のCodex CLIを導入しますが、Remote Control用のstandalone実体は導入しません。
この手順のインストーラーは、`$CODEX_HOME/packages/standalone/current/codex`にstandalone実体を配置します。
`CODEX_INSTALL_DIR`は専用ホーム内へ一時的に向け、インストール中だけPATHへ追加します。
そのため、standalone用のbinディレクトリを通常のPATHへ永続追加しません。

## 既存のstandaloneリンクを移行する

以前のインストールで`~/.local/bin/codex`がstandalone実体へのシンボリックリンクになっている場合は、Aquaの通常CLIより先に解決されます。
対象が専用ホームのstandalone配下であることを確認してから、次のコマンドでリンクだけを削除します。

~~~sh
export CODEX_HOME="$HOME/.codex-wsl"
old_codex="$HOME/.local/bin/codex"
if [ -L "$old_codex" ]; then
    old_target="$(readlink -f "$old_codex")"
    case "$old_target" in
        "$CODEX_HOME/packages/standalone/"*)
            rm "$old_codex"
            ;;
    esac
fi
hash -r 2>/dev/null || true
~~~

通常のCodex CLIがAquaのproxyを指すことを確認します。

~~~sh
export PATH="$HOME/.local/share/aquaproj-aqua/bin:$PATH"
hash -r 2>/dev/null || true
test "$(command -v codex)" = "$HOME/.local/share/aquaproj-aqua/bin/codex"
~~~

## standalone版を更新する

standalone版の更新も、同じインストーラーを実行します。

~~~sh
export CODEX_HOME="$HOME/.codex-wsl"
mkdir -p "$CODEX_HOME"
(
    export CODEX_INSTALL_DIR="$CODEX_HOME/bin"
    # インストーラーが起動スクリプトへPATHを追記しないよう、実行中だけ追加する。
    export PATH="$PATH:$CODEX_INSTALL_DIR"
    curl -fsSL https://chatgpt.com/codex/install.sh | sh
)

"$CODEX_HOME/packages/standalone/current/codex" --version
~~~

通常の`codex`コマンドはAqua管理のCLIを指すため、Remote Control用standalone版の更新に`codex update`を使わないでください。
通常のCLIの更新は、`codex-wsl/SETUP.md`に記載したAquaの手順で行います。

## WSL側のCodexにログインする

同じWSLの対話型シェルで、standalone実体を明示してログインします。

~~~sh
export CODEX_HOME="$HOME/.codex-wsl"
export CODEX_STANDALONE="$CODEX_HOME/packages/standalone/current/codex"
mkdir -p "$CODEX_HOME"
"$CODEX_STANDALONE" login --device-auth
"$CODEX_STANDALONE" login status
~~~

ログイン操作は対話型シェルで行い、認証情報をスクリプトやリポジトリへ保存しません。

`login status`が`Logged in using ChatGPT`を返せば、WSL側の認証状態を確認できます。

## WSL固有の指示を追加する

WSL側だけの制約や運用規則は`$HOME/.codex-wsl/AGENTS.md`に記述します。

ファイルが存在しない場合だけ、次の雛形を作成します。

~~~sh
export CODEX_HOME="$HOME/.codex-wsl"
mkdir -p "$CODEX_HOME"
if [ ! -e "$CODEX_HOME/AGENTS.md" ]; then
    cat > "$CODEX_HOME/AGENTS.md" <<'EOF'
# WSL用Codex指示

ここにWSL固有の指示を書く。
EOF
else
    printf '%s\n' "$CODEX_HOME/AGENTS.md already exists; edit it manually."
fi
~~~

認証情報やアクセストークンは`AGENTS.md`に書きません。

## 確認

次のコマンドで、専用ホームとstandalone実体を確認します。

~~~sh
export CODEX_HOME="$HOME/.codex-wsl"
export CODEX_STANDALONE="$CODEX_HOME/packages/standalone/current/codex"
printf 'CODEX_HOME=%s\n' "$CODEX_HOME"
command -v "$CODEX_STANDALONE"
"$CODEX_STANDALONE" login status
"$CODEX_STANDALONE" --version
~~~

確認が完了したら、[`codex-wsl/SETUP.md`](SETUP.md)の「Windowsの自動起動を登録する」へ進みます。

## トラブルシューティング

### standalone実体が見つからない

`$HOME/.codex-wsl/packages/standalone/current/codex`が存在しない場合は、standalone版の導入手順を再実行します。

### ログイン状態を確認できない

`CODEX_HOME`が`$HOME/.codex-wsl`を指していることと、standalone実体を明示していることを確認します。

Windows側の`~/.codex-personal`をWSL側の`CODEX_HOME`に指定すると、Windows専用パスを含む設定の読み込みで失敗する可能性があります。

## 参照

- [OpenAI公式のCodex CLI手順](https://learn.chatgpt.com/docs/codex/cli)
- [Codexの環境変数](https://learn.chatgpt.com/docs/config-file/environment-variables)
- [AGENTS.mdの探索規則](https://learn.chatgpt.com/docs/agent-configuration/agents-md)
