# 2.6 · MISP: Threat Intelligence Platform

**Result:** MISP 2.5.50 runs natively on `misp01` within its 3 GB RAM budget. Five public feeds (CIRCL OSINT, Botvrij.eu, abuse.ch URLhaus, ThreatFox and Feodo) refresh every 6 hours, giving me about 845 events and 110,000+ indicators. Splunk has a read-only, IP-locked API key, tested from splunk01. Connecting Splunk to MISP (misp42splunk) is the next part of this step.

```mermaid
flowchart LR
    F[Public feeds<br/>CIRCL · Botvrij · abuse.ch] -->|HTTPS every 6h| M[misp01<br/>MISP 2.5.50]
    M --- DB[(MariaDB<br/>events + attributes)]
    M --- R[(Redis<br/>sessions + job queue)]
    S[splunk01] -->|HTTPS API<br/>read-only key<br/>10.30.0.10/32 only| M
```

## What I built
- **A native MISP install** using MISP's official Ubuntu 24.04 script, which I read before running it as root. I skipped the Docker version because its extra containers don't fit in 3 GB.
- **Memory tuning for a 3 GB VM:** a 2 GB swapfile as a safety net, and MariaDB's buffer pool cut from about 1.45 GB (the script's 50%-of-RAM default) to 768 MB
- **Hardening from MISP's own security audit:** config files no longer world-readable, a Redis password, an encryption key for stored secrets, browser caching off, suspicious-login alerts on
- **Five feeds stored as events**, with caching off so feed data lives on disk rather than in RAM
- **Least-privilege API access for Splunk:** an `API Read Only` role, a dedicated service account, and an auth key that is read-only and only accepted from splunk01

## Issues I ran into
| Issue | Cause | What I did |
| --- | --- | --- |
| Installer would have set an unreachable base URL | Its default domain is `misp.local`, which nothing on my network resolves | Ran it with `MISP_DOMAIN=10.30.0.30` |
| MariaDB sized for a bigger machine | The script gives the buffer pool 50% of RAM | Set it to 768 MB and confirmed the live value |
| The Redis password was printed to my terminal | MISP's `setSetting` command echoes the new value | Rotated the password with output sent to `/dev/null` |
| Web UI returned HTTP 500 after I added the Redis password | PHP stores login sessions in Redis through its own `php.ini` setting, which still had no password | Traced it through MISP's error log to `NOAUTH`, added the password to `session.save_path`, and locked down `php.ini` |
| No users in the auth key form | The built-in Read Only role has no API key permission | Created an `API Read Only` role with only that permission added |

## Decisions
- **Native install, not Docker:** about 850 MB idle and 1.4 GB still available during the first feed import
- **Fetch and store, caching off:** Splunk reads MISP events through the API, so caching whole feeds in Redis would only cost RAM
- **misp-modules deferred:** enrichment lookups need another 300–500 MB, and nothing in this step depends on them
- **Benign diagnostics left alone:** two schema differences that come from MariaDB vs MySQL defaults (database version 159 of 159, no failed migrations)

## Intel loaded
| Source | Events | Indicators |
| --- | --- | --- |
| CIRCL OSINT + Botvrij.eu (various original authors) | ~840 | ~70,000 |
| abuse.ch URLhaus | 1 | ~33,400 |
| abuse.ch ThreatFox | 1 | ~7,700 |
| abuse.ch Feodo (active botnet C2 only) | 1 | ~5 |

URLhaus is the biggest feed and also the shortest-lived, since malware URLs often die within days. That matters for false positives when I build Splunk alerts on it.

**Skills:** MISP · threat intel feeds · Linux memory tuning · MariaDB · Redis · PHP session troubleshooting · API least privilege · secret handling

➡️ [Deep dive](deep-dives/13-misp.md)
