# Phase 1 · Step 1.7: Building the SOC Systems

**Status:** Complete
**Goal:** Deploy the eight systems that make up the SOC on the isolated VLAN 30, consistently, within a fixed 24 GB RAM budget, and ready for software installation in Phase 2.

## Summary

Six VMs were cloned from the Ubuntu 24.04 cloud-init template and two lightweight services were deployed as LXC containers. Every system got a static IP, a VLAN 30 tag, fixed RAM, autostart, and a first-boot configuration that installs the QEMU guest agent and disables IPv6. All eight were verified reachable and correctly configured, then snapshotted as a known-good baseline.

## System inventory

| ID | Hostname | Type | IP | vCPU | RAM | Disk | Role (Phase 2+) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 300 | splunk01 | VM | 10.30.0.10 | 4 | 6 GB | 100 GB | SIEM: central log search, detections, dashboards |
| 301 | wazuh01 | VM | 10.30.0.11 | 2 | 2 GB | 50 GB | Wazuh manager: endpoint agents, FIM, vulnerability detection → Splunk |
| 302 | sensor01 | VM | 10.30.0.12 | 2 | 3 GB | 50 GB | Zeek + Suricata network sensor (SPAN feed on a dedicated NIC) |
| 303 | shuffle01 | VM | 10.30.0.20 | 2 | 4 GB | 40 GB | SOAR: alert enrichment and automation |
| 304 | thehive01 | VM | 10.30.0.21 | 2 | 4 GB | 60 GB | Case management |
| 305 | misp01 | VM | 10.30.0.30 | 2 | 3 GB | 60 GB | Threat intelligence platform and IOC feeds |
| 306 | dns01 | LXC | 10.30.0.53 | 1 | 0.5 GB | 8 GB | DNS sinkhole + query logging for the whole network |
| 307 | velo01 | LXC | 10.30.0.22 | 1 | 1 GB | 50 GB | Velociraptor server: endpoint forensics and triage |
| | | | | **16** | **23.5 GB** | **418 GB** | |

**Budget:** 23.5 GB of the 24 GB allocated to the SOC, leaving headroom on the host for its other workloads. VMs vs containers was a deliberate split: the two lightweight services (DNS, Velociraptor) run as LXC containers, which saved about 1.5 GB compared with full VMs and made room for MISP within the cap.

## Build approach

### 1. First-boot configuration (cloud-init vendor data)

Two gaps showed up earlier in the build, and both were fixed once, in a shared snippet applied to every VM:

| Gap | Evidence | Fix |
| --- | --- | --- |
| Proxmox couldn't see VM IPs or shut VMs down cleanly | Cloud images ship without the guest agent | Install and enable `qemu-guest-agent` |
| Thousands of blocked packets from an idle test VM to the gateway (step 1.6) | Leading hypothesis: IPv6 neighbor discovery on a VLAN with no IPv6 subnet | Disable IPv6 through `sysctl` |

```yaml
#cloud-config
timezone: UTC
package_update: true
packages:
  - qemu-guest-agent
write_files:
  - path: /etc/sysctl.d/99-disable-ipv6.conf
    content: |
      net.ipv6.conf.all.disable_ipv6 = 1
      net.ipv6.conf.default.disable_ipv6 = 1
runcmd:
  - sysctl --system
  - systemctl enable --now qemu-guest-agent
```

**UTC everywhere:** every SOC system logs in the same timezone, so events from different sources line up in the SIEM without conversion errors.

### 2. VMs: scripted, consistent clones

```bash
while read id name ip cores mem disk; do
  qm clone 9000 $id --name $name --full 1 --storage local-lvm
  qm set $id --cores $cores --memory $mem --balloon 0 --onboot 1 \
    --net0 virtio,bridge=vmbr0,tag=30 \
    --ipconfig0 ip=$ip/24,gw=10.30.0.1 --nameserver 10.30.0.1 --searchdomain soc.lan \
    --cicustom vendor=isostore:snippets/soc-vendor.yaml
  qm disk resize $id scsi0 ${disk}G
done <<'EOF'
300 splunk01 10.30.0.10 4 6144 100
301 wazuh01 10.30.0.11 2 2048 50
302 sensor01 10.30.0.12 2 3072 50
303 shuffle01 10.30.0.20 2 4096 40
304 thehive01 10.30.0.21 2 4096 60
305 misp01 10.30.0.30 2 3072 60
EOF
```

