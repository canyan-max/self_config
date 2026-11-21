# Keep ELYTerminal's window/taskbar title stable while its file panel follows PWD.
# Change this value to choose the title for new Bash sessions.
export SELF_CONFIG_TERMINAL_TITLE='Git Bash'

function self_config/elyterminal/fix-title {
    local last_status=$? definition
    if declare -F _ely_prompt >/dev/null; then
        definition=$(declare -f _ely_prompt)
        if [[ $definition == *'title=${PWD##*/}'* ]]; then
            definition=${definition/'title=${PWD##*/}'/'title=${SELF_CONFIG_TERMINAL_TITLE:-Git Bash}'}
            builtin eval "$definition"
        fi
        # The terminal integration is now initialized; no need to inspect it again.
        blehook PRECMD-=self_config/elyterminal/fix-title
    fi
    return "$last_status"
}

# ELYTerminal defines _ely_prompt after sourcing .bashrc.
if [[ ${BLE_VERSION-} ]]; then
    blehook PRECMD!=self_config/elyterminal/fix-title
fi
