# bat: code viewer with syntax highlighting and line numbers.
# Custom installations can provide a directory in ~/.bashrc.local.
if [[ -n ${SELF_CONFIG_BAT_DIR-} && -d $SELF_CONFIG_BAT_DIR ]]; then
    case ":$PATH:" in
        *:"$SELF_CONFIG_BAT_DIR":*) ;;
        *) export PATH="$SELF_CONFIG_BAT_DIR:$PATH" ;;
    esac
fi
export BAT_THEME='Dracula'
