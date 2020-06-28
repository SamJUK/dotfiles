# Load all our dotfiles
for f in $HOME/.dotfiles/src/*.sh; do source $f; done

# Allow local install overrides + extensions
test -e "$HOME/.zprofile.local" && source "$HOME/.zprofile.local"
