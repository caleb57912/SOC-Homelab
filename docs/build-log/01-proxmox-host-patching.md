# 1.1 · Proxmox Host Patching

**Result:** Hypervisor fully patched: kernel 6.8.12-9 → **6.8.12-43**, Proxmox 8.4.0 → **8.4.21**, 213 packages updated.

## What I found
Before putting any security tooling on the host, I checked its patch state. It had been up for **337 days** and **hadn't installed an update in months**. It was pointed at the paid enterprise repository with no subscription, so every update check failed with `401 Unauthorized`. The UI looked healthy; the package source was broken.

## What I did
- Switched to the official no-subscription repository on the same release (Proxmox 8 / Debian bookworm)
- Ran a full upgrade, which brought in OpenSSH, OpenSSL, kernel, QEMU and LXC fixes
- Rebooted while I was home, since my VPN VM ran on this host at the time and a failed boot would have locked me out

## Decisions
- **Stayed on Proxmox 8.** A major-version upgrade is its own planned change, and I didn't want it bundled with patching.
- **Used the reboot as a recovery test.** All 8 SOC systems came back by themselves.

```
$ pveversion
pve-manager/8.4.21 (running kernel: 6.8.12-43-pve)
```

**Skills:** patch management · Linux package management · change planning

➡️ [Deep dive](deep-dives/01-proxmox-host-patching.md)
