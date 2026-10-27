#!/usr/bin/env bash
set -uo pipefail

CRED=/etc/thehive/credentials.conf
LOG=/var/log/thehive/application.log
SHUFFLE_IP="${SHUFFLE_IP:-10.30.0.20}"

if [[ $EUID -ne 0 ]]; then
  echo "Run with sudo on thehive01" >&2
  exit 1
fi

echo "== Services =="
printf "%-14s %s\n" elasticsearch "$(systemctl is-active elasticsearch)" thehive "$(systemctl is-active thehive)"
pgrep -f CassandraDaemon > /dev/null && printf "%-14s %s\n" cassandra "running (CassandraDaemon)" || printf "%-14s %s\n" cassandra "NOT RUNNING (the unit state alone doesn't prove it)"
nodetool status 2>/dev/null | grep -E '^(UN|DN|UJ|UL)' || echo "nodetool: no answer yet (JMX on 7199 opens late after a start)"

echo
echo "== Listeners (only 9000 should be on all addresses) =="
ss -tlnp | awk 'NR>1 && $4 ~ /:(9000|9042|7199|9200|9300)$/ {print $4}' | sort -u

echo
echo "== Heaps =="
for p in CassandraDaemon org.elasticsearch.bootstrap play.core.server; do
  pid=$(pgrep -f "$p" | head -1)
  [[ -n $pid ]] && printf "%-28s %s\n" "$p" "$(ps -o args= -p "$pid" | grep -oE -- '-Xm[sx][^ ]+' | sort -u | tr '\n' ' ')"
done

echo
echo "== Credentials file (values never printed) =="
ls -l $CRED
awk -F'"' '{print $1, (/password/ ? "<" length($2) " chars>" : $2)}' $CRED
grep -q 'credentials.conf' /etc/thehive/application.conf && echo "application.conf includes credentials.conf" || echo "application.conf does NOT include credentials.conf"
grep -E '^application.baseUrl' /etc/thehive/application.conf

echo
echo "== Backends with TheHive's own credentials =="
code=$(curl -s -o /dev/null -w "%{http_code}" -K <(awk -F'"' '/basic.password/{printf "user = \"thehive:%s\"\n",$2}' $CRED) http://127.0.0.1:9200/)
echo "Elasticsearch as thehive: HTTP $code (expect 200; 401 means the file and the account disagree)"
curl -s -K <(awk -F'"' '/basic.password/{printf "user = \"thehive:%s\"\n",$2}' $CRED) http://127.0.0.1:9200/_cluster/health | grep -oE '"status":"[a-z]+"'
if command -v cqlsh > /dev/null; then
  tmp=$(mktemp); chmod 600 "$tmp"
  awk -F'"' '/storage.password/{printf "[PlainTextAuthProvider]\nusername = thehive\npassword = %s\n",$2}' $CRED > "$tmp"
  CQLSH_PYTHON=${CQLSH_PYTHON:-/usr/bin/python3.9} cqlsh --credentials="$tmp" -u thehive -e "SELECT keyspace_name FROM system_schema.keyspaces WHERE keyspace_name='thehive';" > /dev/null 2>&1 \
    && echo "Cassandra as thehive: OK" || echo "Cassandra as thehive: REJECTED or cqlsh failed"
  rm -f "$tmp"
fi

echo
echo "== TheHive API =="
curl -s --max-time 5 http://127.0.0.1:9000/api/status | head -c 120; echo

echo
echo "== Recent root causes in the log =="
grep "Caused by" $LOG 2>/dev/null | tail -4 | cut -c1-220 || true

echo
echo "== Last requests from Shuffle (${SHUFFLE_IP}) =="
grep "$SHUFFLE_IP" $LOG 2>/dev/null | grep -E "POST|GET" | tail -3 | cut -c1-200 || true

echo
echo "== Resources =="
free -h | head -2
df -h / | tail -1
ls /tmp/thehive_*.deb* 2>/dev/null && echo "Installer still in /tmp (cleanup item)"
