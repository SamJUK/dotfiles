#!/usr/bin/env zsh
function prompt_show_magento_version() {
  _p9k_upglob 'composer.(json|lock)' && return
  local dir=$_p9k__parent_dirs[$?]
  local lock=$dir/composer.lock
  local json=$dir/composer.json

  if [[ -r $lock ]]; then
    if ! _p9k_cache_stat_get $0 $lock; then
      local v=$(grep -E -A1 "\"name\": \"magento/product-(community|enterprise)-edition\"" "$lock" 2> /dev/null | awk -F\" 'END{print $4}')
      _p9k_cache_stat_set "$v"
    fi
  elif [[ -r $json ]]; then
    if ! _p9k_cache_stat_get $0 $json; then
      local v=$(grep -E 'magento/product-(community|enterprise)-edition' "$json" 2> /dev/null | awk -F\" '{print $4}')
      _p9k_cache_stat_set "$v"
    fi
  fi

  [[ -n $_p9k__cache_val[1] ]] || return
  p10k segment -f orangered1 -i '' -t "${_p9k__cache_val[1]}"
}
