# 1.1 · Proxmox Host Patching (Deep Dive)

I didn't want to install security tooling on a host I hadn't checked, so the first thing I did was look at the hypervisor's patch state.

## What I found

| Item | State |
| --- | --- |
| Uptime | 337 days |
| Kernel | 6.8.12-9 |
| `pve-manager` | 8.4.0 |
| Updates | Failing with `401 Unauthorized` |

The enterprise repository was enabled without a subscription, so `apt update` had been failing quietly for months. No security fixes had been installed. Nothing in the UI pointed to it.

## The fix

I disabled the enterprise and Ceph repositories and added the no-subscription repository for the same release (Proxmox VE 8 / Debian 12 bookworm):

```bash
sed -i 's/^deb/#deb/' /etc/apt/sources.list.d/pve-enterprise.list
[ -f /etc/apt/sources.list.d/ceph.list ] && sed -i 's/^deb/#deb/' /etc/apt/sources.list.d/ceph.list
echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" > /etc/apt/sources.list.d/pve-no-subscription.list
apt update
apt full-upgrade -y
reboot
```

I used `full-upgrade` rather than `upgrade` because Proxmox kernel updates pull in new packages, and plain `upgrade` holds those back. When the package manager asked about modified config files, I kept my local versions.

213 packages were upgraded. The ones that mattered most:

| Component | Change |
| --- | --- |
| Kernel | 6.8.12-9 → 6.8.12-43 |
| `pve-manager` | 8.4.0 → 8.4.21 |
| OpenSSH, OpenSSL | Several security releases |
| `qemu-server`, `pve-container`, `lxc-pve` | The VM and container runtimes the SOC runs on |
| ZFS, GRUB, shim | Storage and boot chain |

## Decisions

I stayed on Proxmox 8. Debian 13 is out, but a major-version upgrade in the middle of a build is its own change with its own backup and rollback plan.

I waited until I was home to reboot. My VPN VM ran on this host at the time, so a failed boot would have cut off my only remote way in.

By the time I rebooted, the eight SOC systems from step 1.7 existed with autostart enabled, so the reboot also tested that the whole SOC comes back on its own.

## Verification

```
$ uname -r
6.8.12-43-pve
$ pveversion
pve-manager/8.4.21/2606ac850d46da29 (running kernel: 6.8.12-43-pve)
```

```
300 splunk01   running     301 wazuh01    running     302 sensor01   running
303 shuffle01  running     304 thehive01  running     305 misp01     running
306 dns01      running     307 velo01     running
```

`apt update` runs clean, the new kernel is live, and all eight SOC systems came back without intervention.

## Backlog

- Patch on a regular schedule and log each run here
- Plan the Proxmox 8 → 9 upgrade as a separate change
