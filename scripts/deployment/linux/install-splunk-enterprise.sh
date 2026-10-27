#!/usr/bin/env bash
set -euo pipefail

VERSION="${SPLUNK_VERSION:-10.6.0.5}"
BUILD="${SPLUNK_BUILD:-86587d4e3b27}"
INDEXES=(os network dns wazuh intel)
SPLUNK=/opt/splunk/bin/splunk

if [[ $EUID -ne 0 ]]; then
  echo "Run with sudo" >&2
  exit 1
fi

DEB="splunk-${VERSION}-${BUILD}-linux-amd64.deb"

echo "[1/5] Package"
if [[ -x $SPLUNK ]]; then
  echo "Splunk already installed, skipping download"
else
  wget -qO "/tmp/$DEB" "https://download.splunk.com/products/splunk/releases/${VERSION}/linux/${DEB}"
  dpkg -i "/tmp/$DEB"
  rm -f "/tmp/$DEB"
fi

echo "[2/5] Admin account"
if [[ -f /opt/splunk/etc/passwd ]]; then
  echo "Admin account already exists"
else
  read -rsp "New Splunk admin password: " PW
  echo
  umask 077
  printf '[user_info]\nUSERNAME = admin\nPASSWORD = %s\n' "$PW" > /opt/splunk/etc/system/local/user-seed.conf
  chown splunk:splunk /opt/splunk/etc/system/local/user-seed.conf
  unset PW
fi

echo "[3/5] Transparent Huge Pages off"
cat > /etc/systemd/system/disable-thp.service <<'UNIT'
[Unit]
Description=Disable Transparent Huge Pages
Before=Splunkd.service
[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo never > /sys/kernel/mm/transparent_hugepage/enabled; echo never > /sys/kernel/mm/transparent_hugepage/defrag'
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now disable-thp
cat /sys/kernel/mm/transparent_hugepage/enabled

echo "[4/5] Service"
if [[ ! -f /etc/systemd/system/Splunkd.service ]]; then
  $SPLUNK enable boot-start -user splunk -systemd-managed 1 --accept-license --answer-yes --no-prompt
fi
systemctl restart Splunkd
for _ in {1..60}; do
  ss -tln | grep -q ':8089 ' && break
  sleep 2
done

echo "[5/5] Indexes and receiving"
sudo -u splunk $SPLUNK login
for idx in "${INDEXES[@]}"; do
  sudo -u splunk $SPLUNK add index "$idx" 2>&1 | grep -v "already exists" || true
done
sudo -u splunk $SPLUNK enable listen 9997 2>&1 | grep -v "already exists" || true
sudo -u splunk $SPLUNK logout

echo
ss -tlnp | grep -E ':(8000|8089|9997) '
