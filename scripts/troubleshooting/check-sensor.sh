#!/usr/bin/env bash
set -uo pipefail

IFACE="${IFACE:-ens19}"
EVE=/var/log/suricata/eve.json

if [[ $EUID -ne 0 ]]; then
  echo "Run with sudo on sensor01" >&2
  exit 1
fi

echo "== Services =="
for s in span-offload zeek suricata SplunkForwarder; do
  printf "%-16s %s\n" "$s" "$(systemctl is-active "$s")"
done

echo
echo "== Capture interface ${IFACE} (expect UP, no IP, offloads off, RX climbing) =="
ip -br addr show "$IFACE"
ethtool -k "$IFACE" | grep -E "generic-receive|large-receive"
ip -s link show "$IFACE" | awk '/RX:/{getline; print "RX packets: "$2"  dropped: "$4}'

echo
echo "== Zeek =="
/opt/zeek/bin/zeekctl status | tail -n +2
ls -lt /opt/zeek/logs/current/*.log 2>/dev/null | head -n 5
printf "Capture loss: "
tail -n 1 /opt/zeek/logs/current/capture_loss.log 2>/dev/null | jq -r '"\(.percent_lost)% lost over \(.ts_delta)s"' 2>/dev/null || echo "no capture_loss.log yet (written every 15 min)"

echo
echo "== Suricata =="
grep -E "rules successfully loaded|using BPF" /var/log/suricata/suricata.log | tail -n 2
grep "<Error>" /var/log/suricata/suricata.log | tail -n 3
grep -E "capture.kernel_(packets|drops)" /var/log/suricata/stats.log | tail -n 2
SINCE=$(date -u -d '-1 hour' +%Y-%m-%dT%H:%M:%S)
echo "Top alerts in the last hour:"
jq -r --arg t "$SINCE" 'select(.event_type=="alert" and .timestamp > $t) | "\(.alert.signature_id) \(.alert.signature)"' "$EVE" | sort | uniq -c | sort -rn | head -n 10
printf "Last 2200121 (Ethertype unknown): "
jq -r 'select(.event_type=="alert" and .alert.signature_id==2200121) | .timestamp' "$EVE" | tail -n 1
echo "(a recent timestamp means a new frame type is getting past the BPF filter: run find-nonip-frames.sh)"

echo
echo "== Forwarder =="
id splunkfwd 2>/dev/null | grep -q zeek && echo "splunkfwd in zeek: yes" || echo "splunkfwd in zeek: NO"
id splunkfwd 2>/dev/null | grep -q suricata && echo "splunkfwd in suricata: yes" || echo "splunkfwd in suricata: NO"
sudo -u splunkfwd head -c 1 /opt/zeek/logs/current/conn.log > /dev/null 2>&1 && echo "reads conn.log: yes" || echo "reads conn.log: NO"
sudo -u splunkfwd head -c 1 "$EVE" > /dev/null 2>&1 && echo "reads eve.json: yes" || echo "reads eve.json: NO"
ls /opt/splunkforwarder/etc/apps | grep soc_ || echo "soc_sensor_inputs not deployed"
ss -tn | grep -E ":(9997|8089) " || echo "No connection to splunk01"

echo
echo "== Memory =="
free -h | head -n 2
ps -o rss=,cmd= -C zeek,Suricata-Main,suricata,splunkd | awk '{printf "%.0f MB  %s\n", $1/1024, $2}'
