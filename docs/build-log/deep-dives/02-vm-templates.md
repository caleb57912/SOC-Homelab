# Phase 1 · Step 1.2: VM and Container Templates

**Status:** Complete
**Goal:** Build reusable base images so every SOC system deploys the same way, in seconds, from one source.

## Summary

Instead of installing eight servers from ISOs by hand, I built one **Ubuntu 24.04 cloud-init template** (VM 9000) and downloaded a **Debian 12 LXC template**. Every SOC VM is cloned from VM 9000, and the lightweight services (Pi-hole, Velociraptor) run as containers from the Debian template.

| Template | Used for | Systems |
| --- | --- | --- |
| Ubuntu 24.04 cloud image → VM 9000 | Full VMs | SPLUNK01, WAZUH01, SENSOR01, SHUFFLE01, THEHIVE01, MISP01 |
| Debian 12 standard (LXC) | Containers | DNS01, VELO01 |

## Why templates instead of ISO installs

- **Consistency.** Every VM starts from an identical, known-good base. Configuration drift starts at zero.
- **Speed.** A clone deploys in seconds instead of a 15-minute installer.
- **Security.** Cloud images ship with no password login. Access is key-based SSH only, injected at first boot by cloud-init.
- **Rebuildability.** If a VM is compromised or broken, I destroy it and re-clone it rather than troubleshooting an unknown state. This is the same pattern as golden images in enterprise and cloud environments.

## Storage layout

| Storage | Type | Role in this build |
| --- | --- | --- |
| `isostore` | Directory (`/mnt/isostore`) | Holds the cloud image and LXC template (content: `iso,vztmpl`) |
| `local-lvm` | LVM-thin (~10.8 TiB) | All SOC VM and container disks |
| `local` | Directory (root disk, 77% full) | **Deliberately unused.** Filling the host's root disk can take down Proxmox itself. |

## Steps

### 1. Download the base images

```bash
pvesh create /nodes/pve/storage/isostore/download-url --content iso --filename noble-server-cloudimg-amd64.img --url https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
pveam update
pveam download isostore debian-12-standard_12.12-1_amd64.tar.zst
```

Proxmox verified the Debian template's checksum on download.

### 2. Create a dedicated SSH key (on my admin workstation)

```bash
ssh-keygen -t ed25519 -C "soc-homelab" -f ~/.ssh/soc_ed25519
cat ~/.ssh/soc_ed25519.pub | ssh root@<pve-ip> "cat > /root/soc.pub"
```

- **Ed25519:** modern, short keys, faster and stronger than RSA-2048.
- **A dedicated key for the SOC:** it's separate from my other keys, so it can be revoked without affecting anything else.
- **Passphrase-protected:** a stolen key file alone isn't enough to log in.
- **Only the public key leaves the workstation.** It was piped over SSH rather than pasted into the web console, which can wrap long lines and silently corrupt the key.

### 3. Build the template (VM 9000)

```bash
qm create 9000 --name ubuntu-2404-tpl --memory 2048 --cores 2 --cpu host --net0 virtio,bridge=vmbr0 --scsihw virtio-scsi-single --ostype l26 --agent 1 --serial0 socket --vga serial0
qm set 9000 --scsi0 local-lvm:0,import-from=/mnt/isostore/template/iso/noble-server-cloudimg-amd64.img --boot order=scsi0 --ide2 local-lvm:cloudinit
qm set 9000 --ciuser caleb --sshkeys /root/soc.pub --ipconfig0 ip=dhcp
qm template 9000
```

| Setting | Why |
| --- | --- |
| `--cpu host` | Passes through the Xeon's real CPU features. Splunk and Suricata benefit from them. |
| `virtio` NIC, `virtio-scsi-single` | Paravirtualized drivers give the best network and disk performance. |
| `--agent 1` | QEMU guest agent: Proxmox can see the VM's IP and shut it down cleanly. |
| `--serial0 socket --vga serial0` | Cloud images expect a serial console; without it, the console shows a blank screen. |
| `import-from=` | Imports the cloud image directly as the boot disk; no installer is needed. |
| `--ide2 ...:cloudinit` | The cloud-init drive that injects the user, SSH key and network settings at first boot. |
| `--ciuser` / `--sshkeys` | Non-root admin user, key-only login. |
| `qm template` | Converts the VM to a read-only template. Clones are linked to it and use little disk space. |

## Verification

```bash
qm config 9000
pveam list isostore
```

- `template: 1`
- `scsi0` is on `local-lvm` as `base-9000-disk-0` (about 3.5 GB)
- `ide2` is the cloud-init drive
- The Debian 12 template is listed in `isostore`

## Design decisions and pitfalls avoided

- **No VLAN tag on the template.** The SOC VLAN (30) doesn't exist on the network yet. A tag baked into the template would leave every clone without a network, so the tag is set per clone after the VLAN is built.
- **The template was never booted.** Booting would run cloud-init and stamp the image with one machine ID, and every clone would then share it, which breaks DHCP and logging.
- **The template disk stays small.** Each clone is resized to what its role needs (for example, Splunk to 100 GB) with `qm disk resize`.
- **Containers for light services.** Pi-hole and Velociraptor run as LXCs. That saves about 1.5 GB of RAM compared with VMs and keeps the whole stack under its 24 GB budget.

## Skills demonstrated

Proxmox VE administration · infrastructure-as-code-style golden images · cloud-init · SSH key management · storage planning · secure-by-default provisioning

## Next

**Step 1.3:** create the SOC network (VLAN 30) and its firewall zone on the UniFi UDR.
