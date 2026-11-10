#!/usr/bin/env bash
# WorktreeRemove hook: never loses committed or tracked work. `git worktree remove` refuses
# dirty or untracked trees, `git branch -d` refuses unmerged branches, and a detached HEAD
# must be held by some ref. Gitignored files (dependencies, a copied .env) are disposable.
set -euo pipefail

path=$(jq -r .worktree_path)
[ -d "$path" ] || exit 0

common=$(git -C "$path" rev-parse --path-format=absolute --git-common-dir)
# A submodule keeps its git dir under the parent's .git/modules, with core.worktree pointing back.
wt=$(git --git-dir="$common" config core.worktree || true)
main=$(if [ -n "$wt" ]; then cd "$common/$wt" && pwd; else dirname "$common"; fi)
branch=$(git -C "$path" symbolic-ref -q --short HEAD || true)

if [ -z "$branch" ] && [ -z "$(git -C "$path" for-each-ref --contains HEAD --count=1)" ]; then
  echo "Kept $path: its detached HEAD has commits no branch or tag holds." >&2
  exit 1
fi

git -C "$main" worktree remove "$path"

if [ -n "$branch" ] && ! git -C "$main" branch -d "$branch" >&2 2>/dev/null; then
  echo "Kept branch $branch: it has commits not merged anywhere." >&2
fi
