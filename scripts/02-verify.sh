#!/usr/bin/env bash
# Overeni, ze sluzby bezi a web odpovida. Nenulovy kod pri selhani.
set -Eeuo pipefail

fail=0
for s in mariadb zabbix-server zabbix-agent2 apache2; do
  if systemctl is-active --quiet "$s"; then echo "OK   $s: active"
  else echo "FAIL $s: $(systemctl is-active "$s" || true)" >&2; fail=1; fi
done

code=000
for i in $(seq 1 30); do
  code="$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1/zabbix/ || true)"
  if [ "$code" = "200" ] || [ "$code" = "302" ]; then break; fi
  sleep 2
done
echo "HTTP /zabbix/ -> $code"
case "$code" in 200|302) ;; *) fail=1 ;; esac

exit "$fail"
