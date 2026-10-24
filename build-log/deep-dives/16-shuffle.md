# 3.2 · Shuffle (Deep Dive)

Shuffle is the SOAR (security orchestration, automation and response) layer: it receives detections, enriches them and hands them to TheHive. This entry covers sizing shuffle01, Docker, installing Shuffle 2.3.0, locking down its ports and secrets, the chain from a Suricata detection through Splunk and Shuffle to a TheHive alert, and enriching that alert with MISP, VirusTotal and AbuseIPDB.

## Sizing

Shuffle's install guide asks for at least 4 GB. Its current `docker-compose.yml` sets OpenSearch, the database that holds users, workflows and execution results, to a fixed heap:

```
OPENSEARCH_JAVA_OPTS=-Xms3072m -Xmx3072m
```

On a 4 GB VM that leaves under 1 GB for the OS, the backend, the frontend, Orborus (the component that runs workflows) and every app container a workflow starts.

| Option | Result |
| --- | --- |
| 4 GB, 1 GB heap | Inside the budget, but the least headroom of anything in the SOC |
| **6 GB, 2 GB heap** | **Chosen.** SOC total 27.5 GB, budget raised to about 28 GB |
| RAM rebalance first | Delays 3.2 |

On `pve`:

```bash
free -h
qm shutdown 303 && qm status 303
qm snapshot 303 pre-shuffle --description "Base Ubuntu before Shuffle install, 4 GB"
qm set 303 --memory 6144
qm config 303 | grep -E '^(memory|balloon):'; qm listsnapshot 303
qm start 303
```

Inside shuffle01: 5.8 GiB total, 5.3 GiB available, no swap. Like thehive01, this VM has no swap: OpenSearch locks its heap in RAM (`bootstrap.memory_lock=true`).

## Docker

```bash
sudo apt update && sudo apt -y full-upgrade
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc && sudo chmod a+r /etc/apt/keyrings/docker.asc
gpg --show-keys /etc/apt/keyrings/docker.asc | head -2
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update 2>&1 | grep -iE "docker|err"
apt-get -s install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin | grep -E "^Inst|newly installed"
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo docker version --format '{{.Server.Version}}'; sudo docker compose version; systemctl is-active docker; systemctl is-enabled docker
```

The key's fingerprint was `9DC8 5822 9FC7 DD38 854A E2D8 8D81 803C 0EBF CD88`, Docker's release key. The dry run listed Docker's five packages plus `pigz` and `docker-ce-rootless-extras`. Result: Docker 29.9.1, Compose v5.6.0, containerd 2.4.2, active and enabled at boot.

I didn't add `caleb` to the `docker` group. Any member of that group can start a container that mounts the host's root filesystem, which is root access without a password. Every command uses `sudo docker` instead.

## Shuffle

### Pinning the release

```bash
cd ~ && git clone https://github.com/Shuffle/Shuffle && cd Shuffle
git log --oneline -1; git tag --sort=-v:refname | head -3
```

`main` was at a nightly merge (`c439ab39`). The tag list showed `v2.3.0-rc2`, `v2.3.0-rc1`, `v2.3.0`; version sorting puts the `-rc` suffixes above the release, but `v2.3.0` is the release itself. The compose file also pulls every Shuffle image as `:latest`. I checked out the release and checked which images have a matching tag before pinning:

```bash
git checkout v2.3.0
grep -oE 'ghcr.io/shuffle/shuffle-[a-z-]+' docker-compose.yml | sort -u | while read i; do sudo docker manifest inspect $i:2.3.0 > /dev/null 2>&1 && echo "$i:2.3.0 ok" || echo "$i:2.3.0 MISSING"; done
sed -i 's#\(ghcr.io/shuffle/shuffle-[a-z-]*\):latest#\1:2.3.0#g' docker-compose.yml
sed -i 's#ghcr.io/shuffle/shuffle-security:2.3.0#ghcr.io/shuffle/shuffle-security:latest#' docker-compose.yml
```

Backend, frontend, Orborus and worker exist at `2.3.0`; `shuffle-security` doesn't. My first `sed` pinned all five, so I put that one back on `:latest`, which would otherwise have broken the pull. After the pull I recorded its digest, which identifies the exact build:

```
ghcr.io/shuffle/shuffle-security@sha256:6186b7728785aad3eec4ff2f41637705aa5af8cc7e83ecc647126b606c7b8589
```

| Image | Version |
| --- | --- |
| shuffle-backend, shuffle-frontend, shuffle-orborus, shuffle-worker | 2.3.0 |
| shuffle-security | `latest`, digest above |
| opensearchproject/opensearch | 3.2.0 |

### Heap and ports

```bash
sed -i 's/-Xms3072m -Xmx3072m/-Xms2g -Xmx2g/' docker-compose.yml
sed -i 's#- 9200:9200#- "127.0.0.1:9200:9200"#' docker-compose.yml
sed -i 's#- "${BACKEND_PORT}:5001"#- "127.0.0.1:${BACKEND_PORT}:5001"#' docker-compose.yml
sed -i -e 's#- "${SHUFFLE_SECURITY_PORT:-3002}:80"#- "127.0.0.1:${SHUFFLE_SECURITY_PORT:-3002}:80"#' -e 's#- "${SHUFFLE_SECURITY_PORT_HTTPS:-3444}:443"#- "127.0.0.1:${SHUFFLE_SECURITY_PORT_HTTPS:-3444}:443"#' docker-compose.yml
```

