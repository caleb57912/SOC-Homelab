# Phase 2 · Step 2.2: Pi-hole DNS Sinkhole and DNS Logging (Deep Dive)

**Status:** Complete
**Goal:** Make one SOC-controlled server the DNS resolver for the whole network, block known-bad domains, and send every query to Splunk.

## Why DNS first

Almost every connection starts with a DNS lookup: malware calling home, phishing links, data exfiltration over DNS. A resolver that logs every query and the client that asked gives the SOC a network-wide view, without installing an agent on any endpoint. It's cheap to run (512 MB LXC) and is one of the highest-value log sources a SOC can have.

## Part A: Install Pi-hole on dns01

`dns01` is the unprivileged Debian 12 LXC built in step 1.7 (10.30.0.53).

```bash
ssh root@10.30.0.53
apt update && apt install -y curl
curl -sSL https://install.pi-hole.net | bash
```

Installed versions: **Core 6.4.3 / FTL 6.7.1 / Web 6.6**.

| Installer choice | Value | Why |
| --- | --- | --- |
| Interface | `eth0` | The container's only NIC |
| Upstream DNS | Quad9 (9.9.9.9, 149.112.112.112) | Quad9 blocks domains from its own threat-intel feeds, so it's a second filtering layer behind Pi-hole |
| Blocklist | Default (~72,500 domains) | Starting point; tune later |
| Query logging | On | The whole point: DNS as a sensor |
| Privacy level | 0 (show everything) | The SOC needs the domain **and** the client IP |

The installer prints a random web password. It was changed straight away (`pihole setpassword`). The original appeared in a screenshot, so the change also counted as cleanup.

### Listening mode

By default Pi-hole v6 only answers clients on its own subnet (10.30.0.0/24). Main (192.168.1.0/24) and IoT (192.168.2.0/24) clients arrive through the UDR from other subnets and were being ignored.

```bash
pihole-FTL --config dns.listeningMode ALL
pihole-FTL --config dns.queryLogging      # true
pihole-FTL --config misc.privacylevel     # 0
```

`ALL` would be risky on an internet-facing box. Here it's fine, because the UDR zone firewall decides who can reach port 53 on 10.30.0.53 (see Part D).

### Point the network at Pi-hole

UniFi → Networks → **Default** and **IOT** → DHCP DNS Server → `10.30.0.53`. Clients pick it up on their next lease renewal (`ipconfig /renew` to speed it up).

## Part B: Troubleshooting (Pi-hole saw nothing)

`nslookup` from the workstation, sent straight to Pi-hole, got answers, but **Pi-hole's query log stayed empty** and `pihole -t` showed nothing.

### Step 1: is the traffic reaching the container?

```bash
tcpdump -ni eth0 port 53
```

Nothing. The queries never reached `dns01`, yet the client still got answers. **Something between the client and Pi-hole was answering on Pi-hole's behalf.**

### Step 2: root cause, the UDR's DNS interception

UniFi → CyberSecure → **Content Filter** had an "Ad Block" filter applied to the Default network. To filter DNS, the UDR **transparently intercepts port 53** and answers queries itself, whatever server the client asked for.

Fix: deleted the content filter. Pi-hole now does that job, with logs the SOC controls. Straight after, `tcpdump` showed the queries arriving and the query log filled up.

**Lesson:** "managed" security features on edge devices can quietly redirect traffic. When a packet capture shows nothing arriving but the client still gets answers, look for something in the middle.

### Step 3: the workstation was bypassing everything

`ipconfig /all` showed the workstation's NIC using a **statically configured third-party DNS provider**, not the DHCP-assigned server. That traffic went straight to the internet and skipped Pi-hole completely.

```powershell
# elevated PowerShell
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ResetServerAddresses
ipconfig /flushdns
nslookup pi.hole
```

The first attempt failed with a CIM access error because the window wasn't elevated. It worked in an admin window.

**Lesson:** a sinkhole only covers clients that use it. Static DNS on a host, DNS-over-HTTPS in a browser, or a hard-coded resolver in an IoT device can all get around it. That's why "DNS bypass detection" is on the backlog (see Next steps).

## Part C: Verification

| Test | Result |
| --- | --- |
| `nslookup google.com 10.30.0.53` | Resolves |
| `nslookup <known-ad-domain> 10.30.0.53` | `0.0.0.0` (blocked) |
| Query log shows Main clients (192.168.1.x) | ✅ |
| Query log shows IoT clients (192.168.2.x) | ✅ |
| `tcpdump -ni eth0 port 53` on dns01 | Live queries arriving |

## Part D: Fixing an IoT segmentation gap

Adding IoT as a DNS client meant checking which UDR rule lets IoT reach the SOC. That turned up a real finding:

