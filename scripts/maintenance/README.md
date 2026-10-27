# Maintenance

Routine upkeep scripts.

| Script | Use when |
| --- | --- |
| [`redact-screenshots.py`](redact-screenshots.py) | Before adding screenshots to the repo. `pip install pillow pytesseract` plus the Tesseract binary. Run `python redact-screenshots.py <in> <out> [--boxes boxes.json] [--keyword word]`, then check every output by eye. |

Planned: Proxmox patch run with logging, Catalyst config backup (secrets scrubbed), SOC health check.
