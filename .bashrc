# User specific environment and startup programs
#
# このファイルはリポジトリ直下で管理する Bash の実設定です。
# chezmoi がホームへ配置する ~/.bashrc は、このファイルを読み込むランチャーだけを持ちます。
# ~/.bash_profile 経由で非対話シェルからも読み込まれるため、環境変数と関数定義は
# 非対話シェルでも必要なものとしてここに置き、対話シェル専用の設定は分離しています。
#
# 「非対話なら冒頭で return」はここでは使えません。下の PATH は非対話シェルにも必要です。

# for aqua
# Windows では aqua の bin が Windows 側の PATH に入っており、Git Bash が
# POSIX パスへ変換して引き継ぐため、ここで足す必要はない。
# Windows 形式のパスをそのまま PATH へ足すと、ドライブレターのコロンで
# 分割され、相対エントリが PATH の先頭に入る。
# AQUA_GLOBAL_CONFIG も Windows ではユーザー環境変数として設定するため
# (run_after_environment.ps1.tmpl)、ここでは触らない。両方で設定すると
# シェルの種類によって参照する aqua.yaml が変わる。
case "${OSTYPE-}" in
	msys*|cygwin*) ;;
	*)
		export AQUA_GLOBAL_CONFIG="$HOME/.dotfiles/aqua.yaml"
		aqua_root_directory="${AQUA_ROOT_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/aquaproj-aqua}"
		# Only prepend a POSIX absolute path without a drive-letter colon or UNC prefix.
		case "$aqua_root_directory" in
			/*)
				case "$aqua_root_directory" in
					//*|*:*) ;;
					*) export PATH="$aqua_root_directory/bin:$PATH" ;;
				esac
				;;
		esac
		unset aqua_root_directory
		;;
esac
export AQUA_PROGRESS_BAR=true
export AQUA_LOG_COLOR=always

# その他global系設定
export EDITOR=vim

# svn用
export SVN_EDITOR="vim"

# cdgitroot は現在の Git worktree のルートディレクトリへ移動します。
cdgitroot() {
	if [ `git rev-parse --is-inside-work-tree` ]; then
		cd `git rev-parse --show-toplevel`
	fi
}

# 対話シェル専用の設定
case $- in
	*i*)
		if [ -r "$HOME/.bashrc.interactive" ]; then
			. "$HOME/.bashrc.interactive"
		fi
		;;
esac

# Machine-local overrides. Keep credentials and host-specific paths there.
if [ -r "$HOME/.bashrc.local" ]; then
	. "$HOME/.bashrc.local"
fi
