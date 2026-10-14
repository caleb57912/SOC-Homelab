# Phase 1 · Step 1.1: Proxmox Host Patching

**Status:** Complete
**Goal:** Bring the hypervisor up to date before installing any SOC software on it. Security tooling shouldn't run on an unpatched host.

## Finding

| Item | Before |
| --- | --- |
| Uptime | **337 days** without a reboot |
| Kernel | 6.8.12-9 |
| `pve-manager` | 8.4.0 |
| Updates | **Failing.** The Proxmox *enterprise* repository was enabled with no subscription, so `apt update` returned `401 Unauthorized`, and no updates (including security fixes) had been installed in months. |

The host looked healthy in the UI, but its package source was broken. That kind of gap doesn't show up until someone checks.

## Fix

Switched from the enterprise repository (subscription required) to the official **no-subscription** repository, staying on the same release (Proxmox VE 8 / Debian 12 *bookworm*):

```bash
sed -i 's/^deb/#deb/' /etc/apt/sources.list.d/pve-enterprise.list
[ -f /etc/apt/sources.list.d/ceph.list ] && sed -i 's/^deb/#deb/' /etc/apt/sources.list.d/ceph.list
echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" > /etc/apt/sources.list.d/pve-no-subscription.list
apt update
apt full-upgrade -y
reboot
```

**213 packages** were upgraded, including:

| Component | Before → After | Relevance |
| --- | --- | --- |
| Kernel (`proxmox-kernel-6.8`) | 6.8.12-9 → **6.8.12-43** | 34 kernel releases of fixes |
| `pve-manager` | 8.4.0 → **8.4.21** | Hypervisor management stack |
| OpenSSH, OpenSSL / libssl3 | Multiple security releases | The host's exposed management services |
| `qemu-server`, `pve-container`, `lxc-pve` | Updated | The VM and LXC runtimes hosting the SOC |
| ZFS, GRUB, shim | Updated | Storage and boot chain |
| `ca-certificates`, `tzdata`, glibc, systemd | Updated | Trust store, time zone data, core OS |

## Decisions

- **`full-upgrade`, not `upgrade`:** Proxmox updates often add or replace dependencies (kernels in particular), and plain `upgrade` would hold those back.
- **Stayed on Proxmox 8:** Debian 13 has been released (so bookworm now shows as *oldstable*), but a major-version upgrade mid-project is a separate, planned change, not something to bundle with patching.
- **Kept local config files** whenever the package manager asked about a modified config, so the host's existing customizations survived.
- **The reboot was scheduled while on-site:** the VPN runs on this host, so a failed boot would have cut off remote access.
- **Autostart was proven:** all eight SOC systems had `onboot` set in step 1.7, so this reboot doubled as a recovery test.

## Verification (after reboot)

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

- [x] `apt update` clean (no `401`)
- [x] New kernel running
- [x] Proxmox 8.4.21
- [x] All 8 SOC systems came back up by themselves after the reboot

## Follow-ups

- [ ] Patch on a regular schedule (monthly, or on critical advisories) and log each run in the build log
- [ ] Forward Proxmox host logs to Splunk (step 2.3), so failed updates and auth events become visible instead of silent
- [ ] Plan the Proxmox 8 → 9 upgrade as its own change, with a backup and rollback plan

## Skills demonstrated

Vulnerability and patch management · Linux package management · hypervisor maintenance · change planning (scheduling, rollback awareness) · recovery testing

## Phase 1 complete ✅

All Phase 1 steps (1.1 – 1.7) are done. The SOC network is segmented and verified, the host is patched, and eight systems are built, baselined and ready for Phase 2: telemetry.
