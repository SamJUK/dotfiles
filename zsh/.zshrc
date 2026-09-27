# GITSTATUS_LOG_LEVEL=DEBUG

if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# Pinned in ~/dotfiles/vendor.ini and fetched by install.sh.
export ZSH="${ZSH:-$HOME/.local/share/dotfiles/vendor/oh-my-zsh}"
export ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.config/zsh/custom}"

export ZSH_COMPDUMP="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump-${ZSH_VERSION}"
mkdir -p "${ZSH_COMPDUMP:h}"

ZSH_THEME=""
[[ ! -f "${ZSH_CUSTOM:-$ZSH/custom}/themes/powerlevel10k/powerlevel10k.zsh-theme" ]] || ZSH_THEME="powerlevel10k/powerlevel10k"

zstyle ':omz:update' mode reminder
zstyle ':omz:plugins:nvm' lazy yes
export NVM_DIR="$HOME/.nvm"

plugins=(git npm nvm)
for plugin in zsh-autosuggestions zsh-syntax-highlighting; do
  [[ ! -f "${ZSH_CUSTOM:-$ZSH/custom}/plugins/$plugin/$plugin.plugin.zsh" ]] || plugins+=($plugin)
done
unset plugin

if [[ -r "$ZSH/oh-my-zsh.sh" ]]; then
  source "$ZSH/oh-my-zsh.sh"
else
  PROMPT='%n@%m %~ %# '
fi

if (( $+functions[p10k] )) && [[ -r ~/.p10k.zsh ]]; then source ~/.p10k.zsh; fi


if (( $+functions[compdef] )) && command -v terraform >/dev/null; then
  autoload -U +X bashcompinit && bashcompinit
  complete -o nospace -C "$(command -v terraform)" terraform
fi

# BEGIN SNIPPET: Magento Cloud CLI configuration

export PATH="$HOME/"'.magento-cloud/bin':"$PATH"
if [ -f "$HOME/"'.magento-cloud/shell-config.rc' ]; then . "$HOME/"'.magento-cloud/shell-config.rc'; fi # END SNIPPET

export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
if command -v pyenv >/dev/null; then eval "$(pyenv init -)"; fi

# pnpm
export PNPM_HOME="$HOME/Library/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end

for f in ~/.config/zsh/conf.d/*.zsh(N); do source "$f"; done

typeset -U path

# Added by LM Studio CLI (lms)
export PATH="$PATH:$HOME/.lmstudio/bin"
# End of LM Studio CLI section

