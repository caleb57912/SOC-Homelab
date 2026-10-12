<div align="center">

# 🛡️ SOC Homelab

**A Security Operations Center segment defending my real home network, run like a production SOC.**

<img src="https://img.shields.io/badge/Status-Phase_1:_Foundation-F2A900?style=for-the-badge">
<img src="https://img.shields.io/badge/SIEM-Splunk-000000?style=for-the-badge&logo=splunk&logoColor=white">
<img src="https://img.shields.io/badge/MITRE_ATT%26CK-Mapped-C8202F?style=for-the-badge">

</div>

---

## 🎯 Mission

Monitor, detect, and respond to real activity on a live network, and document every case the way a SOC analyst would.

This isn't an attack lab with staged victims. It's a dedicated SOC segment watching my actual home network: real endpoints, real DNS, real firewall and IDS events. Every alert is triaged, given a verdict, investigated, written up, and used to tune the detection.

## 💡 Why this project

| | |
|---|---|
| 🧠 **Real data, real cases** | Alerts come from a live network, not scripted attacks, so triage involves the same noise and judgment calls a real SOC faces |
| 🔁 **The analyst loop** | Detect → Triage (TP / FP / benign TP) → Investigate → Write up → Tune |
| 🗺️ **Industry language** | Detections and findings are mapped to MITRE ATT&CK |
| 🧰 **Industry tooling** | Splunk, the SIEM most often named in SOC job postings, plus a full case management and SOAR pipeline |
| 📂 **Show the work** | Every use case, search, case file, and weekly report lives in this repo |

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
                 │  (isolated zone)  │
                 └───────────────────┘
```

**SOC VLAN firewall policy:** SOC → Internet allowed · SOC → home networks blocked · home → SOC on required ports only

### SOC segment

| VM | Role |
|---|---|
| **SPLUNK01** | SIEM: every log source lands here |
| **WAZUH01** | Wazuh manager: endpoint agents, FIM, vulnerability detection → Splunk |
| **SENSOR01** | Zeek + Suricata on the switch SPAN feed |
| **DNS01** | DNS resolver logging every device's queries |
| **SHUFFLE01** | SOAR: alert enrichment and case creation |
| **THEHIVE01** | Case management |
| **VELO01** | Velociraptor for endpoint forensics and triage |

### Alert pipeline

```
Splunk alert → Shuffle → Enrichment (VirusTotal, AbuseIPDB) → TheHive case → Velociraptor (if endpoint evidence needed)
```

### Telemetry sources

Endpoint Sysmon + Wazuh agents · UDR firewall, IDS/IPS, DHCP & WiFi events · Switch syslog · Hypervisor auth logs · VPN logs · DNS query logs · Zeek & Suricata

## 🧰 Stack

| Tool | Purpose | Status |
|---|---|---|
| Splunk | SIEM | 🔜 Planned |
| Wazuh | Endpoint agents, FIM, vulnerability detection | 🔜 Planned |
| Zeek + Suricata | Network monitoring and IDS | 🔜 Planned |
| Pi-hole / AdGuard Home | DNS logging | 🔜 Planned |
| Shuffle | SOAR | 🔜 Planned |
| TheHive | Case management | 🔜 Planned |
| Velociraptor | DFIR | 🔜 Planned |
| Atomic Red Team | Benign detection validation on my own endpoint | 🔜 Planned |

## 🧭 Roadmap

- [x] Repository structure and documentation standards
- [x] Design finalized
- [ ] **Phase 1: Foundation.** SOC VLAN, switch trunking, build the SOC VMs
- [ ] **Phase 2: Telemetry.** Endpoint agents and every network log source searchable in Splunk
- [ ] **Phase 3: Baseline.** Document a normal week; baseline searches and dashboards
- [ ] **Phase 4: Use-case loop.** Build a detection → triage → investigate → write up → tune (ongoing)
- [ ] **Phase 5: Reporting.** Weekly SOC reports and final packaging

### Planned use cases

| Category | Examples |
|---|---|
| 🔐 Authentication | Failed logins to the hypervisor or VPN, logins from new IPs |
| 🌐 Network | New devices joining, WAN scanning, outbound traffic spikes, IDS alerts |
| 🔎 DNS | IoT devices calling new domains, malicious or newly registered domains |
| 💻 Endpoint | New services or scheduled tasks, new local admins, encoded PowerShell, Run-key persistence |
| 🩹 Vulnerability | Vulnerable software detected by Wazuh |
| ⚙️ Infrastructure | Switch configuration changes |

## 📁 Repository map

| Folder | What's inside |
|---|---|
| [`docs/`](docs) | Architecture, build log, analyst runbooks |
| [`infrastructure/`](infrastructure) | Hypervisor, network, and VM documentation |
| [`siem/splunk/`](siem/splunk) | Searches, saved alerts, dashboards |
| [`siem/wazuh/`](siem/wazuh) | Agent configuration and rules |
| [`detections/`](detections) | Detection rules (Splunk, Sigma, Suricata) |
| [`detection-validation/`](detection-validation) | Benign Atomic Red Team tests that prove detections fire |
| [`cases/`](cases) | One folder per worked case: ticket, report, evidence |
| [`reports/weekly/`](reports/weekly) | Weekly SOC reports |
| [`threat-intel/`](threat-intel) | IoCs and threat intelligence notes |
| [`automation/`](automation) | Shuffle playbooks and scripts |
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
