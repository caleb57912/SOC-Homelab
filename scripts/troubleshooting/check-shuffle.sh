#!/usr/bin/env bash
set -uo pipefail

DIR="${SHUFFLE_DIR:-$HOME/Shuffle}"
EXEC_ID=""

usage() {
  echo "Usage: $0 [--execution <execution id>]     (as caleb on shuffle01)" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --execution) EXEC_ID=$2; shift 2 ;;
    *) usage ;;
  esac
done

if ! sudo docker info > /dev/null 2>&1; then
  echo "Docker isn't reachable with sudo" >&2
  exit 1
fi

if [[ -n $EXEC_ID ]]; then
  echo "== Worker log lines for execution $EXEC_ID (last 30 min) =="
  sudo docker service logs --since 30m --raw shuffle-workers 2>&1 | grep "$EXEC_ID" | grep -iE "error|towards|Received|FINISHED|abort" | tail -40 | cut -c1-240
  echo
  echo "'dial tcp: lookup <app>' means the worker cached an app address that no longer exists: restart the worker when no runs are in flight."
  exit 0
fi

echo "== Containers =="
cd "$DIR" && sudo docker compose ps --format 'table {{.Name}}\t{{.Image}}\t{{.Status}}'

echo
echo "== Listeners (only 3001 and 3443 should be on all addresses) =="
sudo ss -tlnp | awk 'NR>1 && $4 ~ /:(3001|3443|5001|9200|3002|3444)$/ {print $4}' | sort -u

echo
echo "== OpenSearch login from .env (password never printed) =="
sudo bash -c 'set -a; . ./.env; curl -sk -o /dev/null -w "OpenSearch: HTTP %{http_code}\n" -K <(printf "user = \"admin:%s\"\n" "$SHUFFLE_OPENSEARCH_PASSWORD") https://127.0.0.1:9200/'
sudo stat -c '%a %n' .env .env.orig 2>/dev/null

echo
echo "== App services (anything above 1/1 eats memory: scripts/maintenance/scale-shuffle-app-services.sh) =="
sudo docker service ls --format '{{.Name}} {{.Replicas}}' | awk '{split($2,r,"/"); flag=(r[2]>1 && $1!="shuffle-workers")?"  <-- scale down":""; print $1, $2 flag}'

echo
echo "== Memory =="
sudo docker stats --no-stream --format '{{.MemUsage}} {{.Name}}' | sort -h | tail -8
free -h | head -2

echo
echo "== Recent worker errors =="
sudo docker service logs --since 15m --raw shuffle-workers 2>&1 | grep -iE "error" | tail -5 | cut -c1-200
echo
echo "Trace one run: $0 --execution <id from the Shuffle run page>"
