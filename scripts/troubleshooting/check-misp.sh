#!/usr/bin/env bash
set -uo pipefail

MISP=/var/www/MISP
DB="${MISP_DB:-misp}"
PHP_INI=/etc/php/8.3/apache2/php.ini

if [[ $EUID -ne 0 ]]; then
  echo "Run with sudo on misp01" >&2
  exit 1
fi

echo "== Services =="
for s in apache2 mariadb redis-server supervisor; do
  printf "%-14s %s\n" "$s" "$(systemctl is-active "$s")"
done
curl -sk -o /dev/null -w "Web UI: HTTP %{http_code}\n" https://127.0.0.1/users/login

echo
echo "== Redis password consumers (values never printed) =="
RPW=$(awk '/^requirepass/{print $2}' /etc/redis/redis.conf)
if [[ -z "$RPW" ]]; then
  echo "Redis has no requirepass"
else
  printf "config.php references: %s (expect 2)\n" "$(grep -c "$RPW" $MISP/app/Config/config.php)"
  grep -q "auth=${RPW}" $PHP_INI && echo "php.ini session path: has auth" || echo "php.ini session path: MISSING auth (HTTP 500 NOAUTH)"
fi
unset RPW

echo
echo "== Permissions =="
ls -l $MISP/app/Config/{config,database,email}.php $PHP_INI

echo
echo "== Database =="
mysql -NBe "SELECT CONCAT(@@innodb_buffer_pool_size/1048576,' MB buffer pool')"
mysql -NBe "SELECT 'events', COUNT(*) FROM ${DB}.events UNION ALL SELECT 'published', SUM(published) FROM ${DB}.events UNION ALL SELECT 'attributes', COUNT(*) FROM ${DB}.attributes"

echo
echo "== Feeds cron and recent errors =="
cat /etc/cron.d/misp-feeds 2>/dev/null || echo "No /etc/cron.d/misp-feeds"
tail -n 50 $MISP/app/tmp/logs/error.log 2>/dev/null | grep -iE "error|exception" | tail -n 5

echo
echo "== Resources =="
free -h | head -n 2
df -h / | tail -n 1
