# Phase 2 · Step 2.1: Installing Splunk Enterprise (SIEM)

**Status:** Complete
**Host:** `splunk01`, 10.30.0.10 (Ubuntu 24.04, 4 vCPU / 6 GB RAM / 100 GB disk, VLAN 30)
**Version:** Splunk Enterprise 10.6.0.5
**Goal:** A running Splunk instance that starts at boot, has an index for each data category, is listening for forwarders, and can be reached from the admin workstation, ready to receive its first data source.

This writeup explains each command and the reasoning behind it, not just the steps.

---

## 1. What Splunk is and how it's laid out here

Splunk is a **SIEM** (Security Information and Event Management) platform. It collects machine data (logs, events, alerts), stores it in a searchable form, and lets analysts query, correlate, alert on and visualize it with SPL (Search Processing Language). In this SOC, Splunk is the **central place every log ends up**, and where triage, hunting and detections happen.

A production Splunk deployment separates its roles across many servers:

| Role | What it does | In this lab |
| --- | --- | --- |
| **Forwarder** | Agent on a source machine that ships logs to Splunk | Universal Forwarders on endpoints (Phase 2) |
| **Indexer** | Receives data, parses it, writes it to disk in indexes | `splunk01` |
| **Search head** | Web UI and search engine that queries the indexers | `splunk01` |
| **Deployment server** | Centrally manages forwarder configs | `splunk01` (later) |

At home-lab volume (a few hundred MB a day at most), **one all-in-one instance does every role**. The concepts are the same as in an enterprise deployment; it's just consolidated. Knowing which role does what still matters for interviews and real environments.

---

## 2. Download and install

```bash
ssh caleb@10.30.0.10
cd /tmp && wget -O splunk-10.6.0.5-86587d4e3b27-linux-amd64.deb "https://download.splunk.com/products/splunk/releases/10.6.0.5/linux/splunk-10.6.0.5-86587d4e3b27-linux-amd64.deb"
sudo dpkg -i /tmp/splunk-10.6.0.5-86587d4e3b27-linux-amd64.deb
rm /tmp/splunk-10.6.0.5-86587d4e3b27-linux-amd64.deb
```

### What each piece does

| Command | Explanation |
| --- | --- |
| `cd /tmp` | Downloads go in a scratch directory, not the home folder |
| `wget -O <file> "<url>"` | Downloads the installer. `-O` sets the output file name. The URL is quoted because it contains characters the shell could otherwise interpret. |
| `dpkg -i <file>.deb` | Installs a local Debian/Ubuntu package. Unlike `apt install`, `dpkg` doesn't fetch dependencies, which is fine here because Splunk bundles almost everything it needs. |
| `rm …deb` | The installer is 1.3 GB. Once installed it's no longer needed, and leaving it would waste disk on the SIEM. |

### Why the `.deb` package?

Splunk offers `.tgz`, `.rpm` and `.deb`. On Ubuntu, `.deb` registers Splunk with the system package manager, so `dpkg -l splunk` shows the installed version, upgrades are a single `dpkg -i`, and file ownership is tracked. Everything installs under **`/opt/splunk`** (called `$SPLUNK_HOME`).

### Output worth understanding

```
find: '/opt/splunk/lib/python3.7/site-packages': No such file or directory
complete
```

The install script looks for an old Python 3.7 directory that newer Splunk versions no longer ship. It's harmless. The line that matters is `complete`. **Lesson:** in a SOC, you'll constantly see error-looking output that isn't an error. Read the final status before reacting.

### Mistake made along the way: pasting multiple commands with `ssh`

The first attempt pasted `ssh …`, `wget …` and `dpkg …` as one block. `ssh` started an interactive session and took the first line, but the remaining lines were left in the **local** shell's input buffer, not sent to the server. Nothing was downloaded. **Fix:** connect first, wait for the remote prompt (`caleb@splunk01:~$`), then paste. Or run one-off remote commands with `ssh host 'command'`.

---

## 3. Creating the admin account securely: `user-seed.conf`

```bash
sudo tee /opt/splunk/etc/system/local/user-seed.conf >/dev/null <<'EOF'
[user_info]
USERNAME = admin
PASSWORD = <redacted>
EOF
```

