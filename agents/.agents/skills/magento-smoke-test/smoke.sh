#!/usr/bin/env bash
# Quick Magento health check: deploy as production would, load key pages, catch new errors.
#
#   smoke.sh [project-root] [--url BASE_URL]
#
# Runs setup:upgrade, setup:di:compile and setup:static-content:deploy (SCD_LANGS="en_GB en_US"
# for other locales), then status checks, page loads and the error logs. Refused unless env.php
# points at a local database. --url overrides the configured base URL.
# Exit code = number of failed checks.
set -uo pipefail

ROOT=. URL=''
while [ $# -gt 0 ]; do
  case "$1" in
    --url) URL=${2:?--url needs a URL}; shift ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    -*) echo "unknown flag: $1" >&2; exit 2 ;;
    *) ROOT=$1 ;;
  esac
  shift
done
cd "$ROOT" || exit 2
[ -f bin/magento ] || { echo "no bin/magento in $PWD" >&2; exit 2; }

if [ -f .warden/warden-env.yml ] || grep -qs WARDEN_ENV_NAME .env; then
  RUN=(warden env exec -T php-fpm)
elif [ -d .ddev ]; then
  RUN=(ddev exec)
else
  RUN=(env)
fi
mage() { "${RUN[@]}" php bin/magento "$@"; }
LOCAL_HOST='^(localhost|127\.0\.0\.1|db|mysql|mariadb|[A-Za-z0-9.-]+\.(test|localhost|ddev\.site))$'

fails=0
step() {
  local name=$1; shift
  printf '%-44s ' "$name"
  local out
  if out=$("$@" 2>&1); then
    echo PASS
  else
    echo FAIL
    printf '%s\n' "$out" | tail -20 | sed 's/^/    | /'
    fails=$((fails + 1))
  fi
}

log_size() { wc -c < "var/log/$1" 2>/dev/null | tr -d ' ' || echo 0; }
reports() { find var/report -type f 2>/dev/null | wc -l | tr -d ' '; }
EXC_START=$(log_size exception.log) SYS_START=$(log_size system.log) REP_START=$(reports)

echo "runner: ${RUN[*]}"

host=$(sed -n "/'db'/,/]/p" app/etc/env.php | grep -m1 -oE "'host'[[:space:]]*=>[[:space:]]*'[^']*'" | sed -E "s/.*'([^']*)'$/\1/" | cut -d: -f1)
if ! [[ $host =~ $LOCAL_HOST ]]; then
  echo "Refusing: env.php database host '$host' is not local." >&2
  exit 2
fi
step "setup:upgrade"                mage setup:upgrade
step "setup:di:compile"             mage setup:di:compile
# shellcheck disable=SC2086  # SCD_LANGS is a space-separated locale list
step "setup:static-content:deploy"  mage setup:static-content:deploy -f ${SCD_LANGS:-}
step "cache:flush"       mage cache:flush
step "setup:db:status"   mage setup:db:status
step "app:config:status" mage app:config:status

if [ -z "$URL" ]; then
  URL=$(mage config:show web/secure/base_url 2>/dev/null | tail -1 | tr -d '\r')
fi
URL=${URL%/}
page_host=$(printf '%s' "$URL" | sed -E 's#^[a-z]+://([^/:]+).*#\1#')
if ! [[ $page_host =~ $LOCAL_HOST ]]; then
  echo "Refusing to request '$URL': not a local host. Pass --url for the local store." >&2
  exit 2
fi
admin=$(mage info:adminuri 2>/dev/null | grep -oE '/[A-Za-z0-9_-]+/?$' | tail -1)
page() {
  local path=$1 expect=$2 body code
  body=$(curl -ksS -L --max-time 60 -w '\n%{http_code}' "$URL$path") || return 1
  code=${body##*$'\n'}; body=${body%$'\n'*}
  [ "$code" = 200 ] || { echo "HTTP $code for $URL$path"; return 1; }
  if grep -qiE 'There has been an error processing your request|Exception printing is disabled|Fatal error|Report ID' <<<"$body"; then
    echo "Magento error page at $URL$path"; return 1
  fi
  grep -qi "$expect" <<<"$body" || { echo "expected '$expect' on $URL$path"; return 1; }
}
step "page: home"            page / '</html>'
step "page: customer login"  page /customer/account/login/ 'login\[username\]'
step "page: cart"            page /checkout/cart/ '</html>'
[ -n "$admin" ] && step "page: admin login ($admin)" page "${admin%/}/" 'login\[username\]'

new_errors() {
  local grew=0
  [ "$(log_size exception.log)" -gt "$EXC_START" ] && { echo "exception.log:"; tail -c +"$((EXC_START + 1))" var/log/exception.log | tail -15; grew=1; }
  [ "$(reports)" -gt "$REP_START" ] && { echo "new var/report files: $(( $(reports) - REP_START ))"; grew=1; }
  [ "$grew" = 0 ]
}
step "no new exceptions or reports" new_errors
sys_grew=$(( $(log_size system.log) - SYS_START ))
[ "$sys_grew" -gt 0 ] && echo "note: system.log grew by $sys_grew bytes (not a failure)"

echo
if [ "$fails" -eq 0 ]; then echo "smoke test: all checks passed"; else echo "smoke test: $fails failed"; fi
exit "$fails"
