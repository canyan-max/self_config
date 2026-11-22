# bat: code viewer with syntax highlighting and line numbers.
# Installed through winget; use the executable already available on PATH.
export BAT_THEME='Dracula'

# Load ble.sh only for interactive shells; it reads ~/.blerc automatically.
if [[ $- == *i* && -f "$HOME/.local/share/blesh/ble.sh" ]]; then
    export USER="${USER:-$(id -un)}"
    source "$HOME/.local/share/blesh/ble.sh" --attach=prompt
fi