### Why do it this way?

Splunk has no default admin password. On its **very first start**, it looks for `user-seed.conf` and creates the admin account from it. If the file is missing on first start, no admin is created and you'd have to reset the instance. So this file has to exist **before** Splunk ever runs.

Splunk **reads and then deletes** the file after first start, so the password doesn't stay on disk in plain text.

### The command, piece by piece

| Part | Explanation |
| --- | --- |
| `sudo tee <file>` | `tee` writes its input to a file. It's used instead of `sudo echo … > file` because in that form the `>` redirection is done by **your** unprivileged shell, not by sudo, so it fails with "Permission denied". `sudo tee` puts the privileged process on the writing side. |
| `>/dev/null` | `tee` also echoes what it writes to the screen. This discards that copy, which keeps the password off the terminal. |
| `<<'EOF' … EOF` | A **heredoc**: multi-line input fed to the command. Quoting `'EOF'` stops the shell from expanding `$` and backticks inside it, which matters if the password contains `$`. |
| `etc/system/local/` | Splunk's config layering: `default/` holds vendor settings (never edit), and `local/` holds your overrides (they win and survive upgrades). |

---

## 4. Running Splunk as a managed service

```bash
sudo /opt/splunk/bin/splunk enable boot-start -user splunk -systemd-managed 1 --accept-license --answer-yes --no-prompt
sudo systemctl start Splunkd
sudo systemctl status Splunkd --no-pager | head -5
```

| Flag | Why it's there |
| --- | --- |
| `enable boot-start` | Registers Splunk to start automatically at boot. A SIEM that's down after a reboot is a blind spot, and the Proxmox host was just rebooted for patching. |
| `-user splunk` | Runs Splunk as the unprivileged **`splunk`** account, **not root**. If Splunk (a large, network-facing application) were compromised, the attacker would get a limited user rather than full control of the machine. This is least privilege applied to a service. |
| `-systemd-managed 1` | Creates a proper **systemd unit** (`Splunkd.service`) instead of a legacy init script. systemd then handles start, stop, restart-on-failure, resource limits and logging (`journalctl -u Splunkd`). |
| `--accept-license --answer-yes --no-prompt` | Answers the interactive license and confirmation prompts, so the setup can be scripted and repeated. |
| `systemctl start Splunkd` | Starts it through systemd. From now on, **always** manage Splunk with `systemctl`, not `splunk start`, so systemd knows the true state of the service. |
| `--no-pager \| head -5` | Prints the status without opening a pager and shows only the top lines, where the `Active:` state is. |

### What the first start printed

```
This appears to be your first time running this version of Splunk.
writing RSA key
Systemd unit file installed at /etc/systemd/system/Splunkd.service.
Configured as systemd managed service.
● Splunkd.service ... Active: active (running)
```

- **"writing RSA key"**: Splunk generated its own TLS certificates for the web UI and the management port.
- **`Loaded: … enabled`**: it will start at boot.
- **`Active: active (running)`**: running now.
- **`ExecStartPost … chown … cgroup`**: Splunk gives the `splunk` user ownership of its cgroup, which lets it manage its own resource controls without root.

---

## 5. Disabling Transparent Huge Pages (THP)

```bash
sudo tee /etc/systemd/system/disable-thp.service >/dev/null <<'EOF'
[Unit]
Description=Disable Transparent Huge Pages
Before=Splunkd.service
[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo never > /sys/kernel/mm/transparent_hugepage/enabled; echo never > /sys/kernel/mm/transparent_hugepage/defrag'
[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload && sudo systemctl enable --now disable-thp && sudo systemctl restart Splunkd
cat /sys/kernel/mm/transparent_hugepage/enabled
```

### What THP is and why it's turned off

Linux normally manages memory in 4 KB pages. **Transparent Huge Pages** automatically groups them into 2 MB pages, which helps some workloads. For applications like Splunk, which make many small, scattered memory allocations, THP causes **latency spikes and higher memory use** as the kernel compacts and defragments memory in the background. Splunk's documentation recommends disabling it, and Splunk logs a health warning if it's enabled.

