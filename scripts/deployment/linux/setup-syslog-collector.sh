#!/usr/bin/env bash
set -euo pipefail

UDR_IP="${UDR_IP:-10.30.0.1}"
CONF=/etc/rsyslog.d/10-soc-collector.conf
APP=/opt/splunk/etc/apps/soc_inputs/local

if [[ $EUID -ne 0 ]]; then
  echo "Run with sudo" >&2
  exit 1
fi

existing=$(grep -l 'ruleset(name="remote")' /etc/rsyslog.d/*.conf 2>/dev/null | grep -v "^$CONF$" || true)
if [[ -n $existing ]]; then
  echo "A remote ruleset already exists in: $existing" >&2
  echo "Remove or merge it first so the 514 inputs are not bound twice." >&2
  exit 1
fi

echo "[1/3] rsyslog collector"
install -d -o syslog -g adm -m 0750 /var/log/remote
cat > "$CONF" <<CONF
module(load="imudp")
module(load="imtcp")
template(name="RemoteFile" type="string" string="/var/log/remote/%fromhost-ip%/syslog.log")
template(name="RecvTimeFormat" type="string" string="%timegenerated:::date-rfc3339% %HOSTNAME% %syslogtag%%msg:::sp-if-no-1st-sp%%msg:::drop-last-lf%\n")
ruleset(name="remote") {
  if \$fromhost-ip == "${UDR_IP}" then {
    action(type="omfile" dynaFile="RemoteFile" template="RecvTimeFormat" dirCreateMode="0750" fileCreateMode="0640" dirGroup="adm" fileGroup="adm")
  } else {
    action(type="omfile" dynaFile="RemoteFile" template="RSYSLOG_FileFormat" dirCreateMode="0750" fileCreateMode="0640" dirGroup="adm" fileGroup="adm")
  }
  stop
}
input(type="imudp" port="514" ruleset="remote")
input(type="imtcp" port="514" ruleset="remote")
CONF
rsyslogd -N1
systemctl restart rsyslog

echo "[2/3] Splunk file monitor"
usermod -aG adm splunk
install -d -o splunk -g splunk "$APP"
if [[ -f $APP/inputs.conf ]]; then
  echo "$APP/inputs.conf exists, leaving it alone"
else
  cat > "$APP/inputs.conf" <<'INPUTS'
[monitor:///var/log/remote]
index = network
sourcetype = syslog
host_segment = 4
whitelist = \.log$
disabled = false
INPUTS
fi
if [[ -f $APP/props.conf ]]; then
  echo "$APP/props.conf exists, leaving it alone"
else
  cat > "$APP/props.conf" <<'PROPS'
[source::/var/log/remote/*/syslog.log]
TRANSFORMS =
PROPS
fi
chown -R splunk:splunk /opt/splunk/etc/apps/soc_inputs
systemctl restart Splunkd

echo "[3/3] Check"
ss -lntup | grep ':514 '
ls /var/log/remote/
