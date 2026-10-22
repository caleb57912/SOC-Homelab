# 3.2 · Shuffle (Deep Dive, in progress)

Shuffle is the SOAR (security orchestration, automation and response) layer: it receives detections, enriches them and hands them to TheHive. This entry so far covers sizing shuffle01, Docker, installing Shuffle 2.3.0, locking down its ports and secrets, the first workflow that creates a TheHive alert, and the webhook that Splunk will call. Splunk's alert and enrichment follow.

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

## Splunk → Shuffle: the webhook (in progress)

The second workflow, `3.2 Splunk alert to TheHive`, starts from a **Webhook** trigger named `splunk_alert` instead of a manual run. Shuffle generates its URL:

```
http://10.30.0.20:3001/api/v1/hooks/webhook_<id>
```

It's served through the frontend on 3001, the only Shuffle port reachable from the network, so splunk01 can post to it.

### Issue: the webhook stayed "uninitialized"

Clicking **Start** on a webhook that was the only node in an unsaved workflow did nothing; the panel kept saying `Webhook: uninitialized`, and a test POST returned `{"success": false}`. Shuffle starts a webhook against the saved workflow, and this one had unsaved changes and no action after the trigger. After I added the TheHive node, connected the trigger to it and saved, **Start** switched the webhook to `running`.

### Issue: a new node defaults to the first action

The new TheHive node came up with **GET Get case timeline**, the first action in the app's list, which asks for a case ID and creates nothing. I switched it to **POST Create alert** and gave it a body built from the webhook data:

```json
{"type":"splunk","source":"splunk01","sourceRef":"$exec.sid","title":"$exec.search_name","description":"Splunk alert $exec.search_name. Signature: $exec.result.signature. $exec.result.src_ip -> $exec.result.dest_ip","severity":2,"tlp":2,"pap":2,"tags":["splunk","suricata"],"observables":[{"dataType":"ip","data":"$exec.result.src_ip"},{"dataType":"ip","data":"$exec.result.dest_ip"}]}
```

| Placeholder | Source |
| --- | --- |
| `$exec` | The JSON the webhook received |
| `$exec.sid` | Splunk's search job ID, unique per run, used as TheHive's required unique `sourceRef` |
| `$exec.search_name` | The Splunk alert's name |
| `$exec.result.<field>` | Fields from the first result row (Splunk's webhook action sends only that row) |

`tlp` and `pap` are 2 (AMBER) because these alerts carry internal addresses.

### Testing with a payload shaped like Splunk's

Before involving Splunk I posted the same shape Splunk's webhook action sends:

```bash
H="http://10.30.0.20:3001/api/v1/hooks/webhook_<id>"
curl -s -X POST -d '{"sid":"manual-test-001","search_name":"Manual webhook test","result":{"src_ip":"192.168.1.11","dest_ip":"1.1.1.1","signature":"SOC-LAB local test rule"}}' "$H"
```

Shuffle answered `{"success": true, "execution_id": "..."}`, and the run showed the payload parsed into `$exec.sid`, `$exec.search_name` and `$exec.result.*`. The TheHive node then got a different 400:

```
"status": 400
"message": "Mismatch for one of({body as application/json (UTF-8)}|{body as multipart/form-data}), expected 'app..."
```

TheHive only accepts an alert body declared as `application/json` (or a multipart upload), so it rejected this one before parsing it. The first workflow worked because its node kept the action's default headers. This node's **Headers** field held `Content-Type=application/json` while it was on Get case timeline, and switching the action reset it.

## Next

- Set the node's headers to `Content-Type=application/json` and `Accept=application/json`, restart the webhook and re-test with a new `sid`
- Splunk: a scheduled alert on Suricata test rule sid 9000001 (dotted fields renamed so `$exec.result.*` can reach them) with a webhook action to Shuffle, then the full chain from a real detection
- Enrichment: MISP lookups, VirusTotal and AbuseIPDB for the observables
- Final write-up and HANDOFF update when the Phase 3 gate (a test alert reaching TheHive with enrichment) is met

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

## Backlog

- HTTPS for the Shuffle UI (3443 serves a self-signed certificate)
- Pin `shuffle-security` by digest in the compose file
- Back up the `shuffle-database` volume and `.env` (the encryption key can't be recreated)
- An authentication header on the webhook (Shuffle supports one; Splunk's built-in webhook action can't send custom headers, so this needs a different alert action)
- A host-level allow list for 3001/3443 (Default network and splunk01 only), applied in Docker's `DOCKER-USER` chain
- Ship Shuffle and OpenSearch logs to Splunk
- Revisit the OpenSearch heap after the baseline week
