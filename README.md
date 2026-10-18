<div align="center">

# 🛡️ SOC Homelab

**A Security Operations Center segment defending my real home network, run like a production SOC.**

<img src="https://img.shields.io/badge/Status-Phase_2:_Telemetry-F2A900?style=for-the-badge">
<img src="https://img.shields.io/badge/SIEM-Splunk-000000?style=for-the-badge&logo=splunk&logoColor=white">
<img src="https://img.shields.io/badge/MITRE_ATT%26CK-Mapped-C8202F?style=for-the-badge">

</div>

---

> ### 📖 Start here: [**Build Log →**](build-log/)
> Every step I've completed so far, in order, with the decisions, issues and fixes behind each one.
>
> - **Phase 1 Foundation ✅** network segmentation, switch hardening, 8 SOC systems
> - **Phase 2 Telemetry 🔄** Splunk, Pi-hole DNS logging, firewall / switch / hypervisor logs, Sysmon endpoint telemetry, Wazuh, MISP threat intel, Zeek + Suricata on a SPAN feed

## 🎯 Mission

Monitor, detect, and respond to real activity on a live network, and document every case the way a SOC analyst would.

This isn't an attack lab with staged victims. It's a dedicated SOC segment watching my actual home network: real endpoints, real DNS, real firewall and IDS events. Every alert is triaged, given a verdict, investigated, written up, and used to tune the detection.

## 💡 Why this project

| | |
|---|---|
| 🧠 **Real data, real cases** | Alerts come from a live network, not scripted attacks, so triage involves the same noise and judgment calls a real SOC faces |
| 🔁 **The analyst loop** | Detect → Triage (TP / FP / benign TP) → Investigate → Write up → Tune |
| 🗺️ **Industry language** | Detections and findings are mapped to MITRE ATT&CK |
| 🧰 **Industry tooling** | Splunk, the SIEM most often named in SOC job postings, plus threat intel, SOAR, case management, and DFIR |
| 📂 **Show the work** | Every use case, search, case file, and report lives in this repo |

## 🏗️ Architecture

```
                    Internet
                       │
              ┌────────┴────────┐
              │   Ubiquiti UDR   │  Firewall · IDS/IPS · VLANs · WiFi
              └────────┬────────┘
                       │ trunk
              ┌────────┴────────┐
              │ Cisco Catalyst  │  L2 only · SPAN ──────────┐
              │      3750       │                           │
              └───┬─────────┬───┘                           │
                  │         │                               │
          Wired endpoint   Proxmox VE ◄── mirrored traffic ─┘
                           │
                 ┌─────────┴─────────┐
                 │  SOC VLAN 30      │  10.30.0.0/24
                 │  8 systems        │
                 └───────────────────┘
```

**SOC VLAN firewall policy:** SOC → Internet allowed · SOC → home networks blocked · home → SOC on required ports only

### SOC segment

| System | Role |
|---|---|
| **SPLUNK01** | SIEM: every log source lands here |
| **DNS01** | Pi-hole: logs every device's DNS queries |
| **WAZUH01** | Wazuh manager: endpoint agents, FIM, vulnerability detection → Splunk |
| **MISP01** | Threat intel platform: IoC feeds for enrichment and matching |
| **SENSOR01** | Zeek + Suricata on the switch SPAN feed |
| **THEHIVE01** | Case management |
| **SHUFFLE01** | SOAR: alert enrichment and case creation |
| **VELO01** | Velociraptor for endpoint forensics and triage |

### Alert pipeline

```
Splunk alert → Shuffle → Enrichment (MISP, VirusTotal, AbuseIPDB) → TheHive case → Velociraptor (if endpoint evidence needed)
```

### Telemetry sources

Endpoint Sysmon + Splunk UF + Wazuh agents · UDR firewall, IDS/IPS, DHCP & WiFi events · Switch syslog · Hypervisor auth logs · VPN logs · DNS query logs · Zeek & Suricata

## 🧰 Stack

