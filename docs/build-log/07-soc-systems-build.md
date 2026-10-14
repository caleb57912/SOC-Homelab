# 1.7 · SOC Systems Build

**Result:** **8 SOC systems** deployed on VLAN 30 from a script, verified and snapshotted, within a **24 GB RAM budget**.

| System | Type | IP | RAM | Role |
| --- | --- | --- | --- | --- |
| splunk01 | VM | 10.30.0.10 | 6 GB | SIEM |
| wazuh01 | VM | 10.30.0.11 | 2 GB | Endpoint detection, FIM, vulnerabilities |
| sensor01 | VM | 10.30.0.12 | 3 GB | Zeek + Suricata network sensor |
| shuffle01 | VM | 10.30.0.20 | 4 GB | SOAR / automation |
| thehive01 | VM | 10.30.0.21 | 4 GB | Case management |
| misp01 | VM | 10.30.0.30 | 3 GB | Threat intelligence |
| dns01 | LXC | 10.30.0.53 | 0.5 GB | DNS logging / sinkhole |
| velo01 | LXC | 10.30.0.22 | 1 GB | Velociraptor DFIR |

## Key decisions
- **Scripted build:** one table drives one loop, so the whole SOC can be rebuilt from the document
- **Fixed two gaps once, in a shared first-boot config:** installed the guest agent and disabled IPv6 (the source of the noisy block count from 1.6)
- **Full clones, fixed RAM (no ballooning), autostart,** so production VMs don't depend on the template, the RAM budget is enforced, and the SOC survives reboots
- **Containers for lightweight services** saved ~1.5 GB, enough to fit MISP
- **Snapshots taken after cloud-init finished**, never mid-install

## Verification
```
splunk01: done | agent=active | ipv6_off=1   (×6 VMs)
All 8 reachable · key-only SSH · 23.5 / 24 GB
```

**Skills:** provisioning automation · cloud-init · capacity planning · Linux hardening

➡️ [Deep dive](deep-dives/07-soc-systems-build.md)
