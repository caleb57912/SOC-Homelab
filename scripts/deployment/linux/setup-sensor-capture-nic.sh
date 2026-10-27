#!/usr/bin/env bash
set -euo pipefail

IFACE="${IFACE:-ens19}"

if [[ $EUID -ne 0 ]]; then
  echo "Run with sudo" >&2
  exit 1
fi

echo "[1/3] Netplan: ${IFACE} up with no address"
cat > /etc/netplan/60-span.yaml <<CONF
network:
  version: 2
  ethernets:
    ${IFACE}:
      dhcp4: false
      dhcp6: false
      link-local: []
      optional: true
CONF
chmod 600 /etc/netplan/60-span.yaml
netplan apply

echo "[2/3] Offloads off at every boot"
cat > /etc/systemd/system/span-offload.service <<CONF
[Unit]
Description=Disable NIC offloads on SPAN interface ${IFACE}
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/ethtool -K ${IFACE} gro off lro off tso off gso off
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
CONF
systemctl daemon-reload
systemctl enable --now span-offload

echo "[3/3] Check (expect UP with no IP, offloads off, frames arriving, 0 kernel drops)"
ip -br addr show "$IFACE"
ethtool -k "$IFACE" | grep -E "generic-receive|large-receive"
timeout 15 tcpdump -i "$IFACE" -nn -e -c 20 2>&1 | tail -n 8
