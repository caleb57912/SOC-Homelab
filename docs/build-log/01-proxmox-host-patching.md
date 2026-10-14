# 1.1 · Proxmox Host Patching

**Result:** Hypervisor fully patched: kernel 6.8.12-9 → **6.8.12-43**, Proxmox 8.4.0 → **8.4.21**, 213 packages updated.

## Problem
The host had been up for **337 days** and **wasn't receiving updates at all**. It pointed at the paid enterprise repository without a subscription, so every update check failed with `401 Unauthorized`. The UI looked healthy; the package source was broken.

## What I did
- Switched to the official **no-subscription** repository on the same release (Proxmox 8 / Debian bookworm)
- Ran `apt full-upgrade`, which picked up OpenSSH, OpenSSL, the kernel, QEMU and LXC fixes
- Rebooted while on-site (the VPN runs on this host, so a failed boot would have cut off remote access)

## Key decisions
- **Stayed on Proxmox 8.** A major-version upgrade is its own planned change, not something to bundle with patching.
- **`full-upgrade`, not `upgrade`,** so new kernel dependencies weren't held back.
- **The reboot doubled as a recovery test:** all 8 SOC systems came back up by themselves.

## Verification
```
$ pveversion
pve-manager/8.4.21 (running kernel: 6.8.12-43-pve)
```

**Skills:** patch management · Linux package management · change planning

➡️ [Deep dive](deep-dives/01-proxmox-host-patching.md)
