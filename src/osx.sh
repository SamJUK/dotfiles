# Finder shortcuts
alias f='open -a Finder '
alias fh='open -a Finder .'

# Quicklook at files from terminal
alias ql='qlmanage -p 2>/dev/null'

# Copy to clipboard
alias c="tr -d '\n' | pbcopy"

# Start ScreenSaver. This will lock the screen if locking is enabled.
alias ss="open /System/Library/Frameworks/ScreenSaver.framework/Versions/A/Resources/ScreenSaverEngine.app"

# Iterm 2 shell integration
test -e "${HOME}/.iterm2_shell_integration.zsh" && source "${HOME}/.iterm2_shell_integration.zsh"
function iterm2_print_user_vars() {
  iterm2_set_user_var phpVersion $(php -v | awk '/^PHP/ { print $2 }')
  iterm2_set_user_var nodeVersion $(node -v)
  iterm2_set_user_var externalIP $(external_ip)
  iterm2_set_user_var internalIP $(internal_ip)
}
