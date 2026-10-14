# 2.1 · Splunk Enterprise (SIEM)

**Result:** Splunk Enterprise 10.6 running on `splunk01` as a hardened service, with an index design ready for every data source.

## What was built
- Splunk installed as an **all-in-one** instance (indexer + search head + receiver), the right size for lab volume
- Runs as a **systemd service** under a dedicated **non-root `splunk` user**, starting at boot
- **Transparent Huge Pages disabled** persistently (Splunk's performance recommendation)
- **Receiving port 9997** open for Universal Forwarders

## Index design
| Index | Data |
| --- | --- |
| `os` | Windows / Linux / Sysmon |
| `network` | Firewall, IDS, switch, Zeek, Suricata, VPN |
| `dns` | Every DNS query on the network |
| `wazuh` | Endpoint alerts, FIM, vulnerabilities |
| `intel` | Threat-intel IOCs and matches |

Separate indexes mean faster searches, retention per data type, and per-role access control. Nothing lands in `main`.

## Key decisions
- **Admin created through `user-seed.conf`** before first start: no default credentials, and Splunk deletes the file after use
- **Least privilege:** the service and CLI run as `splunk`, never root
- **Credential exposure handled as an incident:** a password ended up in shell history and pasted output, so it was rotated, and `splunk login` is used from now on instead of `-auth` on the command line

## Backlog
TLS certificates · HTTPS for the web UI · developer license before the trial ends · per-index retention · non-admin analyst account

**Skills:** SIEM deployment · Splunk architecture · systemd · least privilege · credential hygiene

➡️ [Deep dive](deep-dives/08-splunk-installation.md)
