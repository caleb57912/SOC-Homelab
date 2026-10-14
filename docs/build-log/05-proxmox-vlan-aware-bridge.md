# 1.5 · VLAN-Aware Proxmox Bridge

**Result:** VMs can join any VLAN with a single tag on their network card, and **zero existing services were disrupted**.

## What changed
The hypervisor's main bridge (`vmbr0`) became an **802.1Q-aware switch**:
- Untagged traffic (Proxmox management, VPN, game servers) stays on VLAN 1, unchanged
- A VM with `tag=30` lands on the SOC network automatically
- New VLANs never need another host network change

## Key decisions
- **Made the change from the LAN, not over the VPN.** The VPN runs on this same host, so a failed bridge reload would have cut off remote access.
- **Backed up first, used the validating GUI, and reviewed the diff** before applying. The rollback command was ready.
- **Defense in depth:** the bridge allows VLANs, but the switch trunk (`1,30` only) and the router firewall decide what actually flows.

## Bonus finding
Three unused NICs (`eno2`–`eno4`) are available, so the network sensor gets a **dedicated capture port**.

**Skills:** Linux bridging · VLAN tagging · safe change management

➡️ [Deep dive](deep-dives/05-proxmox-vlan-aware-bridge.md)
