#!/usr/bin/env bash
set -uo pipefail

MISP_URL="${MISP_URL:-https://10.30.0.30}"

usage() {
  cat <<USAGE
Usage: $0 virustotal|abuseipdb|misp [ip]     (shuffle01, default ip 1.1.1.1)

Prompts for the API key and calls the service the same way the Shuffle workflow does,
with the key in a header (never in the URL, so it can't land in logs or run history).
Shows only the HTTP status and the fields the TheHive description uses.
USAGE
  exit 1
}

[[ $# -ge 1 ]] || usage
SVC=$1
IP=${2:-1.1.1.1}
read -rsp "API key for $SVC: " K; echo
[[ -n $K ]] || { echo "No key entered" >&2; exit 1; }
echo "Key length: ${#K}"
OUT=$(mktemp)

case $SVC in
  virustotal)
    code=$(curl -s -o "$OUT" -w "%{http_code}" -K <(printf 'header = "x-apikey: %s"\n' "$K") "https://www.virustotal.com/api/v3/ip_addresses/$IP")
    echo "HTTP $code (401: bad key, 429: rate limit)"
    python3 -c 'import json,sys; a=json.load(open(sys.argv[1]))["data"]["attributes"]; s=a["last_analysis_stats"]; print("malicious", s["malicious"], "harmless", s["harmless"], "owner", a.get("as_owner"))' "$OUT" 2>/dev/null
    ;;
  abuseipdb)
    code=$(curl -s -o "$OUT" -w "%{http_code}" -K <(printf 'header = "Key: %s"\nheader = "Accept: application/json"\n' "$K") "https://api.abuseipdb.com/api/v2/check?ipAddress=$IP&maxAgeInDays=90")
    echo "HTTP $code (401: bad or deleted key; Shuffle then writes a blank line)"
    python3 -c 'import json,sys; d=json.load(open(sys.argv[1]))["data"]; print("score", d["abuseConfidenceScore"], "reports", d["totalReports"], "whitelisted", d["isWhitelisted"], "isp", d.get("isp"))' "$OUT" 2>/dev/null
    ;;
  misp)
    code=$(curl -sk -o "$OUT" -w "%{http_code}" -K <(printf 'header = "Authorization: %s"\nheader = "Accept: application/json"\nheader = "Content-Type: application/json"\n' "$K") -d "{\"returnFormat\":\"json\",\"value\":\"$IP\",\"limit\":3}" "$MISP_URL/attributes/restSearch")
    echo "HTTP $code (403: key not allowed from this IP or user lacks API access)"
    python3 -c 'import json,sys; a=json.load(open(sys.argv[1]))["response"]["Attribute"]; print(len(a), "attribute(s)"); [print("event", x["event_id"], "to_ids", x["to_ids"], "comment", x.get("comment")) for x in a]' "$OUT" 2>/dev/null
    ;;
  *) unset K; rm -f "$OUT"; usage ;;
esac

unset K
rm -f "$OUT"
