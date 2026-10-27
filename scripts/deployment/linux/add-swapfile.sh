#!/usr/bin/env bash
set -euo pipefail

SIZE="${1:-2G}"
SWAPPINESS="${SWAPPINESS:-10}"

if [[ $EUID -ne 0 ]]; then
  echo "Run with sudo" >&2
  exit 1
fi

if swapon --show=NAME --noheadings | grep -q '^/swapfile$'; then
  echo "/swapfile already active"
else
  fallocate -l "$SIZE" /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

echo "vm.swappiness=${SWAPPINESS}" > /etc/sysctl.d/99-swap.conf
sysctl --system > /dev/null
free -h
echo "swappiness: $(cat /proc/sys/vm/swappiness)"
