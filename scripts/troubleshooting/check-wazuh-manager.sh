#!/usr/bin/env bash
set -uo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run with sudo" >&2
  exit 1
fi

OSSEC=/var/ossec/etc/ossec.conf

echo "== Services =="
printf "wazuh-manager:   %s\nSplunkForwarder: %s\n" "$(systemctl is-active wazuh-manager)" "$(systemctl is-active SplunkForwarder)"

echo
echo "== Manager-only settings (expect indexer no, index-status no, jsonout yes, use_password yes) =="
grep -A1 "<indexer>" "$OSSEC" | grep enabled
grep -E "<index-status>|<jsonout_output>|<use_password>" "$OSSEC"

echo
echo "== Listening =="
ss -lntp | grep -E ':(1514|1515|55000) ' || echo "Nothing listening on 1514/1515/55000"

echo
echo "== Agents =="
/var/ossec/bin/agent_control -l

echo
echo "== alerts.json =="
ls -l /var/ossec/logs/alerts/alerts.json
printf "Last alert: "
tail -n1 /var/ossec/logs/alerts/alerts.json | cut -c1-160
id splunkfwd 2>/dev/null | grep -q wazuh && echo "splunkfwd is in the wazuh group" || echo "splunkfwd is NOT in the wazuh group, the forwarder cannot read alerts.json"

echo
echo "== Recent errors and warnings =="
tail -n 200 /var/ossec/logs/ossec.log | grep -iE "error|warn" | tail -n 10
