# Phase 1 · Step 1.5: VLAN-Aware Proxmox Bridge

**Status:** Complete
**Goal:** Let VMs on the Proxmox host join the SOC VLAN (30) through a per-VM tag, without changing the host's management network or any existing VMs.

## Summary

The Proxmox host's main bridge (`vmbr0`) was converted from a plain Linux bridge into a **VLAN-aware (802.1Q) bridge**. VMs can now be placed on any VLAN by setting a tag on their virtual NIC. Untagged traffic, including Proxmox management, the VPN VM and the game servers, stays on VLAN 1 as before.

With this step, the end-to-end path for VLAN 30 is complete:

```
VM (tag 30) → vmbr0 (802.1Q) → eno1 → Catalyst Gi1/0/5 (trunk 1,30) → Gi1/0/1 (trunk 1,30) → UDR (SOC zone firewall)
```

## What "VLAN-aware" means

| | VLAN-aware off | VLAN-aware on |
| --- | --- | --- |
| Tagged frames | Not understood by the bridge | Sorted and isolated per VLAN inside the bridge |
| VM on VLAN 30 | Needs a sub-interface + bridge per VLAN (`eno1.30` → `vmbr30`) | Set **Tag = 30** on the VM's NIC |
| Untagged VMs | VLAN 1 | VLAN 1 (unchanged) |
| New VLANs later | Host network config change each time | No host change needed |

Functionally, each VM NIC becomes an **access port** and `eno1` becomes a **trunk**, the same model as the Catalyst switch. The bridge adds the 802.1Q tag on frames leaving through `eno1` and strips it on frames delivered to the VM, so the guest OS needs no VLAN configuration.

**Why this approach:** one bridge for every VLAN keeps the host config small and stable. Adding the SOC's eight systems, or any future segment, never requires touching the host's network file again, and every change to the network file is a chance to lose remote access.

## Starting state

| Item | Value |
| --- | --- |
| Bridge | `vmbr0`, static management IP on the Main network |
| Uplink | `eno1` → Catalyst Gi1/0/5 (already trunking VLANs 1 and 30, step 1.4) |
| Spare NICs | `eno2`, `eno3`, `eno4`: unused, no link (reserved; `eno2` → SPAN sensor in step 2.7) |
| Other bridges | `openvpn`: internal-only bridge for the VPN VM, deliberately **not** changed |
| Network stack | `ifupdown2` 3.2.0 (supports live reload, no reboot needed) |

## Procedure

**1. Back up the network config:**

```bash
cp /etc/network/interfaces /root/interfaces.bak-$(date +%F)
```

**2. Enable VLAN awareness** through the Proxmox UI (**System → Network → vmbr0 → VLAN aware → Apply Configuration**), not by editing the file directly. The UI validates the file and shows a diff before applying. The only lines added:

```
bridge-vlan-aware yes
bridge-vids 2-4094
```

The address, gateway and bridge ports were unchanged.

**3. Applied live** with `ifupdown2`, so there was no reboot and no outage.

## Verification

```bash
grep -A8 "iface vmbr0" /etc/network/interfaces
bridge vlan show dev eno1
ping -c 3 <gateway>
ip -br link show | grep eno
```

- [x] `vmbr0` contains `bridge-vlan-aware yes` and `bridge-vids 2-4094`
- [x] `eno1` carries VLAN 1 (PVID, egress untagged) plus 2–4094
- [x] Gateway ping 0% loss: management path intact
- [x] Proxmox web UI, VPN and existing VMs still reachable
- [x] `eno2`–`eno4` confirmed unused (DOWN): a dedicated SPAN capture NIC is available

## Risk management

| Risk | Mitigation |
| --- | --- |
| Losing remote access if the bridge reload fails | The change was made **from the LAN, not over the VPN**. The VPN VM runs on this same host, so a failed reload would also cut off the VPN. |
| A bad edit to `/etc/network/interfaces` | Timestamped backup; changes made through the validating GUI; reviewed the pending-changes diff before applying |
| Rollback | From the physical console: `cp /root/interfaces.bak-<date> /etc/network/interfaces && ifreload -a` |
| Existing VMs moving VLANs | Untagged NICs default to VLAN 1 (PVID), which matches the switch's native VLAN, so no VM changed segments |

## Design notes

- **The bridge isn't the security boundary.** `bridge-vids 2-4094` only allows VLANs on the host uplink. What actually reaches the host is limited by the Catalyst trunk (`allowed vlan 1,30`), and what VLAN 30 can reach is limited by the UDR zone firewall. Defense in depth: each layer allows only what it must.
- **Layer 2 isolation on the host:** a VM tagged 30 and an untagged VM on the same bridge **cannot** talk directly. Their traffic must go through the UDR, where SOC → Internal is blocked.
- **The internal `openvpn` bridge was left alone.** Changes stayed limited to the one bridge that needed them.

## Skills demonstrated

Proxmox VE networking · Linux bridging · 802.1Q VLAN tagging · change management (backup, validated change, rollback plan) · protecting the remote-access path during network changes

## Next

**Step 1.6:** smoke test. A throwaway VM on VLAN 30 verifies the full path and every SOC firewall policy end to end.
