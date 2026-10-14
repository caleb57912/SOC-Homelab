# 1.3 · SOC VLAN and Zone Firewall (UniFi UDR)

**Result:** An isolated **SOC network (VLAN 30, 10.30.0.0/24)** that can watch the home network but can't reach into it.

## Why segment the SOC
SOC tools ingest untrusted data all day (threat feeds, raw packets, logs from every device). If one is compromised, segmentation stops the attacker pivoting into the home network or taking over the router.

## Firewall policy (least privilege)
| From → To | Result |
| --- | --- |
| Home (Internal) → SOC | ✅ Allow (admin access, log forwarding) |
| SOC → Home | ❌ Return traffic only |
| SOC → Internet | ✅ Allow (updates, threat feeds) |
| SOC → Router (Gateway) | DNS + NTP only, everything else **blocked and logged** |
| SOC ↔ Guest/IoT, VPN, DMZ | ❌ Block |

## Key decisions
- **Locked the SOC out of the router's own management.** By default SOC → Gateway was "Allow All". A compromised SOC VM could have reached the router's admin UI, and owning the router means owning every VLAN.
- **Rule order matters:** the DNS/NTP Allow is evaluated before the Block (first match wins).
- **Only the Block rule is logged.** Any hit means something tried to reach router management, so the rule doubles as a detection.
- **Caught a backwards rule before saving.** My first draft allowed SOC → Home, which would have defeated the segmentation.

**Skills:** network segmentation · zone-based firewalls · least privilege · rule ordering

➡️ [Deep dive](deep-dives/03-udr-soc-segment.md)
