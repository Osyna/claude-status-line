#!/usr/bin/env bash
# Claude Code status line - maximum information display
# Uses a single jq call for performance

input=$(cat)

# Extract ALL fields in one jq call
eval "$(echo "$input" | jq -r '
  @sh "model=\(.model.display_name // "unknown")",
  @sh "model_id=\(.model.id // "")",
  @sh "version=\(.version // "")",
  @sh "cwd=\(.workspace.current_dir // .cwd // "")",
  @sh "project_dir=\(.workspace.project_dir // "")",
  @sh "session_id=\(.session_id // "")",
  @sh "session_name=\(.session_name // "")",
  @sh "cost_usd=\(.cost.total_cost_usd // 0)",
  @sh "duration_ms=\(.cost.total_duration_ms // 0)",
  @sh "api_duration_ms=\(.cost.total_api_duration_ms // 0)",
  @sh "lines_added=\(.cost.total_lines_added // 0)",
  @sh "lines_removed=\(.cost.total_lines_removed // 0)",
  @sh "total_in=\(.context_window.total_input_tokens // 0)",
  @sh "total_out=\(.context_window.total_output_tokens // 0)",
  @sh "ctx_size=\(.context_window.context_window_size // 0)",
  @sh "used_pct=\(.context_window.used_percentage // "")",
  @sh "remaining_pct=\(.context_window.remaining_percentage // "")",
  @sh "cur_in=\(.context_window.current_usage.input_tokens // "")",
  @sh "cur_out=\(.context_window.current_usage.output_tokens // "")",
  @sh "cache_write=\(.context_window.current_usage.cache_creation_input_tokens // "")",
  @sh "cache_read=\(.context_window.current_usage.cache_read_input_tokens // "")",
  @sh "exceeds_200k=\(.exceeds_200k_tokens // false)",
  @sh "vim_mode=\(.vim.mode // "")",
  @sh "agent_name=\(.agent.name // "")",
  @sh "worktree_name=\(.worktree.name // "")",
  @sh "worktree_branch=\(.worktree.branch // "")",
  @sh "output_style=\(.output_style.name // "")"
' 2>/dev/null)"

# --- ANSI colors ---
R="\033[0m"  # reset
B="\033[1m"  # bold
D="\033[2m"  # dim
CY="\033[36m"; GR="\033[32m"; YE="\033[33m"; RE="\033[31m"
MA="\033[35m"; BL="\033[34m"; WH="\033[37m"

# --- Helper: format token numbers with K/M suffix ---
fmt() {
  local n=$1
  if [ -z "$n" ] || [ "$n" = "null" ] || [ "$n" = "" ]; then echo "0"; return; fi
  if [ "$n" -ge 1000000 ] 2>/dev/null; then
    printf "%.1fM" "$(echo "scale=1; $n / 1000000" | bc 2>/dev/null || echo 0)"
  elif [ "$n" -ge 1000 ] 2>/dev/null; then
    printf "%.1fK" "$(echo "scale=1; $n / 1000" | bc 2>/dev/null || echo 0)"
  else
    echo "$n"
  fi
}

# --- Format duration from ms ---
fmt_dur() {
  local ms=$1 s m h
  [ -z "$ms" ] || [ "$ms" = "0" ] && { echo "0s"; return; }
  s=$((ms / 1000))
  if [ "$s" -ge 3600 ]; then
    h=$((s / 3600)); m=$(( (s % 3600) / 60 )); printf "%dh%dm" "$h" "$m"
  elif [ "$s" -ge 60 ]; then
    m=$((s / 60)); printf "%dm%ds" "$m" "$((s % 60))"
  else
    printf "%ds" "$s"
  fi
}

# --- Build progress bar ---
bar() {
  local pct=$1 width=20 filled empty
  [ -z "$pct" ] && pct=0
  filled=$((pct * width / 100))
  empty=$((width - filled))
  local color="$GR"
  [ "$pct" -ge 50 ] 2>/dev/null && color="$YE"
  [ "$pct" -ge 80 ] 2>/dev/null && color="$RE"
  printf "${color}"
  [ "$filled" -gt 0 ] && printf "%${filled}s" | tr ' ' '▓'
  [ "$empty" -gt 0 ] && printf "%${empty}s" | tr ' ' '░'
  printf "${R}"
}

# ============================================================
# LINE 1: Model, version, session info, git branch
# ============================================================
line1=""

# Model + ID
line1+="$(printf "${B}${CY}%s${R}" "$model")"
[ -n "$model_id" ] && line1+="$(printf "${D}(%s)${R}" "$model_id")"

# Version
[ -n "$version" ] && line1+="$(printf " ${D}v%s${R}" "$version")"

# Session ID (short)
[ -n "$session_id" ] && line1+="$(printf " ${D}sid:%s${R}" "${session_id:0:8}")"

# Session name
[ -n "$session_name" ] && line1+="$(printf " ${MA}[%s]${R}" "$session_name")"

# Agent
[ -n "$agent_name" ] && line1+="$(printf " ${YE}agent:%s${R}" "$agent_name")"