As shipped, the compose file published OpenSearch (9200) and the backend API (5001) on every address. Docker opens published ports with its own iptables rules, ahead of anything `ufw` or a host firewall would add, so the only reliable control is the bind address in the compose file. The frontend (3001 HTTP, 3443 HTTPS) stays on all addresses: it serves the UI, proxies API calls to the backend internally, and will receive Splunk's webhooks.

### Secrets and timezone

The shipped `.env` sets the OpenSearch admin password to a default value that is published in the repository. I replaced it before first start, together with the encryption key:

```bash
cp -p .env .env.orig
P="$(openssl rand -base64 36 | tr -dc 'A-Za-z0-9' | cut -c1-28)_Aa1"; sed -i -e "s|^SHUFFLE_OPENSEARCH_PASSWORD=.*|SHUFFLE_OPENSEARCH_PASSWORD=\"$P\"|" -e "s|^OPENSEARCH_INITIAL_ADMIN_PASSWORD=.*|OPENSEARCH_INITIAL_ADMIN_PASSWORD=\"$P\"|" .env; unset P
sed -i -e "s|^SHUFFLE_ENCRYPTION_MODIFIER=.*|SHUFFLE_ENCRYPTION_MODIFIER=$(openssl rand -hex 32)|" -e 's|^TZ=.*|TZ=UTC|' .env
chmod 600 .env .env.orig
awk -F= '/^(SHUFFLE_OPENSEARCH_PASSWORD|OPENSEARCH_INITIAL_ADMIN_PASSWORD|SHUFFLE_ENCRYPTION_MODIFIER)=/{print $1, "<" length($2) " chars>"} /^TZ=/' .env
```

