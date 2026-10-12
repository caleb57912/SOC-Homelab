<div align="center">

# 🛡️ SOC Homelab

**A working Security Operations Center built on my own hardware, used to practice every part of a SOC analyst's job.**

<img src="https://img.shields.io/badge/Status-In_Progress-F2A900?style=for-the-badge">
<img src="https://img.shields.io/badge/Proxmox-E57000?style=for-the-badge&logo=proxmox&logoColor=white">
<img src="https://img.shields.io/badge/MITRE_ATT%26CK-Mapped-C8202F?style=for-the-badge">

</div>

---

## 🎯 Mission

Build, attack, and defend a real network end to end, then document it the way a SOC would: from the first log to the final incident report.

This lab exists to close the gap between **knowing** security concepts and **doing** security work. Certifications prove the knowledge. This repo is meant to show the hands-on part: detections I wrote, alerts I triaged, and incidents I investigated and wrote up.

## 💡 Why this project

| | |
|---|---|
| 🧠 **Learn the full role** | Cover the whole analyst workflow (monitoring, triage, investigation, response, reporting), not just tool installation |
| 🔁 **Build → Attack → Detect → Respond** | Every detection is tested against a real, simulated attack, and every alert gets a documented investigation |
| 🗺️ **Speak the industry's language** | Map attacks and detections to MITRE ATT&CK |
| 📂 **Show the work** | Every build step, config, rule, and report lives here so the process is fully transparent |

## 🏗️ Lab hardware

| Component | Role |
|---|---|
| **Proxmox VE server** | Hypervisor hosting the SIEM, endpoints, and attack VMs |
| **Ubiquiti UDR** | Perimeter firewall, VLAN segmentation, IDS/IPS |
| **Cisco Catalyst switch** | Core switching, VLAN trunking, SPAN port for traffic capture |
| **Suricata sensor (Proxmox VM)** | Passive IDS on a SPAN port with custom rules and AlienVault OTX threat intel |

### 🛡️ Layered detection

| Layer | Placement | Role |
|---|---|---|
| **UDR IPS** | Inline at the perimeter | Blocks known-bad traffic using Ubiquiti-managed signatures |
| **Suricata IDS** | Passive, internal (SPAN) | Alerts on internal traffic using ET Open, custom rules, and OTX IoCs |
| **SIEM** | Central | Correlates both sources into a single investigation view |

Network diagram and VLAN plan: [`docs/architecture`](docs/architecture)

## 🧭 Roadmap

- [x] Repository structure and documentation standards
- [ ] **Phase 1: Foundation.** Network segmentation, VLANs, isolated attack zone
- [ ] **Phase 2: Visibility.** SIEM deployment, endpoint agents, log ingestion
- [ ] **Phase 3: Detection.** UDR IPS, Suricata sensor with OTX threat intel, custom rules
- [ ] **Phase 4: Adversary simulation.** Run attacks and map them to MITRE ATT&CK
- [ ] **Phase 5: Response.** Triage runbooks, SOAR automation, containment
- [ ] **Phase 6: Reporting.** Full incident reports with timeline, IoCs, and lessons learned

## 📁 Repository map

| Folder | What's inside |
|---|---|
| [`docs/`](docs) | Architecture, build log, analyst runbooks |
| [`infrastructure/`](infrastructure) | Proxmox, network, and VM documentation |
| [`siem/`](siem) | SIEM configuration and dashboards |
| [`detections/`](detections) | Custom detection rules |
| [`attack-simulation/`](attack-simulation) | Attack scenarios and ATT&CK mapping |
| [`incident-reports/`](incident-reports) | Full incident investigations |
| [`threat-intel/`](threat-intel) | IoCs and threat intelligence notes |
| [`automation/`](automation) | SOAR playbooks and scripts |
| [`screenshots/`](screenshots) | Evidence supporting the documentation |

## 🔒 A note on sanitization

All configs, logs, and screenshots are scrubbed of public IPs, credentials, and other identifying details before they're published. Redacted values appear as `<REDACTED>`.

---

<div align="center">

**Caleb Santora** · Security+ · CySA+ · SecurityX · Associate of ISC2

[GitHub Profile](https://github.com/caleb57912)

</div>
