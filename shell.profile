# Shell Profle
# Include this file in whatever shell you use

# Program Shortcuts
alias phpstorm='open -a phpstorm'
alias sublime='open -a Sublime\ Text'
alias chrome='open -a google\ chrome'
alias f='open -a Finder '
alias fh='open -a Finder .'

# Misc Tooling
alias lmk="say 'Process complete.' & osascript -e 'display notification \"Process Complete\" with title \"Process Complete\"'"
alias ql='qlmanage -p 2>/dev/null'
alias password='openssl rand -base64 14'
alias own='sudo chown -Rv $(id -u):$(id -g)'

# Network
port() { lsof -nP -iTCP:$1 | grep LISTEN }
alias external_ip='curl -ks -m 3 https://sdj.pw/ip/s/'
alias internal_ip="ifconfig | awk '/inet.*broadcast/ { print \$2 }'"
alias ip="echo External IP: $(external_ip); echo Internal IP: \$(internal_ip)"

# SSH
alias sshk='ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no'

# Git
alias gittree='git log --graph --pretty=oneline --abbrev-commit'

# Iterm Config
source $HOME/.iterm2_shell_integration.zsh
function iterm2_print_user_vars() {
  iterm2_set_user_var phpVersion $(php -v | awk '/^PHP/ { print $2 }')
  iterm2_set_user_var nodeVersion $(node -v)
  iterm2_set_user_var externalIP $external_ip
  iterm2_set_user_var internalIP $internal_ip
}
