export PATH=$HOME/.dotfiles/bin:$HOME/.dotfiles/GIT_SAFE_RESET/:$HOME/bin:$PATH

# User specific environment and startup programs

stty stop undef

# kube-ps1
if [ -d $HOME/.dotfiles/kube-ps1 ]; then
	source $HOME/.dotfiles/kube-ps1/kube-ps1.sh
fi

# PS1
export OLD_PS1=${PS1}
export PS1_COLOR='\033[32m'
function git_branch { printf '\033[34m<'; printf "$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"; printf ">${PS1_COLOR}"; }
function git_ps1 { git rev-parse --is-inside-work-tree >/dev/null 2>&1 && git_branch; }
export PS1='$(printf ${PS1_COLOR})[\u@\h \W$(git_ps1)]\033[0m $(kube_ps1)\n\$ '

# alias
alias la='ls -al'
alias vi='vim'
alias :vi='vim'
alias :e='vim'

# 雑多なalias
alias la='ls -al'
alias ll='ls -l'
alias vi='vim'

# 
export EDITOR=vim

# ccache 用の設定
#export CCACHE_PREFIX="distcc"
export CCACHE_DIR=/opt/$USER/CCACHE_DIR

# svn用
export SVN_EDITOR="vim"
alias svndiff='svn diff -x --ignore-eol-style'

# CentOS用バージョン表示
# そのうちOS毎のやつ作るかも。
alias osver='cat /etc/redhat-release'

alias lfs='git lfs'

# ccache
export CC='ccache gcc'
export CXX='ccache g++'

# git completion
if [ -f /etc/bash_completion.d/git ]; then
	. /etc/bash_completion.d/git
elif [ -f $(which git)/../../contrib/completion/git-completion.bash ]; then
	. $(which git)/../../contrib/completion/git-completion.bash
elif [ -f ~/.dotfiles/git-completion/git-completion.bash ]; then
	. ~/.dotfiles/git-completion/git-completion.bash
else
	echo 'git-completion.bash is not found'
fi

# function _update_ps1()
# {
# 	   export PS1="$(~/powerline-bash/powerline-bash.py $?)"
# }
# export PROMPT_COMMAND="_update_ps1"

# .vimとの連携前提
if [ -d ${HOME}/.vim/bundle/lua-5.2.2-utf8/src ] ; then
	export PATH=${HOME}/.vim/bundle/lua-5.2.2-utf8/src:${PATH}
fi

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

# AWS
alias awsaccount='aws sts get-caller-identity'
alias dockerlogin='$(aws ecr get-login --no-include-email --region ap-northeast-1)'

##
# Your previous /Users/Shaula/.bash_profile file was backed up as /Users/Shaula/.bash_profile.macports-saved_2014-02-17_at_04:37:22
##

# MacPorts Installer addition on 2014-02-17_at_04:37:22: adding an appropriate PATH variable for use with MacPorts.
export PATH=/opt/local/bin:/opt/local/sbin:$PATH
# Finished adapting your PATH environment variable for use with MacPorts.

export HOMEBREW_GITHUB_API_TOKEN=2e20ceedd5d99ded0d8df8534e518cf197e9ad35

export GOPATH="${HOME}/gocode"
export PATH="${GOPATH}/bin:${PATH}"

# for aqua
export AQUA_PROGRESS_BAR=true
export AQUA_LOG_COLOR=always
