alias own='sudo chown -Rv $(id -u):$(id -g)'
alias password='openssl rand -base64 14'
alias lmk="say 'Process complete.' & osascript -e 'display notification \"Process Complete\" with title \"Process Complete\"'"

# Create a new directory and enter it
function md() {
  mkdir -p "$@" && cd "$@"
}
