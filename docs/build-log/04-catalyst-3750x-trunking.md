# 1.4 · Catalyst 3750-X: Recovery, Hardening and Trunking

**Result:** VLAN 30 trunked through the core switch, and **three hidden risks found and fixed** along the way.

## Recovery and hardening
- The enable password was lost, so I recovered access through the **console boot loader** (MODE button → `flash_init` → bypass the startup config → restore it with privileged access)
- Set a new hashed `enable secret`, **SSH-only** management, and regenerated a 2048-bit SSH key

## Pre-change audit findings
| Finding | Risk | Fix |
| --- | --- | --- |
| **Layer 2 loop:** two cables between the router and the switch | Spanning tree was the only thing preventing a broadcast storm | Shut the port, removed the cable |
| **`ip routing` enabled** on the switch | Inter-VLAN traffic could **bypass the firewall** | `no ip routing` |
| **VTP server mode**, blank domain | Could overwrite or adopt another switch's VLANs | `vtp mode transparent` |
| SHA-1-only SSH (platform limit) | Weak management crypto | Accepted; restrict management access |

The loop was spotted from a single clue: a port in spanning-tree role **Backup / Blocking** with no MAC addresses learned. *Backup* means the switch was receiving its own BPDUs.

## The change
```
interface Gi1/0/1   (to router)  /  Gi1/0/5 (to Proxmox)
 switchport mode trunk
 switchport trunk allowed vlan 1,30
 switchport nonegotiate
```
Protected with **`reload in 10`** (an automatic rollback if I locked myself out), then verified and saved.

**Skills:** Cisco IOS · password recovery · STP troubleshooting · 802.1Q · change management

➡️ [Deep dive](deep-dives/04-catalyst-3750x-trunking.md)
