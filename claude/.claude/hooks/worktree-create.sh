#!/usr/bin/env bash
# WorktreeCreate hook: worktrees live beside the repo's group, not inside the repo,
# e.g. ~/Projects/personal/foo -> ~/Projects/personal/.worktrees/foo/<name>
set -euo pipefail

input=$(cat)
name=$(jq -r '.name // empty' <<<"$input" | LC_ALL=C tr -c 'A-Za-z0-9._\n-' '-')
cwd=$(jq -r .cwd <<<"$input")
case "$name" in "" | . | ..) echo "Invalid worktree name" >&2; exit 1 ;; esac
git check-ref-format --branch "worktree-$name" >/dev/null || { echo "Invalid worktree name: $name" >&2; exit 1; }

common=$(git -C "$cwd" rev-parse --path-format=absolute --git-common-dir)
# A submodule keeps its git dir under the parent's .git/modules, with core.worktree pointing back.
wt=$(git --git-dir="$common" config core.worktree || true)
main=$(if [ -n "$wt" ]; then cd "$common/$wt" && pwd; else dirname "$common"; fi)
dest="$(dirname "$main")/.worktrees/$(basename "$main")/$name"
branch="worktree-$name"

if [ ! -d "$dest" ]; then
  mkdir -p "$(dirname "$dest")"
  git -C "$main" fetch -q origin >&2 || true
  base=$(git -C "$main" symbolic-ref -q --short refs/remotes/origin/HEAD || echo HEAD)
  if git -C "$main" show-ref -q --verify "refs/heads/$branch"; then
    git -C "$main" worktree add "$dest" "$branch" >&2
  else
    git -C "$main" worktree add -b "$branch" "$dest" "$base" >&2
  fi
  # The hook replaces Claude's own .worktreeinclude handling, so copy those files here.
  if [ -f "$main/.worktreeinclude" ]; then
    git -C "$main" ls-files -z --others --ignored --exclude-from=.worktreeinclude |
      while IFS= read -r -d '' f; do
        mkdir -p "$dest/$(dirname "$f")" || continue
        cp -pPR "$main/$f" "$dest/$f" || echo "Could not copy $f" >&2
      done
  fi
fi

echo "$dest"
