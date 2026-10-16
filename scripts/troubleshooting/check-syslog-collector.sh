#!/usr/bin/env bash
set -uo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run with sudo" >&2
  exit 1
fi

echo "== Services =="
printf "rsyslog: %s\nSplunkd: %s\n" "$(systemctl is-active rsyslog)" "$(systemctl is-active Splunkd)"

echo
echo "== Listening on 514 =="
ss -lntup | grep ':514 ' || echo "Nothing listening on 514"

echo
echo "== Senders (latest event per folder) =="
for dir in /var/log/remote/*/; do
  ip=$(basename "$dir")
  file="${dir}syslog.log"
  if [[ -f $file ]]; then
    printf "%-16s %s\n" "$ip" "$(tail -n1 "$file" | cut -c1-120)"
  else
    printf "%-16s %s\n" "$ip" "no syslog.log"
  fi
done
