# ble.sh: load before other interactive shell customizations.
if [[ $- == *i* && -f /d/software_config/blesh/ble.sh ]]; then
    export USER="${USER:-$(id -un)}"
    source /d/software_config/blesh/ble.sh --attach=none
fi

if [ -f /etc/bash.bashrc ]; then
    source /etc/bash.bashrc
fi

# git alias
alias gs='git status'
alias ga='git add'
alias gcm='git commit'
alias glg='git log --oneline --graph --all'
alias gb='git branch'
alias gce='git checkout'
alias gpl='git pull'
alias gps='git push'
alias gft='git fetch'
alias gk='gitk'
# normal alias
alias cls='clear'
alias path='echo $PATH | tr ":" "\n"'
alias ip='ipconfig'
alias his='history'
alias ll='ls -la'
alias la='ls -A'
alias cmphome='cd /d/program_CC'
alias st='cd /d/program_CC/00_my_information/02_st/clang_st32_h743vi'
alias exp='explorer'
alias ls='ls -F --color=auto --show-control-chars'
# function
for f in ~/.bashrc.d/*.sh; do [ -f "$f" ] && source "$f"; done
# Persist command history between Bash sessions.
export HISTFILE="$HOME/.bash_history"
HISTSIZE=10000
HISTFILESIZE=20000
HISTCONTROL=ignoreboth
shopt -s histappend
bind 'set bell-style none'
# star ship
eval "$(starship init bash)"

[[ ! ${BLE_VERSION-} ]] || ble-attach
