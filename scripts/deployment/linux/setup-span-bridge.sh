#!/usr/bin/env bash
set -euo pipefail

NIC="${NIC:-eno2}"
BRIDGE="${BRIDGE:-vmbr1}"
VMID="${VMID:-302}"
IFACES=/etc/network/interfaces

if [[ $EUID -ne 0 ]]; then
  echo "Run as root on the Proxmox host" >&2
  exit 1
fi

echo "[1/4] Bridge config"
if grep -q "^iface ${BRIDGE} " "$IFACES"; then
  echo "${BRIDGE} already defined in ${IFACES}"
else
  cp "$IFACES" "${IFACES}.bak-pre-span"
  printf '\nauto %s\niface %s inet manual\n\tpost-up /usr/sbin/ethtool -K %s gro off lro off tso off gso off\n\nauto %s\niface %s inet manual\n\tbridge-ports %s\n\tbridge-stp off\n\tbridge-fd 0\n\tbridge-ageing 0\n#SPAN capture, no IP\n' \
    "$NIC" "$NIC" "$NIC" "$BRIDGE" "$BRIDGE" "$NIC" >> "$IFACES"
  echo "Appended ${NIC} and ${BRIDGE}; backup at ${IFACES}.bak-pre-span"
fi

echo "[2/4] Apply"
ifreload -a

echo "[3/4] Check (expect UP, ageing 0, offloads off, link detected)"
ip -br link show "$NIC"
ip -br link show "$BRIDGE"
echo "ageing_time: $(cat /sys/class/net/${BRIDGE}/bridge/ageing_time)"
ethtool -k "$NIC" | grep -E "generic-receive|large-receive|tcp-segmentation-offload|generic-segmentation"
ethtool "$NIC" | grep -E "Speed|Link detected"

echo "[4/4] Sensor NIC on VM ${VMID}"
if qm config "$VMID" | grep -q "bridge=${BRIDGE}"; then
  qm config "$VMID" | grep "bridge=${BRIDGE}"
else
  qm set "$VMID" --net1 "virtio,bridge=${BRIDGE},firewall=0"
fi
