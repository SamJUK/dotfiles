#!/usr/bin/env bash
# Called only after the full install plan is approved.
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
if ! command -v brew >/dev/null; then
  for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [ -x "$candidate" ]; then eval "$("$candidate" shellenv)"; break; fi
  done
fi
if ! command -v brew >/dev/null; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [ -x "$candidate" ]; then eval "$("$candidate" shellenv)"; break; fi
  done
fi
command -v brew >/dev/null || { echo 'Homebrew is not available.' >&2; exit 1; }
eval "$(brew shellenv)"
command -v stow >/dev/null || brew install stow
brew bundle --file="$HERE/Brewfile"
