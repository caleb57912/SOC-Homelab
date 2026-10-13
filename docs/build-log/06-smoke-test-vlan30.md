# Phase 1 · Step 1.6: End-to-End Smoke Test of the SOC VLAN

**Status:** Complete (passed after one fault was found and fixed)
**Goal:** Prove the full VLAN 30 path and every SOC firewall policy work before building production SOC systems on it.

## Summary

A throwaway VM was cloned from the Ubuntu template and placed on VLAN 30 with a static IP. The first attempt **failed**: the VM had no connectivity. Packet captures at two points along the path isolated the fault to the **UDR side of the trunk**, where the switch-facing port was set to drop all tagged VLANs. After a one-setting fix, all five tests passed and the firewall hit counters confirmed each policy was doing its job.

```
VM 10.30.0.99 (tag 30) → vmbr0 → eno1 → Catalyst Gi1/0/5 ⇄ Gi1/0/1 → UDR Port 1 → gateway 10.30.0.1 → zone firewall
```

## Test VM

```bash
qm clone 9000 999 --name smoke-test
qm set 999 --net0 virtio,bridge=vmbr0,tag=30 --ipconfig0 ip=10.30.0.99/24,gw=10.30.0.1 --nameserver 10.30.0.1
qm start 999
```

Static addressing through cloud-init: the SOC VLAN deliberately has no DHCP server.

## Troubleshooting: no connectivity on first boot

### Symptoms

- The VM console showed cloud-init `Ign:` / `Err:` lines: apt couldn't reach Ubuntu's mirrors.
- `ssh caleb@10.30.0.99` from the workstation → `Connection timed out`.

### Method: split the path with packet captures

Rather than changing settings by guesswork, I captured traffic on the host uplink to see how far frames actually got:

```bash
tcpdump -eni eno1 -c 10 vlan 30
```

```
bc:24:11:ca:81:59 > ff:ff:ff:ff:ff:ff, 802.1Q vlan 30, ARP, Request who-has 10.30.0.1 tell 10.30.0.99
78:da:6e:cd:db:05 > 01:00:0c:cc:cc:cd, 802.1Q vlan 30, STP 802.1w (Rapid PVST), bridge-id 801e.78:da:6e:cd:db:00
bc:24:11:ca:81:59 > ff:ff:ff:ff:ff:ff, 802.1Q vlan 30, ARP, Request who-has 10.30.0.1 tell 10.30.0.99
...
```

| Evidence | Conclusion |
| --- | --- |
| VM's ARP requests leave `eno1` **tagged VLAN 30** | ✅ The VM, its NIC tag and the VLAN-aware bridge are correct |
| Rapid-PVST BPDUs **for VLAN 30** arrive from the Catalyst | ✅ The switch knows VLAN 30 and forwards it on the pve trunk |
| **No ARP reply** from 10.30.0.1 | ❌ The gateway never answers: the fault is beyond the switch |

The switch MAC table confirmed it. VLAN 30 showed the VM's MAC on **Gi1/0/5 only**, with nothing learned from the UDR side:

```
MySwitch#show mac address-table vlan 30
  30    bc24.11ca.8159    DYNAMIC     Gi1/0/5
```

That left the UDR. The SOC network config was correct (VLAN 30, 10.30.0.1/24, zone SOC), so the remaining suspect was the switch-facing port.

### Root cause

**UDR Port 1 → Tagged VLAN Management: `Block All`.**

The Catalyst was tagging VLAN 30 toward the UDR, but the UDR was dropping every tagged frame on that port: a **trunk mismatch** where one side tags and the other side discards.

### Fix

| UDR Port 1 setting | Before | After |
| --- | --- | --- |
| Native VLAN | Default (1) | Default (1), unchanged |
| Tagged VLAN Management | **Block All** | **Custom → SOC** |
| PoE | On | **Off** (the switch is mains-powered) |

### Confirmation

```
bc:24:11:ca:81:59 > 1e:0b:8b:48:f4:e7, vlan 30, ARP, Request who-has 10.30.0.1 tell 10.30.0.99
1e:0b:8b:48:f4:e7 > bc:24:11:ca:81:59, vlan 30, ARP, Reply 10.30.0.1 is-at 1e:0b:8b:48:f4:e7
```

The gateway answered within seconds of the change, and SSH to the VM succeeded with no reboot.

## Test results

Run from inside the VM unless noted:

| # | Test | Expected | Result | Proves |
| --- | --- | --- | --- | --- |
| 1 | SSH from workstation (Main) → 10.30.0.99 | Connects | ✅ | Internal → SOC allow, both trunks, the VLAN-aware bridge |
| 2 | `ping -c 3 1.1.1.1` | Replies | ✅ | SOC → External allow, routing via the UDR |
| 3 | `getent hosts google.com` | Resolves | ✅ | SOC → Gateway DNS allow (`DNS-NTP` list) |
| 4 | `curl -k -m 5 https://10.30.0.1` | Timeout (`exit=28`) | ✅ | SOC → Gateway block: the router's management plane is unreachable |
| 5 | `curl -k -m 5 https://<proxmox-host>:8006` | Timeout (`exit=28`) | ✅ | SOC → Internal block: the SOC can't reach the home network |

### Firewall hit counters (UniFi)

| Policy | Hits | Interpretation |
| --- | --- | --- |
| Internal SOC Allow | 19 | Admin SSH sessions into the VM |
| SOC to Gateway (Allow, DNS-NTP) | 24 | DNS lookups |
| SOC → Gateway Block | ~2,800 | The block is enforced. The volume is far more than test 4 alone: see the open item below. |

The test VM was destroyed afterwards (`qm stop 999 && qm destroy 999`).

## Open item: high block count

~2,800 blocked packets from one idle VM is too many to come from the single `curl` test. The leading hypothesis is **IPv6 neighbor discovery and router solicitations** to the gateway (the block rule covers both IPv4 and IPv6, and the SOC VLAN has no IPv6 subnet). Other candidates are systemd-resolved DNS-over-TLS (853) and DHCP attempts.

**Plan:** confirm the source with packet capture or the UDR firewall logs in Splunk (Phase 2), then fix it at the source, for example by disabling IPv6 in the template's cloud-init config. **Not** by adding an allow rule just to silence the counter. This becomes the first detection-tuning case.

## Lessons learned

1. **Capture, don't guess.** Two observation points (host uplink + switch MAC table) narrowed a five-hop path to one setting in minutes.
2. **Check both ends of every trunk.** "Configured on the switch" isn't the same as "working": the far end must accept the same VLANs. UniFi's default for a port's tagged VLANs can be `Block All`.
3. **Static-IP VLANs fail quietly.** With no DHCP, there's no lease to check. ARP is the first thing to look at.
4. **Read the hit counters.** They confirmed each policy matched and exposed unexpected traffic worth investigating.
5. **Paused two over-permissive legacy rules** found during the earlier firewall review (broad external → internal and external → gateway access).

## Phase 1 network gate: passed ✅

- [x] SOC VLAN reachable end to end
- [x] SOC can reach the internet and the gateway's DNS
- [x] SOC can't reach the home network or router management
- [x] Admin access from the home network works
- [x] Existing services (Proxmox UI, VPN, game servers) unaffected

## Skills demonstrated

Structured network troubleshooting · packet capture and analysis (tcpdump, 802.1Q, ARP, STP) · MAC-table analysis · trunk mismatch diagnosis · firewall policy validation · evidence-based verification · hypothesis-driven investigation

## Next

**Step 1.7:** build the eight SOC systems (6 VMs + 2 LXC containers) on VLAN 30.
