# 3.2 · Shuffle: SOAR (in progress)

**Status:** 🚧 In progress. Shuffle 2.3.0 runs in Docker on shuffle01 with its OpenSearch database, and a Shuffle workflow has created an alert in TheHive through a dedicated service account. The Splunk webhook trigger and the enrichment (MISP, VirusTotal, AbuseIPDB) come next.

```mermaid
flowchart LR
    SPL[splunk01<br/>alert webhook<br/>next] -.->|POST :3001| SH[shuffle01<br/>Shuffle 2.3.0]
    SH -->|POST /api/v1/alert<br/>service account| TH[thehive01<br/>TheHive 5.8.1]
    SH -.->|enrichment, next| EN[MISP · VirusTotal · AbuseIPDB]
```

## What I built so far
- **A 6 GB VM:** Shuffle's compose file gives OpenSearch a fixed 3 GB heap, which can't fit in 4 GB alongside the backend and the workflow containers. I raised shuffle01 to 6 GB and the SOC budget to about 28 GB, with OpenSearch at a 2 GB heap.
- **Docker Engine 29.9 and Compose v5.6** from Docker's signed apt repo, used through `sudo` (no `docker` group)
- **Shuffle pinned to release 2.3.0** instead of `main` and `:latest` images, so the build is repeatable
- **Only the web UI exposed:** OpenSearch, the backend API and the shuffle-security service bound to localhost; ports 3001/3443 are the only ones reachable from the network
- **Secrets replaced before first start:** a generated OpenSearch admin password instead of the one published in the repo, and an encryption key for stored app credentials
- **A TheHive service account** (`shuffle@soc.lan`, analyst, API key only) and a test workflow that created an alert in TheHive

## Issues I ran into
| Issue | Cause | What I did |
| --- | --- | --- |
| The pull would have failed on one image | `shuffle-security` has no `2.3.0` tag, and my pinning `sed` changed every image | Put that one image back on `:latest` and recorded its digest |
| `vm.max_map_count` dropped from 1048576 to 262144 | Ubuntu 24.04 already ships a higher value; my `99-` sysctl file loaded last and lowered it to OpenSearch's minimum | Removed my file and kept the system default |
| The first workflow run would never have reached TheHive | New workflows start at a placeholder node that wasn't connected to the TheHive node | Deleted the placeholder so the TheHive node became the start node |
| TheHive returned `400 Invalid json: Unrecognized token '$'` | The app's body template leaves unquoted placeholders like `${flag}` and `${tlp}` as literal text when their fields are empty | Replaced the template with a fixed JSON body; the run returned 201 |
| Shuffle reported `"success": true` on the failed call | Shuffle's flag means the HTTP request completed, not that TheHive accepted it | Check `status` (201) and TheHive's own log instead |

## Decisions
- **6 GB with a 2 GB OpenSearch heap**, rather than 4 GB with a 1 GB heap or a RAM rebalance first
- **Pin the release:** `main` was a nightly merge, and `:latest` images change under you
- **Bind internal ports to 127.0.0.1 in the compose file:** Docker writes its own iptables rules, so a host firewall would never see published ports
- **A service account for Shuffle**, so every automated alert is attributed to `shuffle@soc.lan`, never to my own account
- **Alerts, not cases:** detections arrive as TheHive alerts for triage; only real ones get promoted to cases

**Skills:** Docker and Compose · container port exposure · release pinning · OpenSearch sizing · secrets handling · SOAR workflow design · REST API integration · service accounts and API keys · troubleshooting from both ends of an API call

➡️ [Deep dive](deep-dives/16-shuffle.md)
