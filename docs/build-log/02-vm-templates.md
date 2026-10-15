# 1.2 · VM and Container Templates

**Result:** An Ubuntu 24.04 cloud-init golden image (VM 9000) and a Debian 12 LXC template. Every SOC system deploys from one of these, identically, in seconds.

## Why I used templates
I didn't want to hand-install eight servers from ISOs and end up with eight slightly different machines. With a golden image, every system starts from the same known-good base, deploys in seconds, and has no password login: cloud-init injects my SSH key at first boot. If a system breaks or gets compromised, I destroy it and re-clone it rather than repair it.

## What I did
- Imported the official Ubuntu cloud image as the boot disk and attached a cloud-init drive
- Created a dedicated, passphrase-protected Ed25519 key for the SOC
- Converted VM 9000 into a template and downloaded the Debian 12 LXC template

## Decisions
- **No VLAN tag in the template.** I set the tag per clone so the template works on any network.
- **I never boot the template.** Booting would stamp one machine ID into every future clone.
- **VM disks go on the 10.8 TiB LVM-thin pool,** not the host's root disk, which was already 77% full.

**Skills:** Proxmox · cloud-init · golden images · SSH key management

➡️ [Deep dive](deep-dives/02-vm-templates.md)
