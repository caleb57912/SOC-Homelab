# 1.2 · VM and Container Templates

**Result:** A reusable **Ubuntu 24.04 cloud-init golden image** (VM 9000) plus a Debian 12 LXC template. Every SOC system deploys from these in seconds, identically.

## Why templates
- **Consistency:** every VM starts from the same known-good base
- **Speed:** clone in seconds instead of running an installer
- **Security:** no password login; key-only SSH injected at first boot
- **Rebuildability:** a broken or compromised VM gets destroyed and re-cloned, not repaired

## What I did
- Imported the official Ubuntu cloud image as the boot disk and attached a cloud-init drive
- Created a dedicated **Ed25519 SSH key** for the SOC (passphrase-protected; only the public key left the workstation)
- Converted VM 9000 into a read-only template

```bash
qm set 9000 --scsi0 local-lvm:0,import-from=<cloud-image> --ide2 local-lvm:cloudinit
qm set 9000 --ciuser caleb --sshkeys /root/soc.pub --ipconfig0 ip=dhcp
qm template 9000
```

## Key decisions
- **No VLAN tag in the template.** The tag is set per clone, so the template works on any network.
- **The template is never booted.** Booting would stamp one machine ID into every future clone.
- VM disks go on the large LVM-thin pool, **not** the nearly full root disk.

**Skills:** Proxmox · cloud-init · golden images · SSH key management

➡️ [Deep dive](deep-dives/02-vm-templates.md)