### Why a systemd unit instead of a one-line command?

Writing `never` to `/sys/kernel/mm/...` takes effect immediately but is **lost on reboot**, because `/sys` is a virtual filesystem generated at boot. A tiny systemd service reapplies the setting on every boot.

| Unit line | Meaning |
| --- | --- |
| `Before=Splunkd.service` | Ordering: run this before Splunk starts, so Splunk never starts with THP on |
| `Type=oneshot` | Run once and exit; it's a setting, not a long-running daemon |
| `WantedBy=multi-user.target` | Run during normal boot |
| `daemon-reload` | Tells systemd to read the new unit file |
| `enable --now` | Enable at boot **and** start it right away |
| `restart Splunkd` | Splunk picks up the new memory behavior |

### Verification

```
always madvise [never]
```

The value in **brackets** is the active one. `[never]` means THP is off.

---

## 6. Creating the indexes

```bash
for i in os network dns wazuh intel; do sudo -u splunk /opt/splunk/bin/splunk add index $i -auth admin:'<redacted>'; done
```

### What an index is

An index is where Splunk stores events on disk. Think of it as a **database table plus a storage policy**. Every search names the index(es) it reads (`index=dns …`). Without custom indexes, everything lands in `main`, which is the classic beginner mistake.

### Why separate indexes?

| Reason | Example |
| --- | --- |
| **Search speed** | `index=dns` only scans DNS data, not every log ever collected |
| **Retention** | DNS logs are high-volume and short-lived, while alerts may need to be kept longer. Retention is set **per index**. |
| **Access control** | Roles can be granted per index (for example, an analyst can see `wazuh` but not `intel`) |
| **Clean detections** | Detection logic targets known data sources, not a mixed `main` |

### This SOC's index design

| Index | Will hold | Source (step) |
| --- | --- | --- |
| `os` | Windows and Linux system and security logs, Sysmon | Universal Forwarders (2.4) |
| `network` | UDR firewall/IDS, Catalyst syslog, Zeek, Suricata, Proxmox, VPN | rsyslog, sensor (2.3, 2.7) |
| `dns` | Every DNS query from every device | Pi-hole (2.2) |
| `wazuh` | Wazuh alerts: FIM, vulnerabilities, rule hits | Wazuh manager (2.5) |
| `intel` | Threat-intel IOCs and matches | MISP (2.6) |

### The command, piece by piece

| Part | Explanation |
| --- | --- |
| `for i in …; do …; done` | A shell loop: runs the command once per index name, with `$i` replaced each time. One line instead of five. |
| `sudo -u splunk` | Runs the CLI **as the `splunk` user**. Running it as root can create files under `/opt/splunk` owned by root, and then the service (running as `splunk`) can't read them. That's a common cause of mysterious failures. |
| `splunk add index $i` | Creates the index under the default storage path (`/opt/splunk/var/lib/splunk/<index>`) |
| `-auth admin:'…'` | Logs in to the Splunk management API for this command. Single quotes keep special characters in the password from being interpreted by the shell. |

---

## 7. Opening the receiving port for forwarders

```bash
sudo -u splunk /opt/splunk/bin/splunk enable listen 9997
```

**9997** is Splunk's conventional port for **Splunk-to-Splunk (S2S)** traffic, the protocol Universal Forwarders use to send data. Without a listener, forwarders have nowhere to deliver.

This command didn't need `-auth`: the previous command's login was still cached as a session token, so the CLI reused it.

---

## 8. Verifying the listening ports

```bash
sudo ss -tlnp | grep -E '8000|8089|9997'
```

| `ss` flag | Meaning |
| --- | --- |
| `-t` | TCP sockets |
| `-l` | Only sockets in the **listening** state |
| `-n` | Show numeric ports, not service names |
| `-p` | Show which process owns each socket (needs `sudo`) |

```
LISTEN 0.0.0.0:9997  users:(("splunkd",...))
LISTEN 0.0.0.0:8089  users:(("splunkd",...))
LISTEN 0.0.0.0:8000  users:(("splunkd",...))
```

