#!/usr/bin/env python3
"""Claude Code status line — Nerd Font dashboard, human-readable, right-aligned."""
import json, sys, os, subprocess, time, hashlib, re

data = json.load(sys.stdin)

# ── Data extraction ──────────────────────────────────────────
model      = data.get("model", {})
model_name = model.get("display_name", "?")
model_id   = model.get("id", "")
version    = data.get("version", "")
ws         = data.get("workspace", {})
cwd        = ws.get("current_dir", data.get("cwd", ""))
session_id = data.get("session_id", "")
session_name = data.get("session_name", "")

cost_d      = data.get("cost", {})
cost_usd    = cost_d.get("total_cost_usd", 0) or 0
duration_ms = cost_d.get("total_duration_ms", 0) or 0
api_dur_ms  = cost_d.get("total_api_duration_ms", 0) or 0
lines_added   = cost_d.get("total_lines_added", 0) or 0
lines_removed = cost_d.get("total_lines_removed", 0) or 0

ctx         = data.get("context_window", {})
total_in    = ctx.get("total_input_tokens", 0) or 0
total_out   = ctx.get("total_output_tokens", 0) or 0
ctx_size    = ctx.get("context_window_size", 0) or 0
used_pct    = ctx.get("used_percentage") or 0
remaining_pct = ctx.get("remaining_percentage") or 0
cur         = ctx.get("current_usage") or {}
cur_in      = cur.get("input_tokens")
cur_out     = cur.get("output_tokens")
cache_write = cur.get("cache_creation_input_tokens")
cache_read  = cur.get("cache_read_input_tokens")

exceeds_200k = data.get("exceeds_200k_tokens", False)
vim_mode     = (data.get("vim") or {}).get("mode", "")
agent_name   = (data.get("agent") or {}).get("name", "")
wt           = data.get("worktree") or {}
wt_name      = wt.get("name", "")
wt_branch    = wt.get("branch", "")
out_style    = (data.get("output_style") or {}).get("name", "")

# ── Terminal width ───────────────────────────────────────────
try:
    COLS = os.get_terminal_size().columns
except:
    COLS = 120

# ── ANSI ─────────────────────────────────────────────────────
R   = "\033[0m"
B   = "\033[1m"
D   = "\033[2m"
IT  = "\033[3m"
CY  = "\033[36m"; GR  = "\033[32m"; YE  = "\033[33m"; RE  = "\033[31m"
MA  = "\033[35m"; BL  = "\033[34m"; WH  = "\033[37m"
BCY = "\033[96m"; BGR = "\033[92m"; BYE = "\033[93m"; BRE = "\033[91m"
BMA = "\033[95m"; BBL = "\033[94m"; BWH = "\033[97m"
BG_CY  = "\033[48;5;23m"
BG_MA  = "\033[48;5;53m"
BG_YE  = "\033[48;5;58m"
BG_GR  = "\033[48;5;22m"
BG_BL  = "\033[48;5;17m"
BG_DK  = "\033[48;5;236m"

# ── Nerd Font icons ──────────────────────────────────────────
I = {
    "brain":  "\U000f09ed",  # 󰧭
    "tag":    "\uf412",      #
    "dir":    "\uf07c",      #
    "git":    "\ue725",      #
    "robot":  "\U000f06a9",  # 󰚩
    "tree":   "\uf1bb",      #
    "vim":    "\ue62b",      #
    "dollar": "\uf155",      #
    "clock":  "\uf017",      #
    "api":    "\U000f0318",  # 󰌘
    "plus":   "\uf067",      #
    "minus":  "\uf068",      #
    "down":   "\uf063",      #  (input tokens)
    "up":     "\uf062",      #  (output tokens)
    "db":     "\uf1c0",      #  (cache)
    "write":  "\U000f0040",  # 󰁀 (cache write)
    "read":   "\U000f0046",  # 󰁆 (cache read)
    "bulb":   "\U000f0335",  # 󰌵
    "warn":   "\uf071",      #
    "paint":  "\uf1fc",      #
    "name":   "\uf02b",      #
    "code":   "\uf121",      #
    "gauge":  "\U000f0614",  # 󰘔 (context gauge)
    "zap":    "\uf0e7",      #  (last call)
    "sigma":  "\U000f068b",  # 󰚋 (total)
    "sep":    "\ue0b1",      #  (powerline thin)
}

# ── Helpers ──────────────────────────────────────────────────
def fmt(n):
    if n is None or n == 0:
        return "0"
    if n >= 1_000_000:
        return f"{n/1_000_000:.1f}M"
    if n >= 1_000:
        return f"{n/1_000:.1f}K"
    return str(n)

