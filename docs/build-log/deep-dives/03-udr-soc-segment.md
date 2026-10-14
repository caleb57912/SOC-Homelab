# Phase 1 · Step 1.3: SOC Network Segment and Firewall Zone (UniFi UDR)

**Status:** Complete (firewall verified live in step 1.6)
**Goal:** Create an isolated network segment for the SOC tooling that can watch the home network without being able to reach into it.

## Summary

I created a dedicated **SOC VLAN (30, 10.30.0.0/24)** on the Ubiquiti UDR and placed it in its own **firewall zone**. The policies follow least privilege:

- The home network can reach the SOC to manage it.
- The SOC can reach the internet for updates and threat feeds.
- The SOC **cannot** open connections into the home network, the guest/IoT network, or the router's own management interfaces.

## Why segment the SOC

SOC tools are high-value, high-exposure systems. They:

- **Ingest untrusted data constantly:** threat-intel feeds (MISP), raw packet parsing (Zeek and Suricata), and logs from every device.
- **Hold sensitive data:** logs from the whole network, credentials for integrations, and case notes.

If one is compromised, segmentation limits the blast radius: an attacker on a SOC VM can't pivot into the home network or take over the router. This mirrors how enterprise SOC and management networks are isolated from production.

## Network

| Setting | Value | Reason |
| --- | --- | --- |
| Name | SOC | |
| VLAN ID | 30 | Separates SOC traffic from the default/Main network at Layer 2 |
| Subnet | 10.30.0.0/24 | Distinct range; the VLAN number matches the third octet, which makes logs easier to read |
| Gateway | 10.30.0.1 (UDR) | |
| DHCP | Disabled | Every SOC system has a static IP, so log sources keep stable addresses and a rogue device gets no automatic address |

## Zone-based firewall policy

UniFi uses zone-based firewalling: networks are grouped into zones, and policies are written between zones. Built-in default policies (locked) apply to each zone pair; **custom policies are evaluated first** and override them.

### Resulting zone matrix (SOC rows and columns)

| From → To | Result | How |
| --- | --- | --- |
| Internal → SOC | **Allow** | Custom policy (admin access, log forwarding from endpoints) |
| SOC → Internal | **Return traffic only** | Auto-return from the policy above; the SOC can't start new connections |
| SOC → External | Allow | Updates, package installs, threat-intel feeds |
| SOC → Gateway | **DNS + NTP only** | Custom allow + custom block (see below) |
| SOC → Hotspot (Guest/IoT) | Block | Built-in default |
| SOC → VPN / DMZ | Block | Built-in default |
| Hotspot / DMZ / VPN → SOC | Block | Built-in default |

### Custom policies

| ID | Name | Source → Destination | Action | Ports | Logging |
| --- | --- | --- | --- | --- | --- |
| 10000 | Internal SOC Allow | Internal → SOC | Allow (+ auto return) | Any | Off |
| 10000 | SOC to Gateway | SOC → Gateway | Allow | `DNS-NTP` list (53, 123) TCP/UDP | Off |
| 10001 | SOC → Gateway Block | SOC → Gateway | Block | Any | **On** |

## Design decisions

### 1. Direction matters: Internal → SOC, never SOC → Internal

Firewall policies are written from the side that **starts** the connection. My workstation starts connections into the SOC (SSH, the Splunk web UI, log forwarding), so the allow is **Internal → SOC**. Replies are covered by "Auto Allow Return Traffic."

The UI makes it easy to build this policy backwards. My first draft had SOC as the source, which would have let the SOC open connections into the home network and defeated the segmentation. I caught it before saving. Since then I check each rule by reading it as a sentence: "Internal → SOC → Allow."

### 2. Locking the SOC out of the router itself

The **Gateway** zone is the UDR itself: its admin UI, SSH, API and services. By default, SOC → Gateway was **Allow All**, so a compromised SOC VM could reach the router's management interface. Owning the router means owning every VLAN.

SOC VMs only need two services from the UDR:

| Service | Port | Why it's needed |
| --- | --- | --- |
| DNS | 53 | Name resolution for packages, feeds and updates |
| NTP | 123 | Accurate time. SIEM correlation depends on consistent timestamps across sources. |

So the policy is **allow those two, then deny everything else**.

### 3. Rule order: first match wins

Each packet is checked top to bottom, and the first matching rule decides. The Allow (ID 10000) must be evaluated before the Block (ID 10001):

- DNS query → matches the Allow → permitted
- HTTPS to the UDR admin UI → no match on the Allow → falls to the Block → dropped

If the order were reversed, DNS would be blocked, and every VM would fail with "temporary failure in name resolution."

**Note:** the UniFi policy list sorts alphabetically by name, not by evaluation order. Evaluation order is shown by the **per-zone-pair ID** (10000, 10001, …).

### 4. Log the block, not the allow

- **Allowed DNS/NTP:** thousands of routine events a day. Logging them is noise.
- **Blocked SOC → Gateway:** should never happen in normal operation. Every hit means something in the SOC tried to reach router management.

So only the Block rule has syslog logging on. Once Splunk is running, **this rule becomes a detection**: any hit generates an alert.

### 5. Reusable port lists

DNS and NTP were defined as a named port list (`DNS-NTP`) rather than one rule per port. The same pattern will be used to tighten Internal → SOC down to specific service ports in Phase 2.

## Verification

- [x] Zone matrix shows SOC → Internal, Hotspot, VPN and DMZ blocked; SOC → External allowed
- [x] Internal → SOC shows Allow; SOC → Internal shows return-only
- [x] SOC → Gateway Allow (10000) is evaluated before the Block (10001)
- [ ] Live test from a SOC VM (step 1.6):
    - `nslookup` via 10.30.0.1 → **succeeds**
    - `curl -k https://10.30.0.1` → **times out**, and the Block rule's hit counter increases
    - A connection to a Main-network host → **fails**
    - `ping 1.1.1.1` → **succeeds**

## Known limitations and next steps

- **Internal → SOC is currently Allow Any.** That's fine during the build; in Phase 2 it will be tightened to the specific service ports (Splunk web/forwarding, Wazuh agents, syslog, SSH).
- **Syslog logging** only takes effect once a remote syslog target (Splunk) is configured in step 2.3.
- **Pinging the gateway (10.30.0.1) from the SOC fails by design**, because ICMP isn't in the allow list. Test connectivity against an external IP instead.

## Skills demonstrated

Network segmentation · VLAN design · zone-based firewall policy · least privilege · rule ordering and evaluation · detection-oriented logging · secure management-plane design

## Next

**Step 1.4:** trunk VLAN 30 through the Cisco Catalyst 3750 to the Proxmox host.
