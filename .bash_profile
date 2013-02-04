# .bash_profile

# Get the aliases and functions
if [ -f $HOME/.bashrc ]; then
	. $HOME/.bashrc
fi

# User specific environment and startup programs

stty stop undef

# OLD_PS1=${PS1}
export OLD_PS1='[\u@\h \W]\$ '

# http://d.hatena.ne.jp/u-no/20070626
# screen は任意のプログラムが "<esc>khogehoge<esc>\" という文字列を吐くと、そのウィンドウのタイトルを hogehoge にかえるという機能が備わっています
# 最後に実行したコマンド
#export SCREEN_TITLE='\[\ek\e\\\]'
# 現在のカレントディレクトリ
export SCREEN_TITLE='\[\ek\W\e\\\]\r'

export PS1="${SCREEN_TITLE}${OLD_PS1}"

# export OLD_PROMPT_COMMAND='echo -ne "\033]0;${USER}@${HOSTNAME%%.*}:${PWD/#$HOME/~}"; echo -ne "\007"'
# export PROMPTO_COMMAND='echo -ne "\ek$(whoami)\e\\"'

# alias
alias la='ls -al'
alias vi='vim'
alias :vi='vim'
alias :e='vim'

# ccache 用の設定
#export CCACHE_PREFIX="distcc"
export CCACHE_DIR=/opt/$USER/CCACHE_DIR

# svn用
export SVN_EDITOR="vim"
alias svndiff='svn diff -x --ignore-eol-style'

# CentOS用バージョン表示
# そのうちOS毎のやつ作るかも。
alias osver='cat /etc/redhat-release'

# ccache
export CC='ccache gcc'
export CXX='ccache g++'

# git completion
if [ -f /etc/bash_completion.d/git ]; then
	. /etc/bash_completion.d/git
elif [ -f `which git`/../../contrib/completion/git-completion.bash ]; then
	. `which git`/../../contrib/completion/git-completion.bash
else
	echo 'git-completion.bash is not found'
fi

# function _update_ps1()
# {
# 	   export PS1="$(~/powerline-bash/powerline-bash.py $?)"
# }
# export PROMPT_COMMAND="_update_ps1"
