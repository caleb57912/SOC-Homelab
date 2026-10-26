# 1.7 · SOC Systems Build (Deep Dive)

With the network proven, I built the eight systems that make up the SOC. I wanted them consistent, scripted, and inside the 24 GB of RAM I'd set aside for the SOC on this host.

## Inventory

| ID | Hostname | Type | IP | vCPU | RAM | Disk | Role |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 300 | splunk01 | VM | 10.30.0.10 | 4 | 6 GB | 100 GB | SIEM |
| 301 | wazuh01 | VM | 10.30.0.11 | 2 | 2 GB | 50 GB | Wazuh manager |
| 302 | sensor01 | VM | 10.30.0.12 | 2 | 3 GB | 50 GB | Zeek + Suricata on a SPAN feed |
| 303 | shuffle01 | VM | 10.30.0.20 | 2 | 4 GB | 40 GB | SOAR |
| 304 | thehive01 | VM | 10.30.0.21 | 2 | 4 GB | 60 GB | Case management |
| 305 | misp01 | VM | 10.30.0.30 | 2 | 3 GB | 60 GB | Threat intel |
| 306 | dns01 | LXC | 10.30.0.53 | 1 | 0.5 GB | 8 GB | Pi-hole |
| 307 | velo01 | LXC | 10.30.0.22 | 1 | 1 GB | 50 GB | Velociraptor |
| | | | | **16** | **23.5 GB** | **418 GB** | |

DNS and Velociraptor run as containers. That saved about 1.5 GB against full VMs, and that's what let MISP fit under the cap.

## First-boot config

Two things had come up earlier, and I fixed both in one cloud-init vendor snippet that every VM gets:

- Cloud images ship without the QEMU guest agent, so Proxmox couldn't see VM IPs or shut them down cleanly.
- I suspected IPv6 neighbor discovery behind the high block count in 1.6, so I disabled IPv6. (Step 2.3 later showed the block count was something else, but the SOC VLAN has no IPv6 anyway.)

`/mnt/isostore/snippets/soc-vendor.yaml`:

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

I also set every system to UTC, so logs from different sources line up in Splunk without conversion.

## VMs

```bash
while read id name ip cores mem disk; do
  qm clone 9000 $id --name $name --full 1 --storage local-lvm
  qm set $id --cores $cores --memory $mem --balloon 0 --onboot 1 \
    --net0 virtio,bridge=vmbr0,tag=30 \
    --ipconfig0 ip=$ip/24,gw=10.30.0.1 --nameserver 10.30.0.1 --searchdomain soc.lan \
    --cicustom vendor=isostore:snippets/soc-vendor.yaml
  qm disk resize $id scsi0 ${disk}G
done <<'EOF2'
300 splunk01 10.30.0.10 4 6144 100
301 wazuh01 10.30.0.11 2 2048 50
302 sensor01 10.30.0.12 2 3072 50
303 shuffle01 10.30.0.20 2 4096 40
304 thehive01 10.30.0.21 2 4096 60
305 misp01 10.30.0.30 2 3072 60
EOF2
```

I used full clones so nothing depends on template 9000; a linked clone would break if I ever changed or deleted the template. RAM is fixed (`--balloon 0`), because ballooning lets the host take memory back under pressure, which would hurt Splunk's indexing and make the budget meaningless. Every system has `--onboot 1`, since monitoring that stays down after a reboot is a blind spot. IPs are static because the SOC VLAN has no DHCP, and log forwarding and firewall rules need stable addresses.

## Containers

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

Both are unprivileged, so root inside a container maps to an unprivileged user on the host. SSH is key-only with the same SOC key.

## Verification

From the Proxmox host, through the UDR's Internal → SOC policy:

```
10.30.0.10 up    10.30.0.11 up    10.30.0.12 up    10.30.0.20 up
10.30.0.21 up    10.30.0.30 up    10.30.0.53 up    10.30.0.22 up
```

Over SSH from my workstation:

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

## Snapshots

I took a `clean-base` snapshot of every system, but only after cloud-init reported `done`. A snapshot taken mid-install would bake a half-configured system into my rollback point.

```bash
for id in 300 301 302 303 304 305; do qm snapshot $id clean-base; done
for id in 306 307; do pct snapshot $id clean-base; done
```

If a Phase 2 install goes wrong, I revert and retry instead of troubleshooting a broken state.

## Backlog

- Non-root admin user in the two containers
- Move these definitions into Terraform (`bpg/proxmox`)
