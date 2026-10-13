# Phase 1 · Step 1.4: Catalyst 3750-X Recovery, Hardening and VLAN Trunking

**Status:** Complete
**Goal:** Carry the SOC VLAN (30) from the UniFi UDR through the core switch to the Proxmox host, without disrupting the existing home network.

## Summary

The Cisco Catalyst sits between the UDR and the Proxmox server, so VLAN 30 has to cross it. Before the switch could be configured, it needed a **password recovery**, **SSH restored and hardened**, and a **pre-change audit**. The audit found a **Layer 2 loop**, **inter-VLAN routing enabled**, and a **risky VTP mode**. All three were fixed in the same change window, protected by a timed rollback.

**Final state:**

```
UDR Port 1 ──trunk (native 1, tagged 30)── Gi1/0/1 [3750-X] Gi1/0/5 ──trunk (native 1, tagged 30)── Proxmox
                                                      Gi1/0/3  shutdown (former loop)
```

---

## Part A: The switch

### A1. Hardware and software

| Item | Value |
| --- | --- |
| Model | Cisco Catalyst **WS-C3750X-24T-E**: 24× 10/100/1000 copper, network-module slot (1G/10G uplinks) |
| IOS | **15.2(4)E10**, C3750E-UNIVERSALK9 (crypto image, supports SSHv2) |
| Role | Layer 2 access/distribution switch between the UDR and the wired hosts |
| Management | SVI `Vlan1`, in-band on the Main network; dedicated `Fa0` management port disabled |

### A2. Port map (from the pre-change audit)

| Port | Description | Connected to | How it was identified |
| --- | --- | --- | --- |
| Gi1/0/1 | Trunk to UDR | UDR LAN Port 1 | UDR MACs learned on the port; the UDR port manager listed "Cisco Switch" |
| Gi1/0/3 | UNUSED, was loop | UDR LAN Port 2 (second cable) | Spanning tree **Backup / Blocking** (see A5) |
| Gi1/0/5 | Trunk to pve | Proxmox host (Dell PowerEdge) | Dell OUI MAC learned on the port |
| Gi1/0/6 – 24 | — | Nothing | Already administratively **disabled** (unused-port hardening) |

Identifying ports by **MAC address tables on both devices**, rather than by port labels or memory, is what exposed the mislabeled Gi1/0/3: it was described as "Con to 2nd Computer" but actually looped back to the router.

### A3. Credential recovery

The switch had been configured years earlier and the enable secret was lost. Recovery used Cisco's documented boot-loader procedure over the **console cable (9600 8N1, no flow control)**:

1. Hold **MODE** while powering on → `switch:` boot loader. The banner confirmed *"password-recovery mechanism is enabled"*.
2. `flash_init`, then rename `config.text` to `config.text.old` so the switch boots without its startup config.
3. Boot, decline the setup dialog, then rename the file back and `copy flash:config.text system:running-config`. The original config is restored, now with privileged access.
4. Set a new `enable secret` (strong hash), remove any legacy `enable password`, and `write memory`.

**Lessons:**

- **Physical access means full control.** Anyone with the console port and the MODE button can do this. The switch belongs in a physically secured location; alternatively, `no service password-recovery` can be set, at the cost of a factory reset being the only recovery path.
- **Recovery doesn't restore the SSH host key.** The RSA keypair is stored separately from `config.text`, so after recovery SSH was refused (`Connection refused`) until the key was regenerated.

### A4. Management-plane hardening

| Control | Configuration | Why |
| --- | --- | --- |
| Enable secret | `enable secret …` (hashed); `no enable password` | `enable password` is reversible or plaintext |
| SSH only | `line vty 0 15` / `transport input ssh` / `login local` | Telnet sends credentials in clear text |
| SSHv2 + new key | `ip domain-name …` / `crypto key generate rsa modulus 2048` / `ip ssh version 2` | Regenerated after recovery; 2048-bit replaces any legacy short key |
| Unused ports | Gi1/0/6 – 24 and Gi1/0/3 `shutdown` | Nothing can be plugged in unnoticed |

**Known limitation (finding):** the switch only offers **SHA-1 key exchange** (`diffie-hellman-group14-sha1`). Modern OpenSSH disables it by default, so connections need per-host legacy flags. 15.2(4)E10 is the final release for this platform, so the mitigation is **restricting who can reach management**: a VTY `access-class` limited to the admin workstation. That's tracked as a follow-up.

### A5. Pre-change audit findings

| # | Finding | Risk | Fix |
| --- | --- | --- | --- |
| 1 | **Layer 2 loop:** two cables between the UDR and the switch (UDR P1 → Gi1/0/1 and UDR P2 → Gi1/0/3). Gi1/0/3 was spanning-tree role **Backup, state BLK**. | Only spanning tree prevented a broadcast storm. During any re-convergence (such as converting Gi1/0/1 to a trunk), the loop could briefly forward. | `shutdown` Gi1/0/3, relabel it, physically remove the cable |
| 2 | **`ip routing` enabled** on the switch | A Layer 3 switch with SVIs can route between VLANs and **bypass the UDR's zone firewall** entirely | `no ip routing` (only Vlan1 had an IP; `ip default-gateway` already set) |
| 3 | **VTP mode server**, blank domain, revision 40 | Could overwrite another switch's VLAN database, or adopt a foreign one, if ever connected to a VTP switch | `vtp mode transparent` |
| 4 | **12 legacy VLANs** (DMZ, OSPF transit, guest, etc.) from a previous lab | Clutter; confusing during troubleshooting | Deferred: remove unused VLANs in a later cleanup |
| 5 | **SHA-1-only SSH** | Weak management crypto | Accepted for now; restrict management access (A4) |

