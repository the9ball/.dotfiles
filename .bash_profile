# .bash_profile

# Get the aliases and functions
if [ -f ~/.bashrc ]; then
	. ~/.bashrc
fi

# User specific environment and startup programs

stty stop undef

# OLD_PS1=${PS1}
export OLD_PS1="[\u@\h \W]\$ "
export SCREEN_TITLE='\[\ek\e\\\]';
export PS1="${SCREEN_TITLE}${OLD_PS1}"

# export OLD_PROMPT_COMMAND='echo -ne "\033]0;${USER}@${HOSTNAME%%.*}:${PWD/#$HOME/~}"; echo -ne "\007"'
# export PROMPTO_COMMAND='echo -ne "\ek$(whoami)\e\\"'

# alias
alias la='ls -al'
alias vi='vim'
alias :vi='vim'
alias :e='vim'

# ccache 用の設定
export CCACHE_PREFIX="distcc"
export CCACHE_DIR=/opt/syasui/CCACHE_DIR

# svn用
export SVN_EDITOR="vim"
alias svndiff='svn diff -x --ignore-eol-style'

