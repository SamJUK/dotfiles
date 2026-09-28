#!/usr/bin/env bash
# Unevaluated LESS division in compiled CSS: less.php v5 emits `a/b` literally and browsers drop
# the declaration. Run from the Magento root after a static deploy: bash < css-division.sh
find pub/static -name '*.css' -print0 \
  | xargs -0 grep -oHE '[a-z-]+:[^;{}]*[0-9](%|px|em|rem)?[[:space:]]*/[[:space:]]*[0-9][^;{}]*' \
  | grep -vE ':(font|background|aspect-ratio|grid-[a-z-]+):|calc\(|url\(|rgba?\(|hsla?\(' \
  | sort -u