| Setting | Why |
| --- | --- |
| One generated password in both OpenSearch lines | OpenSearch takes its admin password from `OPENSEARCH_INITIAL_ADMIN_PASSWORD` on first start, and the backend logs in with `SHUFFLE_OPENSEARCH_PASSWORD`, so they must match. Nobody types it, so it only lives in `.env`. |
| `_Aa1` suffix | OpenSearch 3 requires upper, lower, digit and special characters. `_` avoids `!`, which bash treats as history expansion inside double quotes. |
| `SHUFFLE_ENCRYPTION_MODIFIER` | Encrypts the API keys Shuffle stores for TheHive, MISP and the rest. It has to exist before the first start; changing it later makes saved credentials unreadable. |
| `TZ=UTC` | Matches every other SOC system |
| `chmod 600` | Both files now hold secrets (`.env.orig` only the public default, but it's still a credentials file) |

### Issue: lowering a kernel setting

Shuffle's guide sets `vm.max_map_count=262144` for OpenSearch with `sysctl -w`, which doesn't survive a reboot. I made it permanent with a file, and the reload printed two values:

```bash
echo 'vm.max_map_count=262144' | sudo tee /etc/sysctl.d/99-opensearch.conf > /dev/null && sudo sysctl --system | grep max_map_count
```
```
vm.max_map_count = 1048576
vm.max_map_count = 262144
```

Ubuntu 24.04 already sets 1048576 in `/usr/lib/sysctl.d/`. My `99-` file loaded last and lowered it to OpenSearch's minimum. I removed it:

```bash
sudo rm /etc/sysctl.d/99-opensearch.conf && sudo sysctl --system | grep max_map_count; sysctl vm.max_map_count
```

The value is back at 1048576, four times what OpenSearch needs. The guide's `swapoff -a` wasn't needed either, since the VM has no swap. `shuffle-database` was already owned by UID 1000 (`caleb` on this image), which is also OpenSearch's UID inside its container.

### First start

```bash
sudo docker compose config --quiet && echo "compose OK"
sudo docker compose pull
sudo docker compose up -d
sudo docker compose ps --format 'table {{.Name}}\t{{.Status}}'
sudo ss -tlnp | grep -E ':(3001|3443|5001|9200|3002|3444)\b'
```

`docker compose config` parses the compose file and `.env` exactly as `up` will, so a broken edit shows up before anything starts. All five containers came up, plus a `shuffle-workers.1.<id>` container: Orborus puts Docker into swarm mode (Docker's built-in clustering) and runs workers as a swarm service.

| Port | Bound to | Service |
| --- | --- | --- |
| 3001, 3443 | 0.0.0.0 | Frontend (UI, webhooks) |
| 5001 | 127.0.0.1 | Backend API |
| 9200 | 127.0.0.1 | OpenSearch |
| 3002, 3444 | 127.0.0.1 | shuffle-security |

The generated password checked out against OpenSearch, without printing it, by loading `.env` inside a root shell:

```bash
sudo bash -c 'set -a; . ./.env; curl -sk -o /dev/null -w "%{http_code} %{errormsg}\n" -K <(printf "user = \"admin:%s\"\n" "$SHUFFLE_OPENSEARCH_PASSWORD") https://127.0.0.1:9200/'
```

The first try, 20 seconds after the start, returned `000` (no connection yet); OpenSearch hadn't opened the port. A minute later it returned `200`.

Memory with everything running: OpenSearch 2.55 GiB, the other containers under 100 MB each, 2.5 GiB available.

Shuffle has no default login: the first visitor to the UI creates the admin account. I created mine right after the start, so nobody else on the network could claim it first. The open-source edition needs no license.

## Connecting to TheHive

### Service account

In TheHive, under SOC-Homelab, I created `shuffle@soc.lan` as a **Service** account with the **analyst** profile. A service account has no password, logs in only with an API key, and doesn't count toward TheHive's user limit. Every alert Shuffle creates is attributed to it, so the audit trail shows what was automated. The analyst profile can create alerts and cases but can't change users or settings.

I tested the key from shuffle01 without putting it on the command line:

```bash
read -rs THKEY; echo
curl -s -K <(printf 'header = "Authorization: Bearer %s"\n' "$THKEY") http://10.30.0.21:9000/api/v1/user/current | head -c 250; echo
unset THKEY
```

It returned `"login":"shuffle@soc.lan"`, `"name":"Shuffle"`, `"hasKey":true`, `"hasPassword":false`, which also proved shuffle01 can reach port 9000.

### Which app

Searching Shuffle's public catalogue for TheHive returned a single app, **TheHive** (Case, Alert, Task, Observable). I first took it for Shuffle's old TheHive 4 app. Two things settled it. Its actions carry HTTP method badges ("POST Create alert"), which marks an OpenAPI-based app. And the first run's result showed the URL it called: `http://10.30.0.21:9000/api/v1/alert`, TheHive 5's API. The app's authentication holds TheHive's URL and the API key, encrypted with the modifier from `.env`.

### Issue: the workflow started at the wrong node

A new workflow comes with a placeholder start node ("Change Me"). Shuffle runs a workflow from its start node, and nothing connected the placeholder to the TheHive node, so a run would never have reached TheHive. I deleted the placeholder, and the TheHive node became the start node (Shuffle draws the start node as a circle).

### Issue: `Unrecognized token '$'`

The first run returned:

```
"status": 400
"body": {"type": "BadRequest", "message": "Invalid json", "cause": "Unrecognized token '$': was expecting (JSON String, Number, Array, Object or token 'null', 'true' or..."}
"url": "http://10.30.0.21:9000/api/v1/alert"
"success": true
```

TheHive's log confirmed the request arrived as the service account:

```bash
sudo grep "10.30.0.20" /var/log/thehive/application.log | grep -E "POST|GET" | tail -3 | cut -c1-220
```
```
... (shuffle@soc.lan@SOC-Homelab) [...] 10.30.0.20 POST /api/v1/alert
```

The cause was in the app's body template, which the form fields fill in:

```
"flag": ${flag},
"pap": ${pap},
"tlp": ${tlp},
"tags": "${tags}",
"status": "${status}",
```

An empty field leaves its placeholder as literal text. Quoted placeholders just become odd strings, but `${flag}`, `${pap}` and `${tlp}` are unquoted because they're meant to be a boolean and numbers, and I hadn't filled in `flag`. The body TheHive received contained a bare `${flag}`, which isn't valid JSON. Even with every field filled, `"tags": "${tags}"` would send a string where TheHive expects a list. I replaced the template with the exact body:

```json
{"type":"test","source":"shuffle","sourceRef":"shuffle-test-001","title":"3.2 test alert from Shuffle","description":"Shuffle to TheHive connectivity test","severity":1,"tlp":1,"pap":1}
```

The next run returned `"status": 201` with the new alert in the body.

`"success": true` appeared on both runs. Shuffle sets it when the HTTP call completes, whatever the response; the `status` field and TheHive's log are what show whether the call worked.

```mermaid
flowchart LR
    F[Empty form field<br/>flag] --> T["Template: flag: ${flag}"]
    T --> B["Body sent: flag: ${flag}<br/>not valid JSON"]
    B --> E[TheHive 400<br/>Unrecognized token '$']
```

## Splunk → Shuffle → TheHive

The second workflow, `3.2 Splunk alert to TheHive`, starts from a **Webhook** trigger named `splunk_alert` instead of a manual run. Shuffle generates its URL:

```
http://10.30.0.20:3001/api/v1/hooks/webhook_<id>
```

The frontend serves the same path over HTTPS on 3443. Both are the only Shuffle ports reachable from the network.

### Issue: the webhook stayed "uninitialized"

Clicking **Start** on a webhook that was the only node in an unsaved workflow did nothing; the panel kept saying `Webhook: uninitialized`, and a test POST returned `{"success": false}`. Shuffle starts a webhook against the saved workflow, and this one had unsaved changes and no action after the trigger. After I added the TheHive node, connected the trigger to it and saved, **Start** switched the webhook to `running`.

### Issue: a new node defaults to the first action

The new TheHive node came up with **GET Get case timeline**, the first action in the app's list, which asks for a case ID and creates nothing. I switched it to **POST Create alert**.

### Testing with a payload shaped like Splunk's

Before involving Splunk I posted the same shape Splunk's webhook action sends, from shuffle01:

```bash
H="http://10.30.0.20:3001/api/v1/hooks/webhook_<id>"
curl -s -X POST -d '{"sid":"manual-test-001","search_name":"Manual webhook test","result":{"src_ip":"192.168.1.11","dest_ip":"1.1.1.1","signature":"SOC-LAB local test rule"}}' "$H"
```

Each test used a new `sid`, because TheHive refuses a second alert with the same `sourceRef`. Shuffle answered `{"success": true, "execution_id": "..."}` every time and parsed the payload into `$exec.sid`, `$exec.search_name` and `$exec.result.*`. Getting TheHive to accept the result took three fixes.

**1. No content type.** The first run returned:

```
"status": 400
"message": "Mismatch for one of({body as application/json (UTF-8)}|{body as multipart/form-data}), expected 'app..."
```

TheHive only accepts an alert body declared as `application/json` (or a multipart upload). The node's **Headers** field had held `Content-Type=application/json` while it was on Get case timeline, and switching the action cleared it. I set it back:

```
Content-Type=application/json
Accept=application/json
```

**2. The webhook ended up on the wrong workflow.** Partway through, I lost the webhook node and added a new one, but to `3.2 test - TheHive alert`, the first test workflow, which has a fixed body with `sourceRef: shuffle-test-001`. Every POST to the new webhook returned `success: true` and created nothing, because TheHive already had that reference. The title bar was the only clue. I removed that webhook and went back to the original one on the right workflow. Since then I check the workflow title before every edit.

**3. A dot after a variable.** With the headers fixed, TheHive returned:

```
"message": "Invalid json"
"cause": "Unexpected character ('s' (code 115)): was expecting comma to separate Object entries"
```

My description field read `"Splunk alert $exec.search_name. Signature: $exec.result.signature. ..."`. Shuffle treats a dot after a variable as part of the path, so `$exec.search_name.` asked for an empty key inside `search_name`. That lookup failed, and the whole `$exec` object went into the string instead, quotes and all. The JSON string ended early, and the next character was the `s` of `sid`. I rewrote the description so that no variable is followed by a dot:

```json
{"type":"splunk","source":"splunk01","sourceRef":"$exec.sid","title":"$exec.search_name","description":"Splunk alert: $exec.search_name | signature: $exec.result.signature | src: $exec.result.src_ip | dst: $exec.result.dest_ip","severity":2,"tlp":2,"pap":2,"tags":["splunk","suricata"],"observables":[{"dataType":"ip","data":"$exec.result.src_ip"},{"dataType":"ip","data":"$exec.result.dest_ip"}]}
```

| Placeholder | Source |
| --- | --- |
| `$exec` | The JSON the webhook received |
| `$exec.sid` | Splunk's search job ID, unique per run, used as TheHive's required unique `sourceRef` |
| `$exec.search_name` | The Splunk alert's name |
| `$exec.result.<field>` | Fields from the first result row (Splunk's webhook action sends only that row) |

`tlp` and `pap` are 2 (AMBER) because these alerts carry internal addresses. The next test (`manual-test-005`) returned 201, and TheHive showed the alert with type `splunk`, source `splunk01`, tags `splunk` and `suricata`, severity medium and two `ip` observables. TheHive displays observables defanged (`192[.]168[.]1[.]1`) so they can't be clicked by accident; the stored values are unchanged.

```mermaid
flowchart LR
    V["description: $exec.search_name. Signature"] --> P["Shuffle reads path search_name + empty key"]
    P --> R["Inserts the whole $exec object, quotes included"]
    R --> E["TheHive 400: unexpected 's' (from sid)"]
```

### The Splunk alert

The detection is my Suricata test rule (sid 9000001, `curl http://1.1.1.1/soc-lab-nids-test` from my PC). Shuffle's `$exec.result.<field>` can't reach a field with a dot in its name, so the search flattens Suricata's dotted fields first:

```
index=suricata event_type=alert alert.signature_id=9000001
| rename alert.signature AS signature, alert.severity AS ids_severity
| table _time src_ip dest_ip dest_port signature ids_severity
```

Saved as alert `SOC - Suricata local test rule 9000001`: scheduled on cron `*/5 * * * *` over the last 15 minutes, trigger when results > 0, trigger once, with a **Webhook** action.

### Issue: "Webhook URL is invalid"

Splunk's alert form rejected `http://10.30.0.20:3001/...`. Splunk Enterprise does have a webhook allow list, but it's a setting in `alert_actions.conf`, not in Splunk Web, and it was off:

```bash
sudo -u splunk /opt/splunk/bin/splunk btool alert_actions list webhook --debug | grep -iE "allowlist|enable"
```
```
/opt/splunk/etc/apps/alert_webhook/default/alert_actions.conf enable_allowlist = false
```

So the form itself was rejecting the URL scheme. Shuffle's HTTPS port took it:

```
https://10.30.0.20:3443/api/v1/hooks/webhook_<id>
```

### The full chain

Splunk's own log of the alert action shows each run:

```
index=_internal sourcetype=splunkd component=sendmodalert action=webhook
| table _time log_level event_message
```
```
Invoking modular alert action=webhook for search="SOC - Suricata local test rule 9000001" sid="scheduler__admin__search__RMD580..._65"
Sending POST request to url=https://10.30.0.20:3443/api/v1/hooks/webhook_<id> with size=462 bytes payload
Webhook receiver responded with HTTP status=200
Alert action script completed in duration=261 ms with exit code=0
```

In Shuffle the run came in with source `webhook` and Splunk's payload as `$exec`: `sid`, `search_name`, `app`, `owner`, `results_link` and `result` with the six table fields. The TheHive node returned 201. TheHive showed `SOC - Suricata local test rule 9000001`, created by Shuffle, with the Splunk job ID as its reference and my PC and `1.1.1.1` as observables.

```mermaid
flowchart LR
    PC[curl from my PC] --> SEN[sensor01<br/>Suricata sid 9000001]
    SEN -->|UF| SPL[splunk01<br/>alert every 5 min]
    SPL -->|webhook HTTPS :3443| SH[shuffle01<br/>workflow]
    SH -->|POST /api/v1/alert| TH[thehive01<br/>alert + 2 observables]
```

Three findings from that first real run:

- **Splunk doesn't verify Shuffle's certificate.** Shuffle's certificate is self-signed and Splunk posted to it without complaint, so this HTTPS encrypts the traffic but doesn't prove the receiver is shuffle01.
- **Duplicates.** The 21:40 and 21:45 runs both found the same Suricata event, because the 15-minute window overlaps three 5-minute runs, and each run created its own TheHive alert. Throttling was unticked when I saved the alert (it's visible in the evidence). Throttling the alert for 15 minutes stops the repeats.
- **`results_link` uses `splunk01`.** That name doesn't resolve on my network, so the link in the alert doesn't open.

Throttling the alert for 15 minutes (Search & Reporting → Alerts → Edit Alert → Throttle) stopped the repeats; one Suricata event now produces one TheHive alert.

## Enrichment

The Phase 3 gate is a test alert reaching TheHive *with enrichment*. Shuffle looks up the destination IP in three sources before it creates the alert, and writes the results into the alert's description, so the analyst sees the context when the alert opens instead of pivoting through three other tools.

```mermaid
flowchart LR
    W[Webhook<br/>splunk_alert] --> M[MISP<br/>attribute search]
    M --> V[VirusTotal<br/>IP report]
    V --> A[AbuseIPDB<br/>check IP]
    A --> T[TheHive<br/>alert + enrichment]
```

Only the destination is enriched. In this detection the source is always one of my own machines, and sending a `192.168.x.x` address to VirusTotal or AbuseIPDB would leak a detail of my network and return nothing.

### Keys

Each service got its own key, tested from shuffle01 before Shuffle used it, read with `read -rs` and passed to curl through a config file so it never appeared on screen:

```bash
read -rs K; echo; echo "${#K}"
curl -s -o ~/vt.json -w "%{http_code}\n" -K <(printf 'header = "x-apikey: %s"\n' "$K") https://www.virustotal.com/api/v3/ip_addresses/1.1.1.1
curl -s -w "\n%{http_code}\n" -K <(printf 'header = "Key: %s"\nheader = "Accept: application/json"\n' "$K") "https://api.abuseipdb.com/api/v2/check?ipAddress=1.1.1.1&maxAgeInDays=90"
curl -sk -w "\n%{http_code}\n" -K <(printf 'header = "Authorization: %s"\nheader = "Accept: application/json"\nheader = "Content-Type: application/json"\n' "$K") -d '{"returnFormat":"json","value":"1.1.1.1","limit":3}' https://10.30.0.30/attributes/restSearch
unset K
```

Printing the key length first caught a bad paste: the first VirusTotal key read as 171 characters instead of 64, and the lookup returned nothing until I re-copied it with the site's copy button.

| Service | Key | Result for 1.1.1.1 |
| --- | --- | --- |
| VirusTotal | Free tier (4/min, 500/day) | 0 malicious, 57 harmless, Cloudflare |
| AbuseIPDB | Free plan, API v2 | Confidence 0 despite 162 reports, `isWhitelisted: true` |
| MISP | New user `shuffle@soc.lan`, role **API Read Only** (same as Splunk's), key read-only and locked to `10.30.0.20/32` | Hit in event 918, `to_ids: false`, comment "False Positive?" |

The results disagree on the surface, and that's the point of having three. 1.1.1.1 has plenty of abuse reports and sits in a threat feed, yet every source that knows it marks it benign: AbuseIPDB whitelists it and the MISP feed itself says it isn't fit for detection. A raw "MISP hit" would have looked alarming on its own.

### Issue: MISP's auth key form couldn't see the new user

The user existed (I checked in the database), but the **Add authentication key** dropdown only listed the admin. `cake user authkey` turned out to look up an existing key's owner, not create one. The add-key page accepts the user ID in the URL, which skips the dropdown:

```bash
sudo mysql misp -e "SELECT u.id,u.email,u.disabled,r.name,r.perm_auth FROM users u JOIN roles r ON r.id=u.role_id;"
sudo -u www-data /var/www/MISP/app/Console/cake user change_role shuffle@soc.lan 7
```
```
https://10.30.0.30/auth_keys/add/3
```

### Building the nodes

Each new node defaulted to its app's first action again (MISP came up as **POST Add a feed**), so I set every action by hand:

| Node | Action | Input |
| --- | --- | --- |
| MISP 1 | POST `/attributes/restSearch` | Body `{"returnFormat":"json","value":"$exec.result.dest_ip","limit":5}`, SSL verify off (self-signed) |
| Virustotal v3 1 | Get an IP address report | `$exec.result.dest_ip` |
| AbuseIPDB v2 1 | Get check ip | `$exec.result.dest_ip`, query `maxAgeInDays=90` (the API defaults to 30) |
| TheHive 1 | POST Create alert | Body below |

Connecting AbuseIPDB to TheHive failed with "Cant make branch to starting node": TheHive was still the start node from before the webhook existed. Setting MISP as the start node fixed it; the webhook trigger always feeds whichever node is the start.

The TheHive body adds an enrichment block built from the other nodes' results:

```json
{"type":"splunk","source":"splunk01","sourceRef":"$exec.sid","title":"$exec.search_name","description":"**Detection**\n\n- Splunk alert: $exec.search_name\n- Signature: $exec.result.signature\n- Source: $exec.result.src_ip\n- Destination: $exec.result.dest_ip\n\n**Enrichment for $exec.result.dest_ip**\n\n- VirusTotal: $virustotal_v3_1.body.data.attributes.last_analysis_stats.malicious malicious, $virustotal_v3_1.body.data.attributes.last_analysis_stats.harmless harmless (owner: $virustotal_v3_1.body.data.attributes.as_owner)\n- AbuseIPDB: score $abuseipdb_v2_1.body.data.abuseConfidenceScore, $abuseipdb_v2_1.body.data.totalReports reports, whitelisted: $abuseipdb_v2_1.body.data.isWhitelisted (ISP: $abuseipdb_v2_1.body.data.isp)\n- MISP: event $misp_1.body.response.Attribute.#0.event_id, to_ids: $misp_1.body.response.Attribute.#0.to_ids, comment: $misp_1.body.response.Attribute.#0.comment","severity":2,"tlp":2,"pap":2,"tags":["splunk","suricata","enriched"],"observables":[{"dataType":"ip","data":"$exec.result.src_ip"},{"dataType":"ip","data":"$exec.result.dest_ip"}]}
```

No variable is followed by a dot, and `.#0` picks the first entry of MISP's attribute list.

### Issue: runs stuck at "No results yet"

The first enrichment runs never got past the start. Two causes, one after the other.

**Every app ran three copies.** With the new apps running, the VM was down to 292 MiB available:

```bash
sudo docker stats --no-stream --format 'table {{.Name}}\t{{.MemUsage}}' | sort -k2 -h | tail -15
sudo docker service ls --format 'table {{.Name}}\t{{.Replicas}}'
```

Orborus runs each app as a Docker swarm service, and every one was at `3/3`, about 75–100 MB per copy, including apps this workflow never calls. `SHUFFLE_APP_REPLICAS=3` in `.env` looked like the cause, but after setting it to 1, Orborus's environment showed `SHUFFLE_APP_REPLICAS=1` and it still created three copies; 2.3.0 ignores the setting for swarm services. Scaling the services directly worked and has held:

```bash
sudo docker service ls --format '{{.Name}}' | grep -v '^shuffle-workers$' | xargs -I{} sudo docker service scale -d {}=1
```

Available memory went back to about 1.4 GiB.

**I removed services under a running Shuffle.** My first fix deleted the app services so Orborus would recreate them. The worker still had their addresses cached, so the next run's MISP step went nowhere:

```
[ERROR] ... URL: http://misp_1-1-0:33341/api/v1/run. Error: Post "http://misp_1-1-0:33341/api/v1/run": dial tcp: lookup misp
```

Restarting the worker (`docker service update --force shuffle-workers`) cleared the cache, but it also orphaned a run that was in flight: AbuseIPDB answered that run and posted its result to the old worker container, which timed out. Runs started after the restart finished normally, `FINISHED - 4/4` in about 10 seconds. The worker log was what showed each of these; the Shuffle UI only ever said "No results yet".

```bash
sudo docker service logs --since 10m --raw shuffle-workers 2>&1 | grep "$ID" | grep -iE "error|towards|Received|FINISHED"
```

Shuffle also starts a `tenzir-node` container (a data pipeline engine, image `tenzir/tenzir:main`) that uses about 660 MB and isn't part of this workflow. I stopped it and turned off its restart policy, and Orborus started it again within seconds, so it stays for now.

### Issue: the AbuseIPDB app sends its key in the URL

The AbuseIPDB node's result showed the request it made:

```
"url": "https://api.abuseipdb.com/api/v2/check?key=<KEY>..."
```

This app passes the API key as a query parameter, so every run stores it in plain text in Shuffle's execution history in OpenSearch. I had also pasted part of that output into my notes, so I treated the key as exposed: I deleted it in AbuseIPDB and created a new one. The VirusTotal and MISP nodes send their keys in headers, and their recorded URLs carry no key.

### Issue: a failed lookup still produced an alert

After the rotation, the next alert from Splunk showed `AbuseIPDB: score , reports, whitelisted: (ISP: )`. The node had returned **401** with the old, deleted key in its URL: editing the existing auth entry hadn't changed the key the node used. I created a fresh authentication entry with the new key, selected it in the node, and removed the old entries. The next run returned 200.

The failure itself is the finding: AbuseIPDB's error left every path empty, Shuffle filled the description with blanks, and TheHive accepted the alert. An analyst can't tell "no reputation data" from "the lookup failed". Handling empty results is on the backlog.

### The gate

A Splunk-shaped test (`manual-test-011`) and a real detection (`scheduler__admin__search__RMD580..._422`, signature `SOC-LAB NIDS pipeline test`) both produced enriched alerts. The final description:

```
Detection
- Splunk alert: Manual webhook test
- Signature: SOC-LAB local test rule
- Source: 192.168.1.11
- Destination: 1.1.1.1

Enrichment for 1.1.1.1
- VirusTotal: 0 malicious, 57 harmless (owner: Cloudflare, Inc.)
- AbuseIPDB: score 0, 162 reports, whitelisted: True (ISP: APNIC and Cloudflare DNS Resolver project)
- MISP: event 918, to_ids: False, comment: False Positive?
```

That meets the Phase 3 gate: a test alert reaches TheHive with enrichment.

| Memory on shuffle01 | Available |
| --- | --- |
| After first start | 2.5 GiB |
| Enrichment apps at 3 copies each, plus tenzir-node | 292 MiB |
| App services scaled to 1 | 1.4–1.8 GiB |

## Evidence

**Images pinned at 2.3.0 (security at latest with its digest), all containers up, only 3001 and 3443 on all addresses, the OpenSearch login at 200, and the TheHive API key tested as shuffle@soc.lan.**

![Images pinned at 2.3.0 (security at latest with its digest), all containers up, only 3001 and 3443 on all addresses, the OpenSearch login at 200, and the TheHive API key tested as shuffle@soc.lan.](../../screenshots/build-log/16-shuffle/01-images-start-ports-key-test.png)

**The only TheHive app in Shuffle's public catalogue.**

![The only TheHive app in Shuffle's public catalogue.](../../screenshots/build-log/16-shuffle/02-thehive-app-catalogue.png)

**The TheHive node with the POST Create alert action and its authentication, next to the unconnected placeholder start node.**

![The TheHive node with the POST Create alert action and its authentication, next to the unconnected placeholder start node.](../../screenshots/build-log/16-shuffle/03-thehive-node-auth.png)

**The 400 Invalid json result calling /api/v1/alert, and TheHive's log showing the request as shuffle@soc.lan.**

![The 400 Invalid json result calling /api/v1/alert, and TheHive's log showing the request as shuffle@soc.lan.](../../screenshots/build-log/16-shuffle/04-bad-request-and-thehive-log.png)

**The app's body template with unquoted placeholders for flag, pap and tlp.**

![The app's body template with unquoted placeholders for flag, pap and tlp.](../../screenshots/build-log/16-shuffle/05-body-template.png)

**The fixed workflow: 201 Created from /api/v1/alert.**

![The fixed workflow: 201 Created from /api/v1/alert.](../../screenshots/build-log/16-shuffle/06-alert-created-201.png)

**A webhook started on an unsaved workflow with no action after it stays uninitialized.**

![A webhook started on an unsaved workflow with no action after it stays uninitialized.](../../screenshots/build-log/16-shuffle/07-webhook-uninitialized.png)

**A new TheHive node defaults to GET Get case timeline, the first action in the list.**

![A new TheHive node defaults to GET Get case timeline, the first action in the list.](../../screenshots/build-log/16-shuffle/08-default-action-get-case-timeline.png)

**The webhook running once the workflow had a connected action and was saved.**

![The webhook running once the workflow had a connected action and was saved.](../../screenshots/build-log/16-shuffle/09-webhook-running.png)

**The test payload parsed into $exec, and TheHive's 400 for a body without a JSON content type.**

![The test payload parsed into $exec, and TheHive's 400 for a body without a JSON content type.](../../screenshots/build-log/16-shuffle/10-webhook-payload-content-type-400.png)

**The webhook added to the wrong workflow: 3.2 test - TheHive alert, whose node has a fixed sourceRef.**

![The webhook added to the wrong workflow: 3.2 test - TheHive alert, whose node has a fixed sourceRef.](../../screenshots/build-log/16-shuffle/11-webhook-added-to-wrong-workflow.png)

**TheHive's 400 when a dot after a variable pulled the whole $exec object into the description.**

![TheHive's 400 when a dot after a variable pulled the whole $exec object into the description.](../../screenshots/build-log/16-shuffle/12-dot-after-variable-invalid-json.png)

**The Splunk-shaped test payload creating an alert: 201.**

![The Splunk-shaped test payload creating an alert: 201.](../../screenshots/build-log/16-shuffle/13-webhook-payload-201.png)

**Splunk's alert form rejecting the http:// webhook URL (throttle still unticked).**

![Splunk's alert form rejecting the http:// webhook URL (throttle still unticked).](../../screenshots/build-log/16-shuffle/14-splunk-webhook-url-invalid.png)

**btool showing the webhook allow list is disabled, so it wasn't the cause.**

![btool showing the webhook allow list is disabled, so it wasn't the cause.](../../screenshots/build-log/16-shuffle/15-splunk-allowlist-disabled.png)

**Splunk's alert action log: POST to Shuffle over HTTPS, HTTP 200, exit code 0, twice.**

![Splunk's alert action log: POST to Shuffle over HTTPS, HTTP 200, exit code 0, twice.](../../screenshots/build-log/16-shuffle/16-splunk-webhook-sent-200.png)

**The Shuffle run started by Splunk: its payload in $exec and 201 from TheHive.**

![The Shuffle run started by Splunk: its payload in $exec and 201 from TheHive.](../../screenshots/build-log/16-shuffle/17-shuffle-run-from-splunk-201.png)

**The resulting TheHive alert, referenced by the Splunk job ID, with both IPs as observables.**

![The resulting TheHive alert, referenced by the Splunk job ID, with both IPs as observables.](../../screenshots/build-log/16-shuffle/18-thehive-alert-from-splunk.png)

**All three enrichment keys tested from shuffle01: VirusTotal, AbuseIPDB and MISP, each with HTTP 200 and the key never printed.**

![All three enrichment keys tested from shuffle01: VirusTotal, AbuseIPDB and MISP, each with HTTP 200 and the key never printed.](../../screenshots/build-log/16-shuffle/19-enrichment-keys-tested.png)

**The new MISP node defaulting to POST Add a feed.**

![The new MISP node defaulting to POST Add a feed.](../../screenshots/build-log/16-shuffle/20-misp-node-defaults-to-add-feed.png)

**MISP users and roles: shuffle@soc.lan enabled, and both read-only roles with API access but no add permission.**

![MISP users and roles: shuffle@soc.lan enabled, and both read-only roles with API access but no add permission.](../../screenshots/build-log/16-shuffle/21-misp-roles-api-access.png)

**The enrichment chain: webhook, MISP (start node), VirusTotal, AbuseIPDB, TheHive.**

![The enrichment chain: webhook, MISP (start node), VirusTotal, AbuseIPDB, TheHive.](../../screenshots/build-log/16-shuffle/22-enrichment-chain-canvas.png)

**A run stuck at "No results yet".**

![A run stuck at "No results yet".](../../screenshots/build-log/16-shuffle/23-run-stuck-no-results.png)

**Every app service at three copies, and tenzir-node using 663 MiB.**

![Every app service at three copies, and tenzir-node using 663 MiB.](../../screenshots/build-log/16-shuffle/24-app-services-three-replicas.png)

**tenzir-node stopped and back within seconds; the next run stuck with the app services gone.**

![tenzir-node stopped and back within seconds; the next run stuck with the app services gone.](../../screenshots/build-log/16-shuffle/25-tenzir-restarted-and-run-stuck.png)

**Orborus receiving SHUFFLE_APP_REPLICAS=1 while the services were back at 3/3, and the worker waiting on AbuseIPDB.**

![Orborus receiving SHUFFLE_APP_REPLICAS=1 while the services were back at 3/3, and the worker waiting on AbuseIPDB.](../../screenshots/build-log/16-shuffle/26-orborus-ignores-replicas-setting.png)

**Services scaled to 1/1, the orphaned run explained in AbuseIPDB's log, and the next run FINISHED 4/4.**

![Services scaled to 1/1, the orphaned run explained in AbuseIPDB's log, and the next run FINISHED 4/4.](../../screenshots/build-log/16-shuffle/27-scaled-to-one-run-finished.png)

**A real Splunk alert after the key rotation: the AbuseIPDB line blank because the node still used the deleted key.**

![A real Splunk alert after the key rotation: the AbuseIPDB line blank because the node still used the deleted key.](../../screenshots/build-log/16-shuffle/28-splunk-alert-abuseipdb-blank.png)

**The gate: an alert in TheHive enriched by VirusTotal, AbuseIPDB and MISP.**

![The gate: an alert in TheHive enriched by VirusTotal, AbuseIPDB and MISP.](../../screenshots/build-log/16-shuffle/29-enriched-alert.png)

## Backlog

- Skip VirusTotal and AbuseIPDB when the destination is a private address (needed once detections have internal destinations)
- Handle empty or failed lookups so the description says "no data" or "lookup failed" instead of blanks
- Replace the AbuseIPDB app with one that sends the key in the `Key` header, so it stops landing in execution history
- Watch for Orborus recreating app services at three copies (after app updates or restarts) and scale them back; find a supported way to set the count
- Decide on `tenzir-node` (about 660 MB, unpinned `main` image): find how Shuffle starts it and whether it can be disabled
- Avoid restarting the worker while runs are in flight; it orphans their results

- A trusted certificate for Shuffle (3443 serves a self-signed one, and Splunk's webhook action doesn't verify certificates)
- Make `results_link` usable: a Pi-hole DNS record for `splunk01`, or Splunk's server name set to its IP
- Escape double quotes in Splunk field values before they go into the webhook, so a signature containing `"` can't break the JSON body
- Splunk sends only the first result row; detections with several rows need per-row handling without colliding `sourceRef` values
- Remove the unused first test workflow
- Pin `shuffle-security` by digest in the compose file
- Back up the `shuffle-database` volume and `.env` (the encryption key can't be recreated)
- An authentication header on the webhook (Shuffle supports one; Splunk's built-in webhook action can't send custom headers, so this needs a different alert action)
- A host-level allow list for 3001/3443 (Default network and splunk01 only), applied in Docker's `DOCKER-USER` chain
- Ship Shuffle and OpenSearch logs to Splunk
- Revisit the OpenSearch heap after the baseline week