# Worktree
if [ -n "$worktree_name" ]; then
  wt="$worktree_name"
  [ -n "$worktree_branch" ] && wt+=":$worktree_branch"
  line1+="$(printf " ${BL}wt:%s${R}" "$wt")"
fi

# Vim mode
if [ -n "$vim_mode" ]; then
  if [ "$vim_mode" = "NORMAL" ]; then
    line1+="$(printf " ${GR}[NOR]${R}")"
  else
    line1+="$(printf " ${YE}[%s]${R}" "$vim_mode")"
  fi
fi

# Output style
[ -n "$output_style" ] && [ "$output_style" != "default" ] && \
  line1+="$(printf " ${D}style:%s${R}" "$output_style")"

# Directory
dir_name="${cwd##*/}"
line1+="$(printf " ${D}|${R} ${WH}%s${R}" "$dir_name")"

# Git branch (cached)
CACHE_FILE="/tmp/cc-statusline-git-cache"
if [ ! -f "$CACHE_FILE" ] || [ $(($(date +%s) - $(stat -c %Y "$CACHE_FILE" 2>/dev/null || stat -f %m "$CACHE_FILE" 2>/dev/null || echo 0))) -gt 5 ]; then
  git_branch=$(git -C "$cwd" branch --show-current 2>/dev/null || true)
  echo "$git_branch" > "$CACHE_FILE"
else
  git_branch=$(cat "$CACHE_FILE")
fi
[ -n "$git_branch" ] && line1+="$(printf " ${GR}%s${R}" "$git_branch")"

printf '%b\n' "$line1"

# ============================================================
# LINE 2: Context bar + usage % + cost + duration + lines
# ============================================================
line2=""

# Progress bar
pct_int=0
[ -n "$used_pct" ] && [ "$used_pct" != "null" ] && pct_int=${used_pct%.*}
line2+="$(bar "$pct_int")"

# Context percentage
pct_color="$GR"
[ "$pct_int" -ge 50 ] 2>/dev/null && pct_color="$YE"
[ "$pct_int" -ge 80 ] 2>/dev/null && pct_color="$RE"
rem_str=""
[ -n "$remaining_pct" ] && [ "$remaining_pct" != "null" ] && rem_str="${remaining_pct%.*}%left"
line2+="$(printf " ${pct_color}%s%%${R}" "$pct_int")"
[ -n "$rem_str" ] && line2+="$(printf "${D}(%s)${R}" "$rem_str")"

# Exceeds 200k warning
[ "$exceeds_200k" = "true" ] && line2+="$(printf " ${RE}${B}!>200K${R}")"

# Cost
cost_fmt=$(printf '%.4f' "$cost_usd" 2>/dev/null || echo "0.0000")
line2+="$(printf " ${D}|${R} ${YE}\$%s${R}" "$cost_fmt")"

# Duration (total + API)
line2+="$(printf " ${D}|${R} %s" "$(fmt_dur "$duration_ms")")"
[ -n "$api_duration_ms" ] && [ "$api_duration_ms" != "0" ] && \
  line2+="$(printf "${D}(api:%s)${R}" "$(fmt_dur "$api_duration_ms")")"

# Lines changed
if [ "${lines_added:-0}" -gt 0 ] || [ "${lines_removed:-0}" -gt 0 ]; then
  line2+="$(printf " ${GR}+%s${R}/${RE}-%s${R}" "$lines_added" "$lines_removed")"
fi

printf '%b\n' "$line2"

# ============================================================
# LINE 3: Token details
# ============================================================
line3=""

# Context window size
[ -n "$ctx_size" ] && [ "$ctx_size" != "0" ] && \
  line3+="$(printf "ctx:${WH}%s${R}" "$(fmt "$ctx_size")")"

# Cumulative session tokens
total_tok=$(( ${total_in:-0} + ${total_out:-0} ))
if [ "$total_tok" -gt 0 ] 2>/dev/null; then
  line3+="$(printf " ${D}|${R} total:${WH}%s${R}(${GR}in:%s${R}/${RE}out:%s${R})" \
    "$(fmt "$total_tok")" "$(fmt "$total_in")" "$(fmt "$total_out")")"
fi

# Last call tokens
if [ -n "$cur_in" ] && [ -n "$cur_out" ]; then
  line3+="$(printf " ${D}|${R} last:${GR}%s${R}/${RE}%s${R}" \
    "$(fmt "$cur_in")" "$(fmt "$cur_out")")"
  # Cache info
  if [ -n "$cache_write" ] && [ "$cache_write" != "0" ] && [ "$cache_write" != "null" ]; then
    line3+="$(printf " ${YE}cw:%s${R}" "$(fmt "$cache_write")")"
  fi
  if [ -n "$cache_read" ] && [ "$cache_read" != "0" ] && [ "$cache_read" != "null" ]; then
    line3+="$(printf " ${D}cr:%s${R}" "$(fmt "$cache_read")")"
  fi
fi

printf '%b\n' "$line3"
