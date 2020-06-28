alias external_ip='dig +short myip.opendns.com @resolver1.opendns.com'
alias internal_ip="ifconfig | awk '/inet.*broadcast/ { print \$2 }'"
alias ip="echo External IP: $(external_ip); echo Internal IP: \$(internal_ip)"

port() {
    lsof -nP -iTCP:$1 | grep LISTEN
}
