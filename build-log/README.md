# Build Log

A record of how this SOC was built. Each step has two documents:

- **Summary** (this folder): what was done, the key decisions, and the result. A 2-minute read.
- **Deep dive** (`deep-dives/`): the full configs, commands and issues behind each step.

## Phase 1: Foundation ✅

| Step | Summary | Highlights | Deep dive |
| --- | --- | --- | --- |
| 1.1 | [Proxmox host patching](01-proxmox-host-patching.md) | Fixed a broken update source; 213 packages and a new kernel after 337 days of uptime | [details](deep-dives/01-proxmox-host-patching.md) |
| 1.2 | [VM templates](02-vm-templates.md) | Ubuntu cloud-init golden image, key-only SSH | [details](deep-dives/02-vm-templates.md) |
| 1.3 | [SOC VLAN and zone firewall](03-udr-soc-segment.md) | Isolated VLAN 30, least-privilege zone policies | [details](deep-dives/03-udr-soc-segment.md) |
| 1.4 | [Catalyst 3750-X trunking](04-catalyst-3750x-trunking.md) | Password recovery; found and fixed an L2 loop, rogue L3 routing and a VTP risk | [details](deep-dives/04-catalyst-3750x-trunking.md) |
| 1.5 | [VLAN-aware Proxmox bridge](05-proxmox-vlan-aware-bridge.md) | 802.1Q tagging on the hypervisor, zero downtime | [details](deep-dives/05-proxmox-vlan-aware-bridge.md) |
| 1.6 | [End-to-end smoke test](06-smoke-test-vlan30.md) | Diagnosed a trunk mismatch with tcpdump; all firewall tests passed | [details](deep-dives/06-smoke-test-vlan30.md) |
| 1.7 | [SOC systems build](07-soc-systems-build.md) | 8 systems (6 VMs + 2 LXC), scripted, within a 24 GB RAM budget | [details](deep-dives/07-soc-systems-build.md) |

## Phase 2: Telemetry and intel ✅

| Step | Summary | Highlights | Deep dive |
| --- | --- | --- | --- |
| 2.1 | [Splunk Enterprise](08-splunk-installation.md) | SIEM as a hardened systemd service, index design | [details](deep-dives/08-splunk-installation.md) |
| 2.2 | [Pi-hole DNS + logging](09-pihole-dns.md) | Network-wide DNS sinkhole; found UDR DNS interception and an IoT segmentation gap; DNS logs in Splunk | [details](deep-dives/09-pihole-dns.md) |
| 2.3 | [Infrastructure logs](10-infrastructure-logs.md) | Firewall, switch and hypervisor → Splunk; fixed host-spoofing and timezone issues; closed the block-count investigation with evidence | [details](deep-dives/10-infrastructure-logs.md) |
| 2.4 | [Endpoint telemetry](11-endpoint-telemetry.md) | Sysmon + UF on my PC via a deployment server, one-script onboarding, least-privilege fix for Sysmon access, 76% noise cut | [details](deep-dives/11-endpoint-telemetry.md) |
| 2.5 | [Wazuh](12-wazuh.md) | Manager-only Wazuh feeding Splunk through my own add-on; CIS baselines for both systems (49% / 26%); password-protected enrollment | [details](deep-dives/12-wazuh.md) |
| 2.6 | [MISP](13-misp.md) | Native MISP in 3 GB; five feeds (650k+ IOCs) refreshing every 6h; fixed a Redis/PHP session outage; Splunk queries MISP via misp42splunk with a read-only, IP-locked key; 132k-domain IOC lookup; CIM DNS fields for Pi-hole | [details](deep-dives/13-misp.md) |
| 2.7 | [Zeek + Suricata](14-zeek-suricata.md) | SPAN of the uplink and admin port to a no-IP capture bridge; Zeek + Suricata (53k ET Open rules) in 3 GB; traced 742 noise alerts to switch STP/CDP/keepalive frames and filtered them; found CDP leaking the IOS version and ports left enabled since 1.4; alert-only Suricata filter and a forwarder shipping both to Splunk | [details](deep-dives/14-zeek-suricata.md) |

## Phase 3: Response and baseline 🚧

| Step | Summary | Highlights | Deep dive |
| --- | --- | --- | --- |
| 3.1 | [TheHive](15-thehive.md) | TheHive 5.8.1 with Cassandra 4.1 and Elasticsearch 8.19 in a 6 GB VM; both backends authenticated and localhost-only, scoped non-superuser service accounts, signed package verified, secrets kept out of the main config; traced a startup failure through three mismatched passwords; survived a reboot with the test case intact | [details](deep-dives/15-thehive.md) |
| 3.2 | [Shuffle](16-shuffle.md) | Shuffle 2.3.0 sized into 6 GB with internal ports on localhost and public default secrets replaced; Suricata detections flow Splunk → Shuffle webhook → TheHive alert, enriched by MISP, VirusTotal and AbuseIPDB (Phase 3 gate met); traced stuck runs to Orborus ignoring its replica setting, and a blank enrichment line to a rotated key | [details](deep-dives/16-shuffle.md) |
| 3.3 | [Velociraptor](17-velociraptor.md) | Velociraptor 0.77.1 in a 1 GB LXC as a non-root systemd service, GUI on the SOC address and API/monitoring on localhost; GPG-verified binary and MSI, client config with no private key, repacked MSI enrolled my PC; first Pslist collection (316 rows) triaged by signature and path with every unsigned process explained | [details](deep-dives/17-velociraptor.md) |
