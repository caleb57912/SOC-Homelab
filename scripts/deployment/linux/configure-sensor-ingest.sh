#!/usr/bin/env bash
set -euo pipefail

SPLUNK=/opt/splunk
TA=$SPLUNK/etc/apps/TA-soc-homelab/default
APP=$SPLUNK/etc/deployment-apps/soc_sensor_inputs/local
SC=$SPLUNK/etc/system/local/serverclass.conf
SENSOR_HOST="${SENSOR_HOST:-sensor01}"
ZEEK_LOGS="conn dns http ssl x509 files notice weird dhcp ssh software capture_loss known_hosts known_services"
AS_SPLUNK=(sudo -u splunk)

if [[ $EUID -ne 0 ]]; then
  echo "Run with sudo on splunk01" >&2
  exit 1
fi

echo "[1/6] Log the CLI in (prompts for the Splunk admin, nothing is stored)"
"${AS_SPLUNK[@]}" $SPLUNK/bin/splunk login

echo "[2/6] Indexes"
for i in zeek suricata; do
  "${AS_SPLUNK[@]}" $SPLUNK/bin/splunk add index "$i" 2>&1 | grep -v "already exists" || true
done

echo "[3/6] Parsing in TA-soc-homelab"
if grep -q '^\[suricata:eve\]' $TA/props.conf 2>/dev/null; then
  echo "props.conf already has the sensor sourcetypes"
else
  {
    for l in $ZEEK_LOGS; do
      printf '\n[zeek:%s]\nSHOULD_LINEMERGE = false\nLINE_BREAKER = ([\\r\\n]+)\nTIME_PREFIX = ^\\{"ts":\nTIME_FORMAT = %%s.%%6N\nMAX_TIMESTAMP_LOOKAHEAD = 20\nTRUNCATE = 20000\nKV_MODE = json\n' "$l"
    done
    printf '\n[suricata:eve]\nSHOULD_LINEMERGE = false\nLINE_BREAKER = ([\\r\\n]+)\nTIME_PREFIX = "timestamp":"\nTIME_FORMAT = %%Y-%%m-%%dT%%H:%%M:%%S.%%6N%%z\nMAX_TIMESTAMP_LOOKAHEAD = 40\nTRUNCATE = 50000\nKV_MODE = json\nTRANSFORMS-eve_filter = suricata_eve_drop_all, suricata_eve_keep_alerts\n'
  } | "${AS_SPLUNK[@]}" tee -a $TA/props.conf > /dev/null
fi
if grep -q '^\[suricata_eve_drop_all\]' $TA/transforms.conf 2>/dev/null; then
  echo "transforms.conf already has the eve filter"
else
  printf '\n[suricata_eve_drop_all]\nREGEX = .\nDEST_KEY = queue\nFORMAT = nullQueue\n\n[suricata_eve_keep_alerts]\nREGEX = "event_type":"alert"\nDEST_KEY = queue\nFORMAT = indexQueue\n' \
    | "${AS_SPLUNK[@]}" tee -a $TA/transforms.conf > /dev/null
fi

echo "[4/6] Deployment app soc_sensor_inputs"
"${AS_SPLUNK[@]}" mkdir -p $APP
{
  for l in $ZEEK_LOGS; do
    printf '[monitor:///opt/zeek/logs/current/%s.log]\nindex = zeek\nsourcetype = zeek:%s\ndisabled = 0\n\n' "$l" "$l"
  done
  printf '[monitor:///var/log/suricata/eve.json]\nindex = suricata\nsourcetype = suricata:eve\ndisabled = 0\n'
} | "${AS_SPLUNK[@]}" tee $APP/inputs.conf > /dev/null

echo "[5/6] Server class"
if grep -q '^\[serverClass:sensor\]' $SC; then
  echo "serverClass:sensor already present"
else
  printf '\n[serverClass:sensor]\nwhitelist.0 = %s\n\n[serverClass:sensor:app:soc_sensor_inputs]\nrestartSplunkd = true\nstateOnClient = enabled\n' "$SENSOR_HOST" \
    | "${AS_SPLUNK[@]}" tee -a $SC > /dev/null
fi

echo "[6/6] Restart (parse-time settings) and reload the deployment server"
"${AS_SPLUNK[@]}" $SPLUNK/bin/splunk btool props list suricata:eve | grep TRANSFORMS
systemctl restart Splunkd
sleep 30
systemctl is-active Splunkd
"${AS_SPLUNK[@]}" $SPLUNK/bin/splunk reload deploy-server
echo "On ${SENSOR_HOST}: sudo scripts/deployment/linux/install-universal-forwarder.sh --group zeek --group suricata"
