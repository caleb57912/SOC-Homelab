# Maintenance

Routine upkeep scripts.

| Script | Use when |
| --- | --- |
| [`redact-screenshots.py`](redact-screenshots.py) | Before adding screenshots to the repo. `pip install pillow pytesseract` plus the Tesseract binary. Run `python redact-screenshots.py <in> <out> [--boxes boxes.json] [--keyword word]`, then check every output by eye. |
| [`lxc-copy.sh`](lxc-copy.sh) | Moving a file into or out of an LXC on pve: `lxc-copy.sh push\|pull <ctid> <src> <dst> [perms]`, hash-checked |
| [`scale-shuffle-app-services.sh`](scale-shuffle-app-services.sh) | After Shuffle restarts or app updates, when app services come back at 3 copies |
| [`triage-pslist-export.py`](triage-pslist-export.py) | After a Velociraptor process collection: `python triage-pslist-export.py <export.json>`. Keep exports out of the repo |

Planned: Proxmox patch run with logging, Catalyst config backup (secrets scrubbed), SOC health check.
