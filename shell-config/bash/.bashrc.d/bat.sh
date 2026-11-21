# bat: code viewer with syntax highlighting and line numbers.
case ":$PATH:" in
    *:/d/software_config/bat:*) ;;
    *) export PATH="/d/software_config/bat:$PATH" ;;
esac

# Soft colors for dark terminals.
export BAT_THEME='Dracula'
