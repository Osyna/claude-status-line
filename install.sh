#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  Claude Code Status Line Installer                          ║
# ║  A rich, informative status bar for Claude Code             ║
# ╚══════════════════════════════════════════════════════════════╝
set -euo pipefail

# ── Colors ────────────────────────────────────────────────────
R='\033[0m'; B='\033[1m'; D='\033[2m'
GR='\033[32m'; YE='\033[33m'; RE='\033[31m'; CY='\033[36m'; MA='\033[35m'

info()  { echo -e "  ${CY}▸${R} $*"; }
ok()    { echo -e "  ${GR}✓${R} $*"; }
warn()  { echo -e "  ${YE}⚠${R} $*"; }
err()   { echo -e "  ${RE}✗${R} $*" >&2; }
header(){ echo -e "\n${B}${MA}$*${R}"; }

CLAUDE_DIR="${HOME}/.claude"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Banner ────────────────────────────────────────────────────
echo ""
echo -e "${B}${CY}  ┌─────────────────────────────────────────┐${R}"
echo -e "${B}${CY}  │  Claude Code Status Line Installer      │${R}"
echo -e "${B}${CY}  │  Rich dashboard with Nerd Font icons    │${R}"
echo -e "${B}${CY}  └─────────────────────────────────────────┘${R}"
echo ""

# ── Pre-flight checks ────────────────────────────────────────
header "Pre-flight checks"

# Check Python 3
if command -v python3 &>/dev/null; then
    py_ver=$(python3 --version 2>&1)
    ok "Python 3 found: ${py_ver}"
else
    err "Python 3 not found. The Nerd Font version requires Python 3."
    err "Install Python 3 or use the bash-only fallback (see --bash flag)."
    exit 1
fi

# Check if Claude Code CLI exists
if command -v claude &>/dev/null; then
    ok "Claude Code CLI found"
else
    warn "Claude Code CLI not found in PATH (may still work if installed elsewhere)"
fi

# Check for Nerd Font (best-effort)
nerd_font_note=false
if [[ "${TERM_PROGRAM:-}" == "iTerm.app" ]] || [[ -n "${WEZTERM_PANE:-}" ]] || [[ -n "${KITTY_PID:-}" ]] || [[ -n "${ALACRITTY_SOCKET:-}" ]]; then
    ok "Modern terminal detected — likely has Nerd Font support"
else
    warn "Could not confirm Nerd Font support in your terminal"
    nerd_font_note=true
fi

# ── Parse args ────────────────────────────────────────────────
USE_BASH=false
DRY_RUN=false
FORCE=false

for arg in "$@"; do
    case "$arg" in
        --bash)    USE_BASH=true ;;
        --dry-run) DRY_RUN=true ;;
        --force)   FORCE=true ;;
        --help|-h)
            echo ""
            echo "Usage: ./install.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --bash      Install bash version (no Nerd Font icons, uses jq)"
            echo "  --dry-run   Show what would be done without making changes"
            echo "  --force     Overwrite existing files without prompting"
            echo "  --help      Show this help message"
            echo ""
            exit 0
            ;;
        *)
            err "Unknown option: $arg (use --help for usage)"
            exit 1
            ;;
    esac
done

if $DRY_RUN; then
    warn "Dry run mode — no files will be modified"
fi

# ── Create ~/.claude if needed ────────────────────────────────
header "Installing status line"

if [[ ! -d "$CLAUDE_DIR" ]]; then
    if $DRY_RUN; then
        info "Would create ${CLAUDE_DIR}/"
    else
        mkdir -p "$CLAUDE_DIR"
        ok "Created ${CLAUDE_DIR}/"
    fi
else
    ok "${CLAUDE_DIR}/ exists"
fi

# ── Copy script(s) ───────────────────────────────────────────
install_file() {
    local src="$1" dst="$2" desc="$3"

    if [[ -f "$dst" ]] && ! $FORCE; then
        if $DRY_RUN; then
            info "Would prompt to overwrite ${dst}"
            return
        fi
        echo ""
        warn "File already exists: ${dst}"
        read -rp "    Overwrite? [y/N] " ans
        if [[ "${ans,,}" != "y" ]]; then
            info "Skipped ${desc}"
            return
        fi
    fi

    if $DRY_RUN; then
        info "Would install ${desc} → ${dst}"
    else
        cp "$src" "$dst"
        chmod +x "$dst"
        ok "Installed ${desc} → ${dst}"
    fi
}

