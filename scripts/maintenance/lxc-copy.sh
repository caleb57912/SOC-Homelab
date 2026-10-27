#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage: $0 push|pull <ctid> <source> <destination> [perms]     (root on pve)

  push  host file -> container   e.g. $0 push 307 /root/velociraptor-v0.77.1-linux-amd64 /root/velo/velociraptor-v0.77.1-linux-amd64 0755
  pull  container file -> host   e.g. $0 pull 307 /root/velo/velo-client-0.77.1-soc.msi /root/velo-client-0.77.1-soc.msi

Copies with pct push/pull, then compares SHA256 on both sides.
USAGE
  exit 1
}

[[ $# -ge 4 ]] || usage
if [[ $EUID -ne 0 ]] || ! command -v pct > /dev/null; then
  echo "Run as root on the Proxmox host" >&2
  exit 1
fi

MODE=$1 CT=$2 SRC=$3 DST=$4 PERMS=${5:-}
pct status "$CT" | grep -q running || { echo "Container $CT is not running" >&2; exit 1; }

case $MODE in
  push)
    pct exec "$CT" -- mkdir -p "$(dirname "$DST")"
    if [[ -n $PERMS ]]; then pct push "$CT" "$SRC" "$DST" --perms "$PERMS"; else pct push "$CT" "$SRC" "$DST"; fi
    HOST_SUM=$(sha256sum "$SRC" | cut -d' ' -f1)
    CT_SUM=$(pct exec "$CT" -- sha256sum "$DST" | cut -d' ' -f1)
    ;;
  pull)
    pct pull "$CT" "$SRC" "$DST"
    [[ -n $PERMS ]] && chmod "$PERMS" "$DST"
    CT_SUM=$(pct exec "$CT" -- sha256sum "$SRC" | cut -d' ' -f1)
    HOST_SUM=$(sha256sum "$DST" | cut -d' ' -f1)
    ;;
  *) usage ;;
esac

echo "host:      $HOST_SUM"
echo "container: $CT_SUM"
if [[ $HOST_SUM == "$CT_SUM" ]]; then
  echo "MATCH"
else
  echo "MISMATCH: do not use the copy" >&2
  exit 1
fi
[[ $MODE == pull ]] && echo "Remove the host copy once it's moved on: rm $DST"
exit 0
