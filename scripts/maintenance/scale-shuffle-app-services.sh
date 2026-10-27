#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:-1}"

if ! sudo docker info > /dev/null 2>&1; then
  echo "Run on shuffle01 as a user with sudo" >&2
  exit 1
fi

echo "== Before =="
sudo docker service ls --format 'table {{.Name}}\t{{.Replicas}}'

mapfile -t SERVICES < <(sudo docker service ls --format '{{.Name}} {{.Replicas}}' | awk -v t="$TARGET" '$1 != "shuffle-workers" { split($2, r, "/"); if (r[2] != t) print $1 }')
if [[ ${#SERVICES[@]} -eq 0 ]]; then
  echo "Every app service already runs ${TARGET} copy"
  exit 0
fi

echo
echo "== Scaling ${#SERVICES[@]} service(s) to ${TARGET} =="
for s in "${SERVICES[@]}"; do
  sudo docker service scale -d "$s=$TARGET" > /dev/null && echo "$s"
done

sleep 15
echo
echo "== After =="
sudo docker service ls --format 'table {{.Name}}\t{{.Replicas}}'
free -h | head -2
echo
echo "Orborus 2.3.0 ignores SHUFFLE_APP_REPLICAS and creates app services with 3 copies."
echo "Run this again after Shuffle restarts or app updates. Don't remove services while runs are in flight."
