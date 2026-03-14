#!/usr/bin/env bash
# Uninstall Claude Code Status Line
set -euo pipefail

R='\033[0m'; B='\033[1m'; GR='\033[32m'; YE='\033[33m'; CY='\033[36m'
info()  { echo -e "  ${CY}▸${R} $*"; }
ok()    { echo -e "  ${GR}✓${R} $*"; }
warn()  { echo -e "  ${YE}⚠${R} $*"; }

CLAUDE_DIR="${HOME}/.claude"

echo ""
echo -e "${B}${CY}  Uninstalling Claude Code Status Line${R}"
echo ""

# Remove scripts
for f in statusline-command.py statusline-command.sh; do
    if [[ -f "${CLAUDE_DIR}/${f}" ]]; then
        rm "${CLAUDE_DIR}/${f}"
        ok "Removed ${CLAUDE_DIR}/${f}"
    fi
done

# Remove git cache
rm -f /tmp/cc-statusline-git-cache

# Remove statusLine from settings.json
SETTINGS="${CLAUDE_DIR}/settings.json"
if [[ -f "$SETTINGS" ]] && python3 -c "
import json
with open('$SETTINGS') as f:
    s = json.load(f)
if 'statusLine' in s:
    del s['statusLine']
    with open('$SETTINGS', 'w') as f:
        json.dump(s, f, indent=2)
        f.write('\n')
    print('removed')
" 2>/dev/null | grep -q removed; then
    ok "Removed statusLine config from settings.json"
else
    info "No statusLine config found in settings.json"
fi

echo ""
ok "Uninstalled. Status line will be gone on next ${B}claude${R} session."
echo ""