| Setting | Why |
| --- | --- |
| `--full 1` | Full clones are independent of template 9000. A linked clone would break if the template were changed or deleted. Linked clones are fine for throwaway tests, not production. |
| `--balloon 0` | Fixed RAM. Ballooning lets the host take memory back under pressure, which degrades search and indexing workloads and makes the RAM budget meaningless. |
| `--onboot 1` | The SOC comes back by itself after a host reboot. Monitoring that stays down after a reboot is a blind spot. |
| `tag=30` | Places the VM on the SOC VLAN through the VLAN-aware bridge (step 1.5). |
| Static IP via cloud-init | The SOC VLAN has no DHCP by design. Stable addresses are needed for log forwarding and firewall rules. |
| `qm disk resize` | The template stays small (3.5 GB); each clone grows to what its role needs. |

### 3. Containers

```bash
for c in "306 dns01 10.30.0.53 512 8" "307 velo01 10.30.0.22 1024 50"; do
  set -- $c
  pct create $1 isostore:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst \
    --hostname $2 --cores 1 --memory $4 --swap 0 --rootfs local-lvm:$5 \
    --net0 name=eth0,bridge=vmbr0,tag=30,ip=$3/24,gw=10.30.0.1 \
    --nameserver 10.30.0.1 --searchdomain soc.lan \
    --unprivileged 1 --features nesting=1 --ssh-public-keys /root/soc.pub --onboot 1
done
```

- **Unprivileged containers:** root inside the container maps to an unprivileged user on the host. That limits the damage if a container is compromised.
- **Key-only SSH:** the same dedicated SOC key as the VMs; no passwords.

## Verification

**Reachability**, from the Proxmox host on the Main network, through the UDR's Internal → SOC policy:

```
10.30.0.10 up    10.30.0.11 up    10.30.0.12 up    10.30.0.20 up
10.30.0.21 up    10.30.0.30 up    10.30.0.53 up    10.30.0.22 up
```

**First-boot configuration**, over SSH from the admin workstation:

```
splunk01:  done | agent=active | ipv6_off=1
wazuh01:   done | agent=active | ipv6_off=1
sensor01:  done | agent=active | ipv6_off=1
shuffle01: done | agent=active | ipv6_off=1
thehive01: done | agent=active | ipv6_off=1
misp01:    done | agent=active | ipv6_off=1
dns01      (SSH OK)
velo01     (SSH OK)
```

- [x] All 8 systems running, with autostart enabled
- [x] All 8 reachable on their static IPs from the admin network
- [x] Cloud-init finished on every VM
- [x] Guest agent active, so Proxmox reports VM IPs and can shut VMs down cleanly
- [x] IPv6 disabled on every VM
- [x] Key-based SSH works to every system
- [x] Total RAM 23.5 GB, within the 24 GB cap

## Baseline snapshots

Every system has a `clean-base` snapshot, taken **after** cloud-init reported `done`. Snapshots taken mid-install would bake a half-configured system into the rollback point.

```bash
for id in 300 301 302 303 304 305; do qm snapshot $id clean-base; done
for id in 306 307; do pct snapshot $id clean-base; done
```

These are the rollback point for every Phase 2 install: if a service install goes wrong, revert and retry instead of troubleshooting a broken state.

## Design notes

- **Infrastructure as code, lite:** every system is defined in one table and built by a loop, so the whole SOC can be rebuilt from this document. A later improvement is moving these definitions into Terraform with the `bpg/proxmox` provider.
- **Fix it once, upstream:** the guest agent and IPv6 problems were solved in the shared first-boot config, not by hand on eight machines.
- **Isolation by default:** every system lives on VLAN 30, can reach only the internet and the gateway's DNS/NTP, and can't start connections into the home network (verified in step 1.6).

## Open items

- [ ] **Step 1.1:** Proxmox host package updates (the enterprise repository needs replacing with no-subscription). Must be done before Phase 2 installs.
- [ ] Confirm the IPv6 change ends the high SOC → Gateway block count (watch the UniFi hit counter).
- [ ] Create a non-root admin user in the two containers.
- [ ] Attach `eno2` to sensor01 as the SPAN capture interface (step 2.7).

## Skills demonstrated

Proxmox VM and LXC provisioning · cloud-init · scripted and repeatable builds · capacity planning against a fixed resource budget · Linux hardening (key-only SSH, unprivileged containers, IPv6 reduction) · snapshot-based change safety

## Next

**Step 1.1:** fix the Proxmox host package updates, then **Phase 2:** Splunk.
