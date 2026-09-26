#!/usr/bin/env bash
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
command -v python3 >/dev/null || { echo 'Python 3 is required. Install the Xcode command-line tools or Python 3 first.' >&2; exit 1; }
exec python3 "$HERE/scripts/install-links.py" --full "$@"