| Tool | Purpose | Status |
|---|---|---|
| Splunk | SIEM | ✅ Running |
| Pi-hole | DNS logging | ✅ Running |
| Wazuh | Endpoint agents, FIM, vulnerability detection | ✅ Running |
| MISP | Threat intelligence | ✅ Running |
| Zeek + Suricata | Network monitoring and IDS | ✅ Running |
| TheHive | Case management | 🔜 Planned |
| Shuffle | SOAR | 🔜 Planned |
| Velociraptor | DFIR | 🔜 Planned |
| Atomic Red Team | Benign detection validation on my own endpoint | 🔜 Planned |

## 🧭 Roadmap

| Phase | Steps | Gate |
|---|---|---|
| **1 · Foundation** | Update Proxmox · Templates · UDR VLAN 30 · 3750 trunks · VLAN-aware bridge · Smoke test · Build the 8 systems | All 8 up on VLAN 30, remote access unchanged |
| **2 · Telemetry + intel** | Splunk · Pi-hole · UDR, switch, Proxmox & VPN logs · Sysmon + UF · Wazuh · MISP · Sensor + SPAN | Every source searchable in Splunk |
| **3 · Response + baseline** | TheHive · Shuffle workflow · Velociraptor · A baseline week | A test alert reaches TheHive with enrichment |
| **4 · Use-case loop** | Failed Proxmox logins → New device → Vulnerable software → IoC match | Ongoing |
| **5 · Reporting** | Weekly SOC report · Monthly threat brief · README and resume after 4–5 cases | — |

- [x] Repository structure and documentation standards
- [x] Design finalized
- [x] Phase 1: Foundation
- [ ] Phase 2: Telemetry + intel (in progress)
- [ ] Phase 3: Response + baseline
- [ ] Phase 4: Use-case loop
- [ ] Phase 5: Reporting

### Use-case library

| Category | Examples |
|---|---|
| 🔐 Authentication | Failed logins to the hypervisor or VPN, logins from new IPs |
| 🌐 Network | New devices joining, WAN scanning, outbound traffic spikes, IDS alerts |
| 🔎 DNS & intel | IoC matches from MISP, IoT devices calling new domains, malicious or newly registered domains |
| 💻 Endpoint | New services or scheduled tasks, new local admins, encoded PowerShell, Run-key persistence |
| 🩹 Vulnerability | Vulnerable software detected by Wazuh |
| ⚙️ Infrastructure | Switch configuration changes |

## 📁 Repository map

Folders other than `build-log/` fill in as later phases are built.


| Folder | What's inside |
|---|---|
| [`build-log/`](build-log) | **Step-by-step record of the build so far** |
| [`docs/`](docs) | Architecture and analyst runbooks |
| [`infrastructure/`](infrastructure) | Hypervisor, network, and system documentation |
| [`siem/splunk/`](siem/splunk) | Searches, saved alerts, dashboards |
| [`siem/wazuh/`](siem/wazuh) | Agent configuration and rules |
| [`detections/`](detections) | Detection rules (Splunk, Sigma, Suricata) |
| [`detection-validation/`](detection-validation) | Benign Atomic Red Team tests that prove detections fire |
| [`cases/`](cases) | One folder per worked case: ticket, report, evidence |
| [`reports/`](reports) | Weekly SOC reports and monthly threat briefs |
| [`threat-intel/`](threat-intel) | MISP feeds, IoCs, and intel notes |
| [`automation/`](automation) | Shuffle playbooks |
| [`scripts/`](scripts) | Deployment, maintenance and troubleshooting scripts I run |
| [`ir/velociraptor/`](ir/velociraptor) | Velociraptor artifacts and collections |
| [`screenshots/`](screenshots) | Evidence supporting the documentation |

## 🔒 Privacy & sanitization

This SOC monitors a real household network. Before anything is published:

- Public IPs, hostnames, credentials, and keys are removed
- Other household members' devices, activity, and DNS queries are redacted
- Redacted values appear as `<REDACTED>`

---

<div align="center">

**Caleb Santora** · Security+ · CySA+ · SecurityX · Associate of ISC2

[GitHub Profile](https://github.com/caleb57912)

</div>
