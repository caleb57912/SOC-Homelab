#!/usr/bin/env bash
set -euo pipefail

IFACE="${IFACE:-ens19}"
SECONDS_TO_CAPTURE="${1:-120}"
LOCAL_YAML=/etc/suricata/local.yaml
NONIP='not (ip or ip6 or arp) and not (vlan and (ip or ip6 or arp))'

if [[ $EUID -ne 0 ]]; then
  echo "Run with sudo on sensor01" >&2
  exit 1
fi

if [[ "${1:-}" == "--test" ]]; then
  tcpdump -i "$IFACE" -d "$2" > /dev/null && echo "Filter compiles: OK"
  exit 0
fi

CURRENT=$(grep -oP 'bpf-filter:\s*"\K[^"]+' "$LOCAL_YAML" 2>/dev/null | sed 's/ and not (host.*$//' || true)
if [[ -n "$CURRENT" ]]; then
  FILTER="${CURRENT} and ${NONIP}"
  echo "Excluding what Suricata already filters: ${CURRENT}"
else
  FILTER="$NONIP"
fi

echo "Capturing non-IP frames on ${IFACE} for ${SECONDS_TO_CAPTURE}s..."
timeout "$SECONDS_TO_CAPTURE" tcpdump -i "$IFACE" -nn -e "$FILTER" 2>/dev/null \
  | grep -E '^[0-9]{2}:[0-9]{2}:' \
  | awk '{t=$5; for(i=6;i<=8;i++) t=t" "$i; print $2" > "$4"  "t}' \
  | sort | uniq -c | sort -rn | head -n 20 || true

cat <<NOTE

Common switch frames:
  01:80:c2:00:00:00  STP BPDU             -> not ether dst 01:80:c2:00:00:00
  01:00:0c:cc:cc:cd  Cisco PVST+          -> not ether dst 01:00:0c:cc:cc:cd
  01:00:0c:cc:cc:cc  CDP / DTP / VTP      -> not ether dst 01:00:0c:cc:cc:cc
  ethertype 0x9000   keepalive loopback   -> not ether proto 0x9000
Put MAC and ethertype clauses before any 'vlan' clause, test with: $0 --test '<filter>'
NOTE
