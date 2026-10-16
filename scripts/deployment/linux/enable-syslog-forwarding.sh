#!/usr/bin/env bash
set -euo pipefail

COLLECTOR="${1:-10.30.0.10}"

if [[ $EUID -ne 0 ]]; then
  echo "Run as root" >&2
  exit 1
fi

command -v rsyslogd >/dev/null || apt-get install -y rsyslog

cat > /etc/rsyslog.d/90-soc.conf <<CONF
*.* action(type="omfwd" target="${COLLECTOR}" port="514" protocol="tcp" template="RSYSLOG_SyslogProtocol23Format" action.resumeRetryCount="-1" queue.type="LinkedList" queue.filename="soc_fwd" queue.maxDiskSpace="500m" queue.saveOnShutdown="on")
CONF

rsyslogd -N1
systemctl restart rsyslog
sleep 2
logger "SOC syslog forwarding test from $(hostname)"
ss -tnp | grep "${COLLECTOR}:514" || echo "No TCP session to ${COLLECTOR}:514 yet"