if $USE_BASH; then
    # Bash version needs jq
    if ! command -v jq &>/dev/null; then
        err "The bash version requires jq. Install it first:"
        err "  macOS:  brew install jq"
        err "  Ubuntu: sudo apt install jq"
        err "  Arch:   sudo pacman -S jq"
        exit 1
    fi
    ok "jq found (required for bash version)"
    install_file "${SCRIPT_DIR}/statusline-command.sh" "${CLAUDE_DIR}/statusline-command.sh" "status line (bash)"
    STATUS_CMD="bash ~/.claude/statusline-command.sh"
else
    install_file "${SCRIPT_DIR}/statusline-command.py" "${CLAUDE_DIR}/statusline-command.py" "status line (python)"
    STATUS_CMD="python3 ~/.claude/statusline-command.py"
    # Also install bash version as fallback
    if [[ -f "${SCRIPT_DIR}/statusline-command.sh" ]]; then
        install_file "${SCRIPT_DIR}/statusline-command.sh" "${CLAUDE_DIR}/statusline-command.sh" "status line (bash fallback)"
    fi
fi

# ── Configure settings.json ──────────────────────────────────
header "Configuring Claude Code settings"

SETTINGS_FILE="${CLAUDE_DIR}/settings.json"

configure_settings() {
    if $DRY_RUN; then
        info "Would configure statusLine in ${SETTINGS_FILE}"
        info "  command: ${STATUS_CMD}"
        return
    fi

    if [[ -f "$SETTINGS_FILE" ]]; then
        # Check if statusLine is already configured
        if python3 -c "
import json, sys
with open('$SETTINGS_FILE') as f:
    s = json.load(f)
existing = s.get('statusLine', {}).get('command', '')
if existing == '$STATUS_CMD':
    sys.exit(0)  # already correct
sys.exit(1)
" 2>/dev/null; then
            ok "settings.json already configured correctly"
            return
        fi

        # Merge into existing settings
        python3 -c "
import json
with open('$SETTINGS_FILE') as f:
    settings = json.load(f)
settings['statusLine'] = {
    'type': 'command',
    'command': '$STATUS_CMD'
}
with open('$SETTINGS_FILE', 'w') as f:
    json.dump(settings, f, indent=2)
    f.write('\n')
"
        ok "Updated statusLine in existing settings.json"
    else
        # Create new settings file
        python3 -c "
import json
settings = {
    'statusLine': {
        'type': 'command',
        'command': '$STATUS_CMD'
    }
}
with open('$SETTINGS_FILE', 'w') as f:
    json.dump(settings, f, indent=2)
    f.write('\n')
"
        ok "Created settings.json with statusLine config"
    fi
}

configure_settings

# ── Done ──────────────────────────────────────────────────────
echo ""
echo -e "${B}${GR}  ┌─────────────────────────────────────────┐${R}"
echo -e "${B}${GR}  │  Installation complete!                  │${R}"
echo -e "${B}${GR}  └─────────────────────────────────────────┘${R}"
echo ""

if $USE_BASH; then
    info "Installed: ${B}bash${R} version (compact, 3 lines)"
else
    info "Installed: ${B}python + Nerd Font${R} version (rich, 6 rows)"
fi

echo ""
info "The status line will appear next time you start ${B}claude${R}."
echo ""

if $nerd_font_note && ! $USE_BASH; then
    echo -e "  ${YE}${B}Note:${R} The default version uses Nerd Font icons."
    echo -e "  If icons look broken, either:"
    echo -e "    1. Install a Nerd Font: ${D}https://www.nerdfonts.com/${R}"
    echo -e "    2. Re-run with: ${B}./install.sh --bash${R}"
    echo ""
fi

echo -e "  ${D}To uninstall, run: ${B}./uninstall.sh${R}"
echo ""
