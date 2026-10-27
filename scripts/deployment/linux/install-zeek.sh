#!/usr/bin/env bash
set -euo pipefail

IFACE="${IFACE:-ens19}"
SENSOR_IP="${SENSOR_IP:-10.30.0.12}"
NETWORKS="${NETWORKS:-192.168.1.0/24 192.168.2.0/24 10.30.0.0/24 10.40.0.0/24}"
RETENTION="${RETENTION:-14day}"
Z=/opt/zeek

if [[ $EUID -ne 0 ]]; then
  echo "Run with sudo" >&2
  exit 1
fi

echo "[1/6] Package (zeek-lts from the official repo)"
if [[ ! -x $Z/bin/zeek ]]; then
  echo 'deb [signed-by=/usr/share/keyrings/zeek.gpg] http://download.opensuse.org/repositories/security:/zeek/xUbuntu_24.04/ /' > /etc/apt/sources.list.d/zeek.list
  curl -fsSL https://download.opensuse.org/repositories/security:zeek/xUbuntu_24.04/Release.key | gpg --dearmor > /usr/share/keyrings/zeek.gpg
  apt-get update -q
  DEBIAN_FRONTEND=noninteractive apt-get install -y -q zeek-lts
fi
echo "export PATH=${Z}/bin:\$PATH" > /etc/profile.d/zeek.sh
$Z/bin/zeek --version

echo "[2/6] node.cfg and networks.cfg"
for f in node.cfg networks.cfg zeekctl.cfg; do
  [[ -f $Z/etc/$f.orig ]] || cp $Z/etc/$f $Z/etc/$f.orig
done
printf '[zeek]\ntype=standalone\nhost=localhost\ninterface=%s\n' "$IFACE" > $Z/etc/node.cfg
: > $Z/etc/networks.cfg
for n in $NETWORKS; do echo "$n" >> $Z/etc/networks.cfg; done

echo "[3/6] local.zeek: JSON, checksums, drop my own SSH session"
LOCAL=$Z/share/zeek/site/local.zeek
[[ -f $LOCAL.orig ]] || cp $LOCAL $LOCAL.orig
if ! grep -q 'no-sensor-ssh' "$LOCAL"; then
  cat >> "$LOCAL" <<CONF

@load policy/tuning/json-logs.zeek
redef ignore_checksums = T;
redef restrict_filters += {
    ["no-sensor-ssh"] = "not (host ${SENSOR_IP} and port 22) and not (vlan and host ${SENSOR_IP} and port 22)"
};
CONF
fi

echo "[4/6] Log retention ${RETENTION}"
if grep -q '^LogExpireInterval' $Z/etc/zeekctl.cfg; then
  sed -i "s/^LogExpireInterval.*/LogExpireInterval = ${RETENTION}/" $Z/etc/zeekctl.cfg
else
  echo "LogExpireInterval = ${RETENTION}" >> $Z/etc/zeekctl.cfg
fi
grep -c '^LogExpireInterval' $Z/etc/zeekctl.cfg | grep -qx 1 || { echo "LogExpireInterval appears more than once" >&2; exit 1; }

echo "[5/6] systemd unit and zeekctl cron"
cat > /etc/systemd/system/zeek.service <<CONF
[Unit]
Description=Zeek network security monitor
After=network-online.target span-offload.service
Wants=network-online.target

[Service]
Type=forking
ExecStart=${Z}/bin/zeekctl deploy
ExecStop=${Z}/bin/zeekctl stop

[Install]
WantedBy=multi-user.target
CONF
echo "*/5 * * * * root ${Z}/bin/zeekctl cron" > /etc/cron.d/zeek
chmod 644 /etc/cron.d/zeek
systemctl daemon-reload
$Z/bin/zeekctl check
systemctl enable --now zeek

echo "[6/6] Check (expect running, logs in current/, about 250 MB)"
sleep 20
$Z/bin/zeekctl status
ls $Z/logs/current/
ps -o rss=,cmd= -C zeek | awk '{printf "%.0f MB  %s\n", $1/1024, $2}'
