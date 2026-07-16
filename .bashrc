# User specific environment and startup programs

stty stop undef

# for Github Copilot for CLI
if command -v gh &> /dev/null ; then
	if gh extension list | grep -q "copilot"; then
		eval "$(gh copilot alias -- bash)"
		alias ??='ghcs -t shell'
		alias git?='ghcs -t git'
		alias gh?='ghcs -t gh'
	else
		echo "try 'gh extension install github/gh-copilot'"
	fi
fi

# for aqua
export PATH=${AQUA_ROOT_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/aquaproj-aqua}/bin:$PATH
export AQUA_PROGRESS_BAR=true
export AQUA_LOG_COLOR=always

if command -v aqua &> /dev/null; then
	source <(aqua completion bash)
fi

# PS1
export OLD_PS1=${PS1}
function git_branch { printf ' (\033[38;5;6m'; printf "$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"; printf "\033[0m)"; }
function git_ps1 { git rev-parse --is-inside-work-tree >/dev/null 2>&1 && git_branch; }
# $(git_ps1) だとwindowsでのgit-bashでうまく動かなかった
export PS1='\n\033[32m\u@\h\033[0m \033[33m\W\033[0m`git_ps1` `kube_ps1`\n\$ '

if ! command -v kube_ps1 >/dev/null 2>&1; then
  kube_ps1() { :; }
fi

# alias
alias la='ls -al'
alias vi='vim'
alias :vi='vim'
alias :e='vim'

# 雑多なalias
alias la='ls -al'
alias ll='ls -l'
alias vi='vim'

# その他global系設定
export EDITOR=vim

# svn用
export SVN_EDITOR="vim"
alias svndiff='svn diff -x --ignore-eol-style'

alias lfs='git lfs'

# git completion
if [ -f /etc/bash_completion.d/git ]; then
	. /etc/bash_completion.d/git
elif [ -f $(which git)/../../contrib/completion/git-completion.bash ]; then
	. $(which git)/../../contrib/completion/git-completion.bash
else
	echo 'git-completion.bash is not found'
fi

# function _update_ps1()
# {
# 	   export PS1="$(~/powerline-bash/powerline-bash.py $?)"
# }
# export PROMPT_COMMAND="_update_ps1"

# gitのrootディレクトリに移動する関数
cdgitroot() {
	if [ `git rev-parse --is-inside-work-tree` ]; then
		cd `git rev-parse --show-toplevel`
	fi
}

# https://kubernetes.io/docs/tasks/tools/install-kubectl/
if command -v kubectl >/dev/null 2>&1
then
    if [ -e /usr/share/bash-completion/bash_completion ]; then source /usr/share/bash-completion/bash_completion; fi
    source <(kubectl completion bash)
    alias k=kubectl
    alias kube=kubectl
    complete -o default -F __start_kubectl k
fi

# Machine-local overrides. Keep credentials and host-specific paths there.
if [ -r "$HOME/.bashrc.local" ]; then
	. "$HOME/.bashrc.local"
fi
