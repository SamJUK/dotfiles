# Homebrew supports both Apple Silicon and Intel installations.
if ! command -v brew >/dev/null; then
  for brew_bin in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [[ -x "$brew_bin" ]]; then eval "$("$brew_bin" shellenv)"; break; fi
  done
  unset brew_bin
else
  eval "$(brew shellenv)"
fi

export WORKON_HOME=$HOME/.virtualenvs
if [[ -n ${HOMEBREW_PREFIX:-} && -r "$HOMEBREW_PREFIX/bin/virtualenvwrapper.sh" ]]; then
  export VIRTUALENVWRAPPER_PYTHON="$HOMEBREW_PREFIX/bin/python3"
  source "$HOMEBREW_PREFIX/bin/virtualenvwrapper.sh"
fi

path=(
  $HOME/dotfiles/bin
  $HOME/dotfiles-private/bin(N)
  $HOME/.local/bin
  $HOME/.composer/vendor/bin
  $HOME/.magento-cloud/bin
  $HOME/Projects/personal/warden/bin
  $HOME/go/bin
  $HOME/.cargo/bin
  $path
)

if [[ -n ${HOMEBREW_PREFIX:-} ]]; then
  path=("$HOMEBREW_PREFIX/opt/openjdk/bin"(N) $path)
  fpath=("$HOMEBREW_PREFIX/share/zsh/functions"(N) $fpath)
fi
typeset -U path fpath

# Aliases
alias pe='[[ -f venv/bin/activate ]] && source venv/bin/activate || [[ -f .venv/bin/activate ]] && source .venv/bin/activate'
alias sail='[ -f sail ] && bash sail || bash vendor/bin/sail'
alias sshp='ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no'
alias wip='git commit -m "wip"; git push'
alias wipa='git add .; git commit -m "wip"; git push'
alias lmk="osascript -e 'display notification \"Process Complete\" with title \"LMK\" sound name \"default\"'"
alias vim='nvim'
alias gs="git status"
alias lg="lazygit"
alias phpstorm='open -a "PHPStorm"'
alias subl='open -a "Sublime Text"'
alias brave='open -a Brave'
alias code='open -a "Visual Studio Code"'
alias f='open -a Finder'
alias fh='open -a Finder .'
alias ql='qlmanage -p 2>/dev/null'
alias own='sudo chown -Rv $(id -u):$(id -g)'
alias wpscan='docker run -it --rm wpscanteam/wpscan'
alias pbmodules='npx https://github.com/commerce-docs/pbmodules.git'
alias warden-console="warden shell -c \"n98-magerun dev:console\""

# Added by OrbStack: command-line tools and integration
# This won't be added again if you remove it.
source ~/.orbstack/shell/init.zsh 2>/dev/null || :