- The IoT network sits in the **Internal** zone (with "Isolate Network" ticked).
- The existing **"Internal SOC Allow"** policy had source = Internal zone, destination = SOC, any port.
- So **every IoT device could reach every port on every SOC system**: Splunk, the Wazuh manager, MISP, all of it. IoT devices are the least trusted things on the network, and the SOC is the most sensitive.

| Policy | Before | After |
| --- | --- | --- |
| Internal SOC Allow | Source: Internal zone (Main **and IoT**) → SOC, any | Source: **Network = Default only** → SOC |
| IoT DNS to Pi-hole (new) | — | Source: Network = IOT → **10.30.0.53, TCP/UDP 53 only** |

Both networks still resolve through Pi-hole, but IoT can no longer touch anything else in the SOC.

**Lesson:** zone-based rules apply to *every* network in the zone. Adding a network to a zone silently gives it all of that zone's permissions, so check the source scope of each rule.

## Part E: Ship the logs to Splunk

### Install the Universal Forwarder

The UF (`.deb`, amd64) was downloaded from splunk.com and installed on `dns01`:

```bash
dpkg -i splunkforwarder-*.deb
/opt/splunkforwarder/bin/splunk enable boot-start -systemd-managed 1 -user splunkfwd --accept-license
```

- **`-user splunkfwd`:** the forwarder runs as its own unprivileged account, never root.
- **systemd-managed:** runs as `SplunkForwarder.service` and starts at boot.

### Give it read access, and nothing more

Pi-hole's log (`/var/log/pihole/pihole.log`) is owned by the `pihole` group. Rather than loosening file permissions or running the UF as root:

```bash
usermod -aG pihole splunkfwd
systemctl restart SplunkForwarder
```

### Point it at Splunk and pick the file

```bash
sudo -u splunkfwd /opt/splunkforwarder/bin/splunk add forward-server 10.30.0.10:9997
sudo -u splunkfwd /opt/splunkforwarder/bin/splunk add monitor /var/log/pihole/pihole.log -index dns -sourcetype pihole:dnsmasq
sudo -u splunkfwd /opt/splunkforwarder/bin/splunk list forward-server   # Active: 10.30.0.10:9997
```

| Setting | Value | Why |
| --- | --- | --- |
| Index | `dns` | The dedicated index from step 2.1: own retention, faster searches |
| Sourcetype | `pihole:dnsmasq` | `pihole.log` uses dnsmasq's format; a specific sourcetype lets field extractions target it |
| Transport | TCP 9997, SOC VLAN only | Never leaves the SOC segment |

### A false alarm worth noting

The first search in Splunk came back empty. The timestamps explained it: the search ran at 07:51 and the forwarder connected at 07:53. **Check the timeline before you troubleshoot.** A minute later the events were there.

### Verify in Splunk

```
index=dns sourcetype=pihole:dnsmasq | head 20
```

Thousands of events from `host=dns01` within minutes. Each query shows up as a set of lines: `query[A] <domain> from <client>`, `forwarded <domain> to 9.9.9.9`, then the reply (or `gravity blocked`).

A first analyst search, top domains on the network:

```
index=dns sourcetype=pihole:dnsmasq "query["
| rex "query\[(?<qtype>\w+)\] (?<domain>\S+) from (?<src_ip>\S+)"
| stats count by domain
| sort - count
| head 20
```

## A note on container memory

`free -m` on `dns01` showed only ~88 MB **free**, but ~440 MB **available**. Linux uses spare RAM for the page cache and gives it back on demand, so "available" is the number that matters. No resize was needed.

## Security notes

- The forwarder uses Splunk's **default TLS certificates** and doesn't verify the server (`sslVerifyServerCert = false`). Acceptable inside an isolated VLAN for now; it's on the backlog.
- Query logs contain household browsing activity. They stay inside the SOC, and published screenshots are redacted.

## Next steps / backlog

- [ ] **Detection:** alert on DNS (53/853) or known DoH endpoints from any client to anything but 10.30.0.53, using UDR firewall logs (step 2.3)
- [ ] Field extractions (`props.conf`/`transforms.conf`) so `domain`, `src_ip` and `qtype` exist without `rex`
- [ ] Filter `.localdomain` / reverse-lookup noise
- [ ] TLS with custom certificates between the forwarder and the indexer
- [ ] Non-root admin user in the LXC
- [ ] Blocklist tuning and threat-intel feeds (from MISP in step 2.6)

## Skills demonstrated

DNS sinkholing · packet capture troubleshooting · finding transparent DNS interception · endpoint DNS bypass · zone firewall review and fixing an IoT → SOC segmentation gap · Splunk Universal Forwarder deployment · least-privilege file access · log onboarding (index/sourcetype design) · SPL with `rex` and `stats`
