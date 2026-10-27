#!/usr/bin/env bash
set -euo pipefail

VERSION="${SPLUNK_VERSION:-10.6.0.5}"
BUILD="${SPLUNK_BUILD:-86587d4e3b27}"
SPLUNK_SERVER="${SPLUNK_SERVER:-10.30.0.10}"
UF=/opt/splunkforwarder
GROUPS_TO_JOIN=()
MONITORS=()

usage() {
  cat <<USAGE
Usage: sudo $0 [--group NAME]... [--monitor PATH:INDEX:SOURCETYPE]...

  --group     Add splunkfwd to a group so it can read that app's logs (pihole, wazuh)
  --monitor   Add a local file monitor instead of waiting for the deployment server

Examples:
  sudo $0 --group wazuh
  sudo $0 --group pihole --monitor /var/log/pihole/pihole.log:dns:pihole:dnsmasq
USAGE
  exit 1
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --group) GROUPS_TO_JOIN+=("$2"); shift 2 ;;
    --monitor) MONITORS+=("$2"); shift 2 ;;
    *) usage ;;
  esac
done

if [[ $EUID -ne 0 ]]; then
  echo "Run with sudo" >&2
  exit 1
fi

DEB="splunkforwarder-${VERSION}-${BUILD}-linux-amd64.deb"

echo "[1/4] Package"
if [[ -x $UF/bin/splunk ]]; then
  echo "Forwarder already installed"
else
  wget -qO "/tmp/$DEB" "https://download.splunk.com/products/universalforwarder/releases/${VERSION}/linux/${DEB}"
  dpkg -i "/tmp/$DEB"
  rm -f "/tmp/$DEB"
fi

echo "[2/4] Deployment client and outputs"
cat > $UF/etc/system/local/deploymentclient.conf <<CONF
[deployment-client]
clientName = $(hostname -s)

[target-broker:deploymentServer]
targetUri = ${SPLUNK_SERVER}:8089
CONF
cat > $UF/etc/system/local/outputs.conf <<CONF
[tcpout]
defaultGroup = soc

[tcpout:soc]
server = ${SPLUNK_SERVER}:9997
CONF

if [[ ${#MONITORS[@]} -gt 0 ]]; then
  : > $UF/etc/system/local/inputs.conf
  for m in "${MONITORS[@]}"; do
    path=${m%%:*}
    rest=${m#*:}
    index=${rest%%:*}
    sourcetype=${rest#*:}
    printf '[monitor://%s]\nindex = %s\nsourcetype = %s\ndisabled = 0\n\n' "$path" "$index" "$sourcetype" >> $UF/etc/system/local/inputs.conf
  done
fi

echo "[3/4] Service and permissions"
if [[ ! -f /etc/systemd/system/SplunkForwarder.service ]]; then
  $UF/bin/splunk enable boot-start -systemd-managed 1 -user splunkfwd --accept-license --answer-yes --no-prompt
fi
chown -R splunkfwd:splunkfwd $UF/etc/system/local
for g in "${GROUPS_TO_JOIN[@]}"; do
  usermod -aG "$g" splunkfwd
done
systemctl restart SplunkForwarder

echo "[4/4] Check"
sleep 10
systemctl is-active SplunkForwarder
ss -tnp | grep -E ":(8089|9997) " || echo "No connection to ${SPLUNK_SERVER} yet. Check the firewall and the serverclass whitelist."
