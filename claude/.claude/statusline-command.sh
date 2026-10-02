#!/bin/bash
# Claude Code status line — mirrors Powerlevel10k left prompt elements:
#   [account]  dir  vcs(git branch + status)  |  model  context%

input=$(cat)

# --- Directory (from Claude context, falling back to pwd) ---
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')
[ -z "$cwd" ] && cwd=$(pwd)

# Abbreviate $HOME to ~
home="$HOME"
display_dir="${cwd/#$home/~}"

# --- Git branch + status ---
git_info=""
if git -C "$cwd" rev-parse --git-dir --no-optional-locks > /dev/null 2>&1; then
  branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null || git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
  if [ -n "$branch" ]; then
    # Truncate long branch names like p10k does (>32 chars → keep first 12…last 12)
    if [ "${#branch}" -gt 32 ]; then
      branch="${branch:0:12}…${branch: -12}"
    fi
    git_info=" \033[38;5;76m $branch\033[0m"

    # Staged / unstaged / untracked counts
    staged=$(git -C "$cwd" diff --no-optional-locks --cached --name-only 2>/dev/null | wc -l | tr -d ' ')
    unstaged=$(git -C "$cwd" diff --no-optional-locks --name-only 2>/dev/null | wc -l | tr -d ' ')
    untracked=$(git -C "$cwd" ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')

    [ "$staged" -gt 0 ]    && git_info="${git_info} \033[38;5;178m+${staged}\033[0m"
    [ "$unstaged" -gt 0 ]  && git_info="${git_info} \033[38;5;178m!${unstaged}\033[0m"
    [ "$untracked" -gt 0 ] && git_info="${git_info} \033[38;5;39m?${untracked}\033[0m"
  fi
fi

# --- Model ---
model=$(printf '%s' "$input" | jq -r '.model.display_name // empty')

# --- Context window ---
used_pct=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // empty')

# --- Assemble output ---
# Account tag: the claude-work alias sets CLAUDE_CONFIG_DIR=~/.claude-work
case "$CLAUDE_CONFIG_DIR" in
  *claude-work*) printf '\033[38;5;208m[work]\033[0m ' ;;
  *)             printf '\033[38;5;141m[personal]\033[0m ' ;;
esac

# Directory in cyan (matches POWERLEVEL9K_DIR_FOREGROUND=31)
printf '\033[38;5;31m%s\033[0m' "$display_dir"

# Git info (already coloured above)
[ -n "$git_info" ] && printf '%b' "$git_info"

# Separator
printf ' \033[38;5;242m|\033[0m'

# Model
[ -n "$model" ] && printf ' \033[38;5;103m%s\033[0m' "$model"

# Context usage
if [ -n "$used_pct" ]; then
  used_int=$(printf '%.0f' "$used_pct")
  # Colour: green <50%, yellow 50-80%, red >80%
  if [ "$used_int" -lt 50 ]; then
    ctx_color=76
  elif [ "$used_int" -lt 80 ]; then
    ctx_color=178
  else
    ctx_color=160
  fi
  printf ' \033[38;5;%dm%d%%\033[0m' "$ctx_color" "$used_int"
fi
