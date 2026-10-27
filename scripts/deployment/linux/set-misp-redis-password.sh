#!/usr/bin/env bash
set -euo pipefail

MISP=/var/www/MISP
CAKE=$MISP/app/Console/cake
REDIS_CONF=/etc/redis/redis.conf
PHP_INI=/etc/php/8.3/apache2/php.ini

if [[ $EUID -ne 0 ]]; then
  echo "Run with sudo" >&2
  exit 1
fi

RPW=$(openssl rand -hex 32)

echo "[1/4] Redis"
if grep -q '^requirepass ' $REDIS_CONF; then
  sed -i "s|^requirepass .*|requirepass ${RPW}|" $REDIS_CONF
else
  echo "requirepass ${RPW}" >> $REDIS_CONF
fi
systemctl restart redis-server

echo "[2/4] MISP settings (output suppressed, setSetting echoes the value)"
sudo -u www-data $CAKE Admin setSetting MISP.redis_password "$RPW" > /dev/null
sudo -u www-data $CAKE Admin setSetting SimpleBackgroundJobs.redis_password "$RPW" > /dev/null

echo "[3/4] PHP sessions are stored in Redis too"
sed -i "s|^session.save_path = .*|session.save_path = \"tcp://127.0.0.1:6379?auth=${RPW}\"|" $PHP_INI
chown root:www-data $PHP_INI
chmod 640 $PHP_INI
systemctl restart apache2 supervisor

echo "[4/4] Check without printing the password"
printf "config.php references: %s (expect 2)\n" "$(grep -c "$RPW" $MISP/app/Config/config.php)"
grep -q "auth=${RPW}" $PHP_INI && echo "php.ini session path: updated" || echo "php.ini session path: NOT updated"
redis-cli -a "$RPW" --no-auth-warning ping
unset RPW
curl -sk -o /dev/null -w "Web UI: HTTP %{http_code} (expect 200 or 302)\n" https://127.0.0.1/users/login
