# User specific environment and startup programs
#
# このファイルはリポジトリ直下で管理する Bash の実設定です。
# chezmoi がホームへ配置する ~/.bashrc は、このファイルを読み込むランチャーだけを持ちます。
# ~/.bash_profile 経由で非対話シェルからも読み込まれるため、環境変数と関数定義は
# 非対話シェルでも必要なものとしてここに置き、対話シェル専用の設定は分離しています。
#
# 「非対話なら冒頭で return」はここでは使えません。下の PATH は非対話シェルにも必要です。

# for aqua
# Git Bash は Git 同梱ツールを PATH の先頭へ追加するため、aqua の bin を
# POSIX パスへ変換して優先する。Windows 形式のままではドライブレターの
# コロンで分割され、相対エントリが PATH に入る。
# AQUA_GLOBAL_CONFIG も Windows ではユーザー環境変数として設定するため
# (run_after_environment.ps1.tmpl)、ここでは触らない。両方で設定すると
# シェルの種類によって参照する aqua.yaml が変わる。
case "${OSTYPE-}" in
	msys*|cygwin*)
		if command -v aqua >/dev/null 2>&1 && command -v cygpath >/dev/null 2>&1; then
			if aqua_root_directory=${AQUA_ROOT_DIR:-$(aqua root-dir 2>/dev/null)} &&
				aqua_root_directory=$(cygpath -u "$aqua_root_directory"); then
				case "$aqua_root_directory" in
					//*|*:*) ;;
					/*)
						aqua_bin_directory="${aqua_root_directory%/}/bin"
						aqua_remaining_path="${PATH}:"
						aqua_path_suffix=
						# Remove exact aqua entries while preserving every other entry, including empty ones.
						while [ -n "$aqua_remaining_path" ]; do
							aqua_path_entry=${aqua_remaining_path%%:*}
							aqua_remaining_path=${aqua_remaining_path#*:}
							if [ "$aqua_path_entry" != "$aqua_bin_directory" ]; then
								aqua_path_suffix="$aqua_path_suffix:$aqua_path_entry"
							fi
						done
						export PATH="$aqua_bin_directory$aqua_path_suffix"
						unset aqua_bin_directory aqua_remaining_path aqua_path_suffix aqua_path_entry
						;;
				esac
			fi
			unset aqua_root_directory
		fi
		;;
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

# Host-local opt-in is inert until explicitly enabled; a required SSH bootstrap failure ends this shell.
case "${OSTYPE-}:${SSH_CONNECTION-}" in
    msys*:?*|cygwin*:?*)
        case "${DOTFILES_DOCKER_SSH-}" in
            ''|disabled|required) ;;
            *) printf '%s\n' 'Invalid managed SSH Docker mode.' >&2; exit 1 ;;
        esac
        ;;
esac
case "${OSTYPE-}:${SSH_CONNECTION-}:${DOTFILES_DOCKER_SSH-}" in
    msys*:?*:required|cygwin*:?*:required)
        if [ ! -r "$HOME/.dotfiles/.bashrc.docker-ssh" ] || ! . "$HOME/.dotfiles/.bashrc.docker-ssh"; then
            printf '%s\n' 'Required managed SSH Docker bootstrap failed; ending this shell.' >&2
            exit 1
        fi
        ;;
esac

# Select the SSH overlay after ordinary settings, before attaching to psmux.
if [ -r "$HOME/.dotfiles/.bashrc.ssh-psmux" ]; then
	. "$HOME/.dotfiles/.bashrc.ssh-psmux"
fi
