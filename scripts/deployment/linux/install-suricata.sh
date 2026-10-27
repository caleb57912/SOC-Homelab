#!/usr/bin/env bash
set -euo pipefail

IFACE="${IFACE:-ens19}"
SENSOR_IP="${SENSOR_IP:-10.30.0.12}"
HOME_NET="${HOME_NET:-[192.168.1.0/24,192.168.2.0/24,10.30.0.0/24,10.40.0.0/24]}"
S=/etc/suricata

if [[ $EUID -ne 0 ]]; then
  echo "Run with sudo" >&2
  exit 1
fi

echo "[1/7] Package (OISF stable PPA)"
if ! command -v suricata > /dev/null; then
  add-apt-repository -y ppa:oisf/suricata-stable
  apt-get update -q
  DEBIAN_FRONTEND=noninteractive apt-get install -y -q suricata jq
fi
suricata -V

echo "[2/7] HOME_NET in suricata.yaml (not in the include: an include replaces the whole vars section)"
[[ -f $S/suricata.yaml.orig ]] || cp $S/suricata.yaml $S/suricata.yaml.orig
sed -i "s|^\(\s*\)HOME_NET:.*|\1HOME_NET: \"${HOME_NET}\"|" $S/suricata.yaml
grep -q '^include: /etc/suricata/local.yaml' $S/suricata.yaml || echo 'include: /etc/suricata/local.yaml' >> $S/suricata.yaml
grep -n '^\s*HOME_NET:' $S/suricata.yaml

echo "[3/7] local.yaml overrides"
cat > $S/local.yaml <<CONF
%YAML 1.1
---
af-packet:
  - interface: ${IFACE}
    threads: 1
    cluster-id: 99
    cluster-type: cluster_flow
    defrag: yes
    checksum-checks: no
    bpf-filter: "not ether dst 01:80:c2:00:00:00 and not ether dst 01:00:0c:cc:cc:cd and not ether dst 01:00:0c:cc:cc:cc and not ether proto 0x9000 and not (host ${SENSOR_IP} and port 22) and not (vlan and host ${SENSOR_IP} and port 22)"
rule-files:
  - suricata.rules
  - /etc/suricata/rules/local.rules
detect:
  profile: low
mpm-algo: hs
spm-algo: hs
flow:
  memcap: 64mb
stream:
  memcap: 64mb
  checksum-validation: no
  reassembly:
    memcap: 128mb
defrag:
  memcap: 32mb
host:
  memcap: 16mb
CONF
[[ -f /etc/default/suricata ]] && sed -i "s/^IFACE=.*/IFACE=${IFACE}/" /etc/default/suricata

echo "[4/7] Local test rule (sid 9000001)"
mkdir -p $S/rules
echo 'alert http any any -> any any (msg:"SOC-LAB NIDS pipeline test"; flow:to_server,established; http.uri; content:"/soc-lab-nids-test"; classtype:misc-activity; sid:9000001; rev:1;)' > $S/rules/local.rules

echo "[5/7] ET Open rules and config test"
suricata-update -q
suricata -T -c $S/suricata.yaml -v 2>&1 | tail -n 3
suricata --dump-config -c $S/suricata.yaml 2>/dev/null | grep -E "^vars.address-groups.(HOME_NET|EXTERNAL_NET)|^af-packet.0.(interface|bpf-filter)|^detect.profile"

echo "[6/7] Service and daily rule update"
systemctl enable suricata
systemctl restart suricata
echo '37 4 * * * root /usr/bin/suricata-update -q >> /var/log/suricata/suricata-update.log 2>&1 && /usr/bin/systemctl reload suricata' > /etc/cron.d/suricata-update
chmod 644 /etc/cron.d/suricata-update

echo "[7/7] Check (expect rules loaded with 0 failed, BPF line, Engine started)"
sleep 45
systemctl is-active suricata
grep -E "rules successfully loaded|using BPF|Engine started|<Error>" /var/log/suricata/suricata.log | tail -n 4
echo "Test the pipeline with scripts/troubleshooting/test-nids-pipeline.sh"
