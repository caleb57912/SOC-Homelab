#!/usr/bin/env bash
set -euo pipefail

MISP_DOMAIN="${MISP_DOMAIN:-10.30.0.30}"
BUFFER_POOL="${BUFFER_POOL:-768M}"
MISP=/var/www/MISP

if [[ $EUID -ne 0 ]]; then
  echo "Run with sudo inside tmux" >&2
  exit 1
fi

case "${1:-}" in
  install)
    swapon --show --noheadings | grep -q . || { echo "No swap. Run add-swapfile.sh first." >&2; exit 1; }
    cd /tmp
    wget -q --no-cache -O INSTALL.sh https://raw.githubusercontent.com/MISP/MISP/2.5/INSTALL/INSTALL.ubuntu2404.sh
    echo "Installer defaults (read these before continuing):"
    grep -nE '^[A-Z_]+=|MISP_DOMAIN|buffer_pool' INSTALL.sh | head -40
    read -rp "Run the installer with MISP_DOMAIN=${MISP_DOMAIN}? [y/N] " ok
    [[ $ok == y ]] || exit 0
    LOG=/root/misp-install.log
    install -m 600 /dev/null "$LOG"
    env MISP_DOMAIN="$MISP_DOMAIN" bash INSTALL.sh 2>&1 | tee "$LOG"
    echo "Save the generated credentials to the password manager, then: shred -u ${LOG}"
    ;;
  tune)
    printf '[mysqld]\ninnodb_buffer_pool_size = %s\n' "$BUFFER_POOL" > /etc/mysql/mariadb.conf.d/z-misp.cnf
    systemctl restart mariadb
    mysql -NBe "SELECT CONCAT(@@innodb_buffer_pool_size/1048576,' MB buffer pool')"
    chmod o-rwx $MISP/app/Config/config.php $MISP/app/Config/database.php $MISP/app/Config/email.php
    ls -l $MISP/app/Config/{config,database,email}.php
    echo "17 */6 * * * www-data ${MISP}/app/Console/cake Server fetchFeed 1 all > /dev/null 2>&1" > /etc/cron.d/misp-feeds
    chmod 644 /etc/cron.d/misp-feeds
    cat /etc/cron.d/misp-feeds
    ;;
  *)
    echo "Usage: sudo $0 install|tune" >&2
    exit 1
    ;;
esac