def fmt_dur(ms):
    if not ms:
        return "0s"
    s = int(ms) // 1000
    if s >= 3600:
        return f"{s//3600}h{(s%3600)//60}m"
    if s >= 60:
        return f"{s//60}m{s%60}s"
    return f"{s}s"

def visible_len(s):
    """Length of string without ANSI escape codes."""
    return len(re.sub(r'\033\[[0-9;]*m', '', s))

def pad_right(left, right):
    """Print left content, pad with spaces, then right content."""
    gap = COLS - visible_len(left) - visible_len(right) - 1
    if gap < 2:
        gap = 2
    print(f"{left}{' ' * gap}{right}")

def pill(text, icon, fg, bg):
    return f"{bg}{fg}{B} {icon} {text} {R}"

def get_git_branch(cwd):
    cache = "/tmp/cc-statusline-git-cache"
    try:
        if os.path.exists(cache) and (time.time() - os.path.getmtime(cache)) <= 5:
            with open(cache) as f:
                return f.read().strip()
    except:
        pass
    try:
        branch = subprocess.check_output(
            ["git", "-C", cwd, "branch", "--show-current"],
            stderr=subprocess.DEVNULL, text=True
        ).strip()
    except:
        branch = ""
    try:
        with open(cache, "w") as f:
            f.write(branch)
    except:
        pass
    return branch

def progress_bar(pct, width=30):
    pct = int(pct)
    color = BRE if pct >= 80 else BYE if pct >= 50 else BGR
    dim_color = RE if pct >= 80 else YE if pct >= 50 else GR
    filled = pct * width // 100
    empty = width - filled
    return f"{color}{'━' * filled}{D}{dim_color}{'╌' * empty}{R}"

# ── Tips ─────────────────────────────────────────────────────
TIPS = [
    ("/compact",    "Toggle compact output to save tokens"),
    ("/cost",       "Show detailed cost & token breakdown"),
    ("/context",    "See how much context window you've used"),
    ("/clear",      "Clear history and start a fresh session"),
    ("/memory",     "View or manage project memory"),
    ("/review",     "Ask Claude to review recent changes"),
    ("/init",       "Create a CLAUDE.md for project context"),
    ("/vim",        "Toggle vim keybindings in the editor"),
    ("/model",      "Switch models mid-session"),
    ("/doctor",     "Run diagnostics on your setup"),
    ("/statusline", "Customize this status bar"),
    ("/help",       "Show all commands and shortcuts"),
    ("/config",     "Open Claude Code settings"),
    ("/listen",     "Watch a command and respond to changes"),
    ("/diff",       "See all file changes in this session"),
    ("Ctrl+R",      "Search and reuse previous prompts"),
    ("Ctrl+O",      "Toggle transcript view"),
    ("Ctrl+T",      "Toggle the task/todo panel"),
    ("Shift+Tab",   "Cycle: Ask / Edit / Agent modes"),
    ("Ctrl+G",      "Edit prompt in $EDITOR"),
    ("Ctrl+S",      "Stash current input for later"),
    ("@ files",     "Mention files in your prompt to attach them"),
    ("--resume",    "Continue your last conversation"),
    ("--print",     "Non-interactive scripted usage"),
    ("CLAUDE.md",   "Add project context for Claude"),
    ("--worktree",  "Work in an isolated git branch"),
    ("Hooks",       "Run commands on Claude events"),
    ("MCP",         "Add external tool integrations"),
    ("Escape",      "Cancel current prompt input"),
]

