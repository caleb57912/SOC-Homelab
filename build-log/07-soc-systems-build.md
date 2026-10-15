# 1.7 · SOC Systems Build

**Result:** Eight SOC systems deployed on VLAN 30 from a script, verified and snapshotted, inside a 24 GB RAM budget.

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

## Decisions
- **Scripted build.** One table drives one loop, so I can rebuild the whole SOC from this document.
- **Fixed two gaps once, in a shared first-boot config:** the QEMU guest agent was missing, and I disabled IPv6 (my guess at the time for the block count in 1.6).
- **Full clones, fixed RAM, autostart.** The VMs don't depend on the template, the RAM budget means something, and the SOC comes back after a host reboot.
- **Containers for the light services.** That saved about 1.5 GB, which is what made room for MISP.
- **Snapshots only after cloud-init finished,** so every rollback point is a clean system.

**Skills:** provisioning automation · cloud-init · capacity planning · Linux hardening

➡️ [Deep dive](deep-dives/07-soc-systems-build.md)
