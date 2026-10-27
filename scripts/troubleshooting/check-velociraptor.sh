#!/usr/bin/env bash
set -uo pipefail

CONF=/etc/velociraptor/server.config.yaml
WORK="${VELO_DIR:-/root/velo}"

if [[ $EUID -ne 0 ]]; then
  echo "Run as root on velo01" >&2
  exit 1
fi

echo "== Service =="
echo "velociraptor_server: $(systemctl is-active velociraptor_server), $(systemctl is-enabled velociraptor_server)"
pid=$(pgrep -f "frontend" -u velociraptor | head -1)
[[ -n $pid ]] && ps -o user=,pid=,etime= -p "$pid" | awk '{print "process user: " $1 " (expect velociraptor, not root), pid " $2 ", up " $3}' || echo "No frontend process owned by velociraptor"

echo
echo "== Listeners =="
echo "expect: *:8000 frontend, <SOC IP>:8889 GUI, 127.0.0.1:8001 API, 127.0.0.1:8003 monitoring"
ss -tlnp | awk 'NR>1 && $4 ~ /:(8000|8001|8003|8889)$/ {print $4}' | sort -u

echo
echo "== Config =="
grep -nA2 "^GUI:" $CONF | grep bind_
grep -A1 "^Frontend:" $CONF | grep hostname
echo "GUI users seeded on first start:"
awk '/initial_users:/{f=1; next} f && /^[^ ]/{f=0} f && /- name:/{print "  " $3}' $CONF | sort | uniq -c

echo
echo "== Copies of the CA private key on this host =="
grep -l "PRIVATE KEY" $CONF "$WORK"/*.yaml "$WORK"/*.orig 2>/dev/null
ls "$WORK"/velociraptor-server-*.deb 2>/dev/null | sed 's/$/  (compressed: also holds the key, grep cannot see it)/'
for c in "$WORK"/client.config.yaml; do
  [[ -f $c ]] && { [[ $(grep -c "PRIVATE KEY" "$c") -eq 0 ]] && echo "$c: no private key (correct)" || echo "$c: CONTAINS A PRIVATE KEY"; }
done

echo
echo "== Recent errors =="
journalctl -u velociraptor_server --since "-1h" --no-pager 2>/dev/null | grep -iE "error|fatal" | tail -5 | cut -c1-200

echo
echo "== Resources =="
free -h | head -2
df -h / | tail -1
