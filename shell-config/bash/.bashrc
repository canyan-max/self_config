# Machine-specific paths and aliases stay outside the shared configuration.
[[ ! -f "$HOME/.bashrc.local" ]] || source "$HOME/.bashrc.local"

# Load ble.sh once, before other interactive shell customizations.
if [[ $- == *i* && ! ${BLE_VERSION-} ]]; then
    for self_config_ble in "${SELF_CONFIG_BLESH_PATH-}" "$HOME/.local/share/blesh/ble.sh"; do
        [[ -n $self_config_ble && -f $self_config_ble ]] || continue
        export USER="${USER:-$(id -un)}"
        source "$self_config_ble" --attach=prompt
        break
    done
    unset self_config_ble
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
alias cmphome='cd -- "${SELF_CONFIG_PROJECTS_HOME:-$HOME}"'
alias st='cd -- "${SELF_CONFIG_ST_PROJECT:-$HOME}"'
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
if command -v starship >/dev/null 2>&1; then
    eval "$(starship init bash)"
fi

# ble.sh attaches at the first prompt, after terminal integration is installed.