**Why a "Backup" port means a loop:** in Rapid PVST+, the *Backup* role is assigned when a switch receives **its own BPDUs** on a port. That can only happen if the port leads back to the same switch, here through the UDR's internal LAN switch. A blocked port with no learned MAC addresses and a misleading description is easy to miss without checking spanning-tree state.

---

## Part B: The trunk change

### B1. Design

| Port | Mode | Native VLAN | Allowed VLANs |
| --- | --- | --- | --- |
| Gi1/0/1 (to UDR) | 802.1Q trunk, DTP off | 1 (Main, untagged) | 1, 30 |
| Gi1/0/5 (to pve) | 802.1Q trunk, DTP off | 1 (Main, untagged) | 1, 30 |

- **Native VLAN 1 untagged** keeps all existing Main-network traffic, including Proxmox management and the VPN path, exactly as it was. Only VLAN 30 is added as tagged.
- **Explicit allowed list (1, 30):** the switch has 12+ VLANs defined, and the default "allow all" would carry every one of them to the router and the hypervisor.
- **`switchport nonegotiate`:** disables DTP, so a port can't be talked into trunking by a connected device (VLAN-hopping hardening).
- **The UDR side matches:** UDR Port 1 is set to native *Default*, tagged *SOC only* (step 1.3).

### B2. Change procedure (with rollback)

The admin session itself crossed Gi1/0/1, the port being changed, so a mistake could cut off access. The change used a **timed rollback**:

```
reload in 10
```

If the session were lost and not recovered, the switch would reboot into the unchanged startup config after 10 minutes. The full change was pasted as one block so it would finish even if SSH dropped during spanning-tree re-convergence:

```
conf t
interface Gi1/0/3
 description UNUSED - was loop to UDR port 2
 shutdown
exit
vtp mode transparent
vlan 30
 name SOC
interface Gi1/0/5
 description Trunk to pve - native Main + SOC
 switchport trunk encapsulation dot1q
 switchport trunk native vlan 1
 switchport trunk allowed vlan 1,30
 switchport mode trunk
 switchport nonegotiate
interface Gi1/0/1
 description Trunk to UDR - native Main + SOC
 switchport trunk encapsulation dot1q
 switchport trunk native vlan 1
 switchport trunk allowed vlan 1,30
 switchport mode trunk
 switchport nonegotiate
exit
no ip routing
end
```

After verification:

```
reload cancel
write memory
```

### B3. Verification

```
MySwitch#show interfaces trunk
Port        Mode   Encapsulation  Status     Native vlan
Gi1/0/1     on     802.1q         trunking   1
Gi1/0/5     on     802.1q         trunking   1

Port        Vlans allowed on trunk
Gi1/0/1     1,30
Gi1/0/5     1,30

Port        Vlans in spanning tree forwarding state and not pruned
Gi1/0/1     1,30
Gi1/0/5     1,30
```

- [x] Both trunks up; only VLANs 1 and 30 allowed; both forwarding in spanning tree
- [x] Gi1/0/3 disabled (loop removed)
- [x] `no ip routing` in the running config
- [x] Proxmox web UI and internet reachable from the workstation after the change
- [x] `reload cancel` + `write memory`: change made permanent

## Design decisions

1. **Audit before change.** Checking the MAC tables, spanning-tree state, routing and VTP before touching anything turned up three risks that weren't in the plan. Configuring the trunk blind could have triggered the latent loop.
2. **Timed rollback instead of hoping.** `reload in` is the standard safety net when changing the path your own session uses.
3. **The firewall decides, not the switch.** Turning off routing keeps the switch at Layer 2, so all inter-VLAN traffic goes through the UDR's zone policies (step 1.3), where it's filtered and logged.
4. **Least privilege on trunks.** Only the VLANs that need to cross each link are allowed, and trunk negotiation is off.

## Follow-ups

- [ ] VTY `access-class` limiting SSH to the admin workstation
- [ ] Remove the legacy VLANs (2, 3, 4, 10, 11, 69, 100–102, 200, 485, 486)
- [ ] Send switch syslog to Splunk (step 2.3)
- [ ] Back up the running config to the repo, with secrets scrubbed
- [ ] SPAN session to the sensor NIC (step 2.7)

## Skills demonstrated

Cisco IOS · password recovery · management-plane hardening · 802.1Q trunking · Rapid PVST+ troubleshooting (loop detection via the Backup role) · VTP risk · Layer 3 switch security · change management with a timed rollback · MAC-table-based port discovery

## Next

**Step 1.5:** make the Proxmox bridge (`vmbr0`) VLAN-aware so VMs can be tagged into VLAN 30.