def get_tip():
    seed = int(time.time() // 30)
    h = int(hashlib.md5(f"{session_id}{seed}".encode()).hexdigest(), 16)
    return TIPS[h % len(TIPS)]

# ═══════════════════════════════════════════════════════════════
# Build dashboard
# ═══════════════════════════════════════════════════════════════

dir_name   = os.path.basename(cwd) if cwd else "?"
git_branch = get_git_branch(cwd) if cwd else ""
pct_int    = int(used_pct) if used_pct else 0
pct_color  = BRE if pct_int >= 80 else BYE if pct_int >= 50 else BGR
rem_int    = int(remaining_pct) if remaining_pct else 0
total_tok  = total_in + total_out

# ─────────────────────────────────────────────────────────────
# ROW 1:  Model pill  v2.1.76          dir  git branch
# ─────────────────────────────────────────────────────────────
left1 = pill(model_name, I["brain"], BCY, BG_CY)
if version:
    left1 += f"  {D}{I['tag']} v{version}{R}"

# Optional badges
badges = []
if session_name:
    badges.append(pill(session_name, I["name"], BMA, BG_MA))
if agent_name:
    badges.append(pill(agent_name, I["robot"], BYE, BG_YE))
if wt_name:
    wt_lbl = f"{wt_name}:{wt_branch}" if wt_branch else wt_name
    badges.append(pill(wt_lbl, I["tree"], BBL, BG_BL))
if vim_mode:
    vc, vbg = (BGR, BG_GR) if vim_mode == "NORMAL" else (BYE, BG_YE)
    badges.append(pill(vim_mode, I["vim"], vc, vbg))
if out_style and out_style != "default":
    badges.append(f"{D}{I['paint']} {out_style}{R}")
if badges:
    left1 += "  " + "  ".join(badges)

right1 = f"{BYE}{I['dir']}{R} {B}{BWH}{dir_name}{R}"
if git_branch:
    right1 += f"   {BGR}{I['git']} {git_branch}{R}"

pad_right(left1, right1)

# ─────────────────────────────────────────────────────────────
# ROW 2:  ━━━╌╌╌  6% used · 94% free · 1.0M window
# ─────────────────────────────────────────────────────────────
bar = progress_bar(pct_int)
warn = f"   {BRE}{B}{I['warn']} CONTEXT >200K{R}" if exceeds_200k else ""

left2 = f" {bar}  {pct_color}{B}{pct_int}%{R} {D}used{R}"
right2 = f"{D}{rem_int}% free{R}   {D}{I['gauge']}{R} {BWH}{fmt(ctx_size)}{R} {D}window{R}{warn}"

pad_right(left2, right2)

# ─────────────────────────────────────────────────────────────
# ROW 3:  $ Cost    Clock Time (api)         +added  -removed
# ─────────────────────────────────────────────────────────────
cost_str = f"${cost_usd:.4f}" if cost_usd < 10 else f"${cost_usd:.2f}"
dur = fmt_dur(duration_ms)
api = f" {D}(api {fmt_dur(api_dur_ms)}){R}" if api_dur_ms else ""

left3 = f" {BYE}{I['dollar']}{R}  {D}Cost{R} {BWH}{B}{cost_str}{R}       {BCY}{I['clock']}{R}  {D}Time{R} {WH}{dur}{R}{api}"

right3 = ""
if lines_added or lines_removed:
    right3 = f"{BGR}{I['plus']} {lines_added}{R}   {BRE}{I['minus']} {lines_removed}{R} {D}lines{R}"

pad_right(left3, right3)

# ─────────────────────────────────────────────────────────────
# ROW 4:  Session tokens: ↓in  ↑out  = total
# ─────────────────────────────────────────────────────────────
if total_tok > 0:
    left4 = (
        f" {BMA}{I['sigma']}{R}  {D}Session Tokens{R}     "
        f"{BGR}{I['down']} {fmt(total_in)}{R} {D}in{R}     "
        f"{BRE}{I['up']} {fmt(total_out)}{R} {D}out{R}     "
        f"{D}={R} {B}{BWH}{fmt(total_tok)}{R} {D}total{R}"
    )
    print(left4)

# ─────────────────────────────────────────────────────────────
# ROW 5:  Last API call: ↓in  ↑out        Cache: ↑written  ↓read
# ─────────────────────────────────────────────────────────────
if cur_in is not None and cur_out is not None:
    left5 = (
        f" {BBL}{I['zap']}{R}  {D}Last API Call{R}      "
        f"{BGR}{I['down']} {fmt(cur_in)}{R} {D}in{R}     "
        f"{BRE}{I['up']} {fmt(cur_out)}{R} {D}out{R}"
    )

    cache_parts = []
    if cache_write:
        cache_parts.append(f"{BYE}{I['write']} {fmt(cache_write)}{R} {D}written{R}")
    if cache_read:
        cache_parts.append(f"{D}{I['read']} {fmt(cache_read)}{R} {D}read{R}")

    right5 = ""
    if cache_parts:
        right5 = f"{CY}{I['db']}{R}  {D}Cache{R}   {'    '.join(cache_parts)}"

    pad_right(left5, right5)

# ─────────────────────────────────────────────────────────────
# ROW 6:  Tip
# ─────────────────────────────────────────────────────────────
cmd, desc = get_tip()
print(f" {YE}{I['bulb']}{R}  {B}{BWH}{cmd}{R}  {D}{IT}— {desc}{R}")
