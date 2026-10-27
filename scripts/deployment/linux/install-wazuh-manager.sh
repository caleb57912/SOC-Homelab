#!/usr/bin/env bash
set -euo pipefail

VERSION="${WAZUH_VERSION:-4.14.9-1}"
OSSEC=/var/ossec/etc/ossec.conf

if [[ $EUID -ne 0 ]]; then
  echo "Run with sudo" >&2
  exit 1
fi

echo "[1/4] Repository"
apt-get update
apt-get install -y gnupg apt-transport-https curl
curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/wazuh.gpg --import
chmod 644 /usr/share/keyrings/wazuh.gpg
echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" > /etc/apt/sources.list.d/wazuh.list
apt-get update

echo "[2/4] Manager ${VERSION}"
apt-get install -y "wazuh-manager=${VERSION}"
apt-mark hold wazuh-manager

echo "[3/4] Manager-only config"
cp -n "$OSSEC" "$OSSEC.orig"
sed -i '/<indexer>/,/<\/indexer>/ s#<enabled>yes</enabled>#<enabled>no</enabled>#' "$OSSEC"
sed -i '/<vulnerability-detection>/,/<\/vulnerability-detection>/ s#<index-status>yes</index-status>#<index-status>no</index-status>#' "$OSSEC"
sed -i 's#<use_password>no</use_password>#<use_password>yes</use_password>#' "$OSSEC"
if [[ ! -s /var/ossec/etc/authd.pass ]]; then
  openssl rand -hex 16 > /var/ossec/etc/authd.pass
fi
chown root:wazuh /var/ossec/etc/authd.pass
chmod 640 /var/ossec/etc/authd.pass

echo "[4/4] Start"
systemctl enable wazuh-manager
systemctl restart wazuh-manager
sleep 15
systemctl is-active wazuh-manager
ss -lntp | grep -E ':(1514|1515|55000) '
echo
echo "Enrollment password: sudo cat /var/ossec/etc/authd.pass"
echo "Forward alerts.json with: install-universal-forwarder.sh --group wazuh"
