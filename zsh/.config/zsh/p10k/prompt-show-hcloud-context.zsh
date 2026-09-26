#!/usr/bin/env zsh
function prompt_show_hcloud_context() {
  local _hcloud_context
  [[ ! -f ~/.config/hcloud/cli.toml ]] && return
  #[[ -z $_hcloud_context ]] && _hcloud_context=$(hcloud context list | awk '$1 ~ /^\*/ {print $2}')
  [[ -z $_hcloud_context ]] && _hcloud_context=$(awk -F\" '$1 ~ /^active_context/{print $2}' ~/.config/hcloud/cli.toml)
  [[ -n $_hcloud_context ]] || return
  p10k segment -f red3 -i 'H' -t "$_hcloud_context"
}
