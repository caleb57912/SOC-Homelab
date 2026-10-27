#!/usr/bin/env bash
set -uo pipefail

MISP_URL="${MISP_URL:-https://10.30.0.30}"

read -rsp "MISP auth key: " KEY
echo
printf "Read  (expect 200): HTTP %s\n" "$(curl -sk -o /dev/null -w '%{http_code}' -H "Authorization: ${KEY}" -H 'Accept: application/json' "${MISP_URL}/servers/getVersion")"
curl -sk -H "Authorization: ${KEY}" -H 'Accept: application/json' "${MISP_URL}/servers/getVersion" | head -c 200
echo
printf "Write (expect 403): HTTP %s\n" "$(curl -sk -o /dev/null -w '%{http_code}' -X POST -H "Authorization: ${KEY}" -H 'Accept: application/json' -H 'Content-Type: application/json' -d '{"Event":{"info":"api write test"}}' "${MISP_URL}/events/add")"
unset KEY
echo "Run from splunk01 (allowed). From any other host the key should be refused."