| Port | Purpose | Who connects |
| --- | --- | --- |
| **8000** | Splunk Web (the UI) | Analysts' browsers |
| **8089** | Management REST API | The CLI, apps, the deployment server, automation (Shuffle later) |
| **9997** | Data receiving (S2S) | Universal Forwarders |

`0.0.0.0` means the port listens on every network interface. That's acceptable here because the **UDR zone firewall** decides who can reach VLAN 30 (step 1.3): only the Internal network can start connections in. Network-level control in front of the application is defense in depth.

---

## 9. Verification in the web UI

From the admin workstation: **http://10.30.0.10:8000**

- [x] Login as `admin` works
- [x] **Settings → Indexes** lists `os`, `network`, `dns`, `wazuh`, `intel`
- [x] **Settings → Forwarding and receiving** shows receiving on **9997**

---

## 10. Warnings seen, and why they were acceptable for now

```
WARNING: Server Certificate Hostname Validation is disabled.
Please see server.conf/[sslConfig]/cliVerifyServerName for details.
```

The CLI talks to Splunk's management port (8089) over TLS, but it doesn't check that the certificate matches the hostname, because Splunk ships with **self-signed certificates**. Within a single host this is low risk. **Hardening backlog:** replace the default certificates with ones from a private CA and enable hostname validation, especially before forwarders send data over the network.

The web UI is also served over plain **HTTP** on 8000 for now. **Hardening backlog:** enable HTTPS on Splunk Web.

---

## 11. Security lesson: credential exposure

During this step the Splunk admin password was exposed in two places:

1. **Shell history.** `-auth admin:'password'` is saved in `~/.bash_history` in plain text. Anyone who later gets a shell on `splunk01` could read it.
2. **Pasted terminal output.** Command output containing the password was copied into a chat or ticket.

**Response:** treat the password as compromised and rotate it:

```bash
history -c
sudo -u splunk /opt/splunk/bin/splunk edit user admin -password '<new>' -auth admin:'<old>'
history -c
```

**Better practice going forward:**

- Run `splunk login` once (it prompts interactively) instead of putting `-auth` on the command line.
- Redact secrets before sharing any output: tickets, chat, screenshots, Git commits.

This is a real-world pattern. Credentials leaking through **logs, shell history, tickets and screenshots** is one of the most common ways attackers find valid passwords. In a SOC, this incident would get a ticket: a credential found in a ticketing system, rotated, root cause = CLI usage habit.

---

## 12. Licensing note

A new install runs on a **60-day Enterprise trial**. When it ends, Splunk falls back to **Splunk Free**, which keeps searching and indexing (up to 500 MB/day) but **removes alerting, scheduled searches and authentication**, which are core to a SOC.

**Plan:** before day 60, apply a **Splunk developer license** (free through Splunk's developer program; check the current terms when applying). Reminder set.

---

## Summary of what now exists

| Item | State |
| --- | --- |
| Splunk Enterprise 10.6.0.5 | Installed at `/opt/splunk` |
| Service | `Splunkd.service`, systemd-managed, enabled at boot, runs as `splunk` |
| THP | Disabled persistently (`disable-thp.service`) |
| Indexes | `os`, `network`, `dns`, `wazuh`, `intel` |
| Ports | 8000 (web), 8089 (management), 9997 (receiving) |
| Admin | `admin`, password rotated after exposure |

## Hardening backlog

- [ ] Custom TLS certificates and `cliVerifyServerName`
- [ ] HTTPS on Splunk Web
- [ ] Apply a developer license before the trial ends
- [ ] Per-index retention (`frozenTimePeriodInSecs`), plus cold storage on the 36 TB array
- [ ] Non-admin analyst account for daily use (least privilege)
- [ ] Narrow the UDR Internal → SOC rule to the specific ports (8000, 8089, 9997)

## Skills demonstrated

SIEM deployment · Splunk architecture (forwarder / indexer / search head) · Linux package management · systemd service design · least-privilege service accounts · OS tuning for workloads (THP) · index design and data modeling · port and socket verification · credential hygiene and incident response to exposure

## Next

**Step 2.2:** DNS01 (Pi-hole), the first data source, sending every DNS query on the network to `index=dns`.
