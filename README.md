# Claude Code Status Line

A rich, informative status bar for [Claude Code](https://claude.ai/claude-code) that displays model info, token usage, costs, context window, git branch, and more — right in your terminal.

## Screenshots

**Python version (Nerd Font icons, 6-row dashboard):**
```
 󰧭 Claude Sonnet 4.6    v2.1.76    Irvin  session
 ━━━━━━╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌  6% used                94% free    󰘔 1.0M window
   Cost $0.0342        Time 2m14s (api 1m08s)                         + 42   - 7 lines
 󰚋  Session Tokens      ↓ 28.4K in      ↑ 3.2K out     = 31.6K total
 󰁆  Last API Call       ↓ 12.1K in      ↑ 1.4K out         Cache   󰁀 8.2K written    󰁆 19.5K read
 󰌵  /compact  — Toggle compact output to save tokens
```

**Bash version (compact, 3 lines, no special fonts needed):**
```
Claude Sonnet 4.6(claude-sonnet-4-6) v2.1.76 sid:a3b1c2d4 | myproject main
▓▓░░░░░░░░░░░░░░░░░░ 6%(94%left) | $0.0342 | 2m14s(api:1m08s) +42/-7
ctx:1.0M | total:31.6K(in:28.4K/out:3.2K) | last:12.1K/1.4K cw:8.2K cr:19.5K
```

## What it shows

| Info | Description |
|------|-------------|
| Model & version | Current model name, Claude Code version |
| Context window | Progress bar, % used, % remaining, window size |
| Cost & time | Session cost in USD, total duration, API duration |
| Token usage | Session totals (in/out), last API call, cache stats |
| Git branch | Current branch (cached for performance) |
| Lines changed | Lines added/removed in this session |
| Session info | Session name, agent name, worktree, vim mode |
| Tips | Rotating tips about Claude Code features |

## Quick Install

```bash
git clone https://github.com/user/claude-statusline.git
cd claude-statusline
./install.sh
```

That's it! The status line appears automatically on your next `claude` session.

## Install Options

```bash
# Default: Python version with Nerd Font icons (recommended)
./install.sh

# Bash version: no Nerd Font required, uses jq instead
./install.sh --bash

# See what would happen without making changes
./install.sh --dry-run

# Overwrite existing files without prompting
./install.sh --force
```

## Requirements

**Python version (default):**
- Python 3
- A [Nerd Font](https://www.nerdfonts.com/) installed in your terminal

**Bash version (`--bash`):**
- Bash 4+
- [jq](https://jqlang.github.io/jq/) (`brew install jq` / `apt install jq` / `pacman -S jq`)

## Uninstall

```bash
cd claude-statusline
./uninstall.sh
```

This removes the scripts and status line config from `~/.claude/settings.json`. Your other Claude Code settings are preserved.

## Manual Install

If you prefer to install manually:

1. Copy the script to `~/.claude/`:
   ```bash
   cp statusline-command.py ~/.claude/statusline-command.py
   chmod +x ~/.claude/statusline-command.py
   ```

2. Add to `~/.claude/settings.json`:
   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "python3 ~/.claude/statusline-command.py"
     }
   }
   ```

3. Restart Claude Code.

## How it works

Claude Code pipes a JSON object to the status line command via stdin on every update. The script parses this JSON and renders a formatted dashboard. The JSON includes model info, token counts, cost data, context window usage, and session metadata.

## License

MIT
