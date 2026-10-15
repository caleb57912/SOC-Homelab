# 2.2 · Pi-hole DNS Sinkhole + DNS Logging

**Result:** Every DNS query on the Main and IoT networks now goes through Pi-hole on `dns01`, gets filtered against ~72k known-bad domains, and lands in Splunk (`index=dns`) within seconds.

## What was built
- **Pi-hole v6** in an unprivileged LXC on the SOC VLAN (10.30.0.53), upstream **Quad9** (malware-filtering DNS)
- **UDR DHCP** hands out Pi-hole as the DNS server for Main and IoT
- **Splunk Universal Forwarder** on `dns01` ships `pihole.log` to Splunk over 9997, under a dedicated non-root user

```
Client → Pi-hole (10.30.0.53) → Quad9
              │
              └─ pihole.log → Universal Forwarder → splunk01:9997 → index=dns
```

## Problems found and fixed
| Problem | Root cause | Fix |
| --- | --- | --- |
| Pi-hole received **zero** queries | The UDR's Content Filter (ad block) was **intercepting all port 53 traffic** before it reached Pi-hole | Removed the content filter. Pi-hole is now the single DNS control point |
| Workstation bypassed Pi-hole | A **static third-party DNS** setting on the NIC overrode DHCP | Reset the adapter to DHCP-assigned DNS |
| Pi-hole ignored other subnets | Default listening mode only answers the local subnet | `dns.listeningMode ALL`, safe because the UDR firewall controls who can reach it |
| **IoT could reach the whole SOC VLAN** | IoT sits in the Internal zone, so the broad "Internal → SOC" rule covered it too | Narrowed that rule to the Main network and added an **IoT → 10.30.0.53:53 only** rule |

## Key decisions
- **DNS as a sensor:** query logging on, privacy level 0. Every lookup is attributed to a client IP, which makes DNS one of the best-value log sources in the SOC
- **Least privilege:** the forwarder runs as `splunkfwd` and only joins the `pihole` group to read the log
- **Defense in depth:** Pi-hole blocklists plus Quad9's threat-intel filtering upstream

## Verification
- [x] Blocked domains return `0.0.0.0`; allowed domains resolve
- [x] Queries from Main and IoT clients both appear in the Pi-hole query log
- [x] `index=dns sourcetype=pihole:dnsmasq` returns live events from `dns01`

## Backlog
TLS between forwarder and indexer · detection for DNS bypass (port 53/853 to anything but Pi-hole) · filter `.localdomain` noise · non-root admin user in the LXC

**Skills:** DNS security · log onboarding · Splunk Universal Forwarder · firewall troubleshooting · least privilege · finding and closing a segmentation gap

➡️ [Deep dive](deep-dives/09-pihole-dns.md)
