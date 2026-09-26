#!/usr/bin/env bash
# Symlinked configuration changes become live when its checkout is fast-forwarded.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
[ -t 0 ] || { echo 'Run updates interactively so incoming changes can be reviewed.' >&2; exit 1; }
for repo in "$HERE" "${DOTFILES_PRIVATE:-$HOME/dotfiles-private}" "${BED_DEV_TOOLS:-$HOME/Projects/bed/dev-tools}"; do
  [ -e "$repo/.git" ] || continue
  if ! upstream=$(git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null); then
    echo "$repo: no upstream configured; skipped"
    continue
  fi
  git -C "$repo" fetch --quiet
  incoming=$(git -C "$repo" log --oneline "HEAD..$upstream")
  if [ -z "$incoming" ]; then echo "$repo: no incoming commits"; continue; fi
  echo "== $repo incoming"
  echo "$incoming"
  git -C "$repo" diff --stat "HEAD..$upstream"
  read -rp 'Show full diff? [y/N] ' answer
  if [[ "$answer" = [yY] ]]; then git -C "$repo" diff "HEAD..$upstream"; fi
  read -rp "Fast-forward $repo? [y/N] " answer
  [[ "$answer" = [yY] ]] || continue
  git -C "$repo" merge --ff-only "$upstream"
done
"$HERE/install.sh"
