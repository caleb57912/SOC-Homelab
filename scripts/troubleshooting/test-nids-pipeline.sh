#!/usr/bin/env bash
set -euo pipefail

EVE=/var/log/suricata/eve.json
TARGET="${TARGET:-1.1.1.1}"

if [[ $EUID -ne 0 ]]; then
  echo "Run with sudo on sensor01" >&2
  exit 1
fi

START=$(date -u +%Y-%m-%dT%H:%M:%S)
printf "Request: HTTP %s\n" "$(curl -s -o /dev/null -m 10 -w '%{http_code}' "http://${TARGET}/soc-lab-nids-test")"
sleep 10
HITS=$(jq -c --arg t "$START" 'select(.event_type=="alert" and .alert.signature_id==9000001 and .timestamp > $t) | {ts: .timestamp, src: .src_ip, dst: .dest_ip, vlan: .vlan}' "$EVE")
if [[ -n "$HITS" ]]; then
  echo "$HITS"
  echo "Sensor OK. In Splunk: index=suricata alert.signature_id=9000001 earliest=-15m"
else
  echo "No sid 9000001 alert since ${START}. Check that the request crossed a mirrored port and run check-sensor.sh" >&2
  exit 1
fi
