#!/usr/bin/env bash
set -uo pipefail

usage() {
  cat <<USAGE
Usage: $0 <webhook URL> [dest ip]

Posts a payload shaped like Splunk's webhook alert action to a Shuffle webhook, with a
unique sid so TheHive's sourceRef duplicate check doesn't drop it. Run from any host that
can reach shuffle01 (3001 http, 3443 https with a self-signed certificate).

  $0 https://10.30.0.20:3443/api/v1/hooks/webhook_<id>
USAGE
  exit 1
}

[[ $# -ge 1 ]] || usage
URL=$1
DEST=${2:-1.1.1.1}
SID="manual-test-$(date -u +%Y%m%dT%H%M%SZ)"
BODY=$(printf '{"sid":"%s","search_name":"Manual webhook test","app":"search","owner":"admin","result":{"src_ip":"192.168.1.11","dest_ip":"%s","dest_port":"80","signature":"SOC-LAB local test rule","ids_severity":"3"}}' "$SID" "$DEST")

echo "sid: $SID"
curl -sk -w "\nHTTP %{http_code}\n" -X POST -H 'Content-Type: application/json' -d "$BODY" "$URL"
cat <<NEXT

{"success": true, "execution_id": ...} only means Shuffle accepted the payload.
Check the run in Shuffle (Debug tab), then the TheHive alert titled "Manual webhook test" with sourceRef $SID.
"uninitialized" or {"success": false}: the workflow needs a connected action, a save, then Stop/Start on the webhook.
NEXT
