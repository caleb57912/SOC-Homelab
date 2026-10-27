# Scripts

Scripts I use to build and run the SOC. Anything I'd otherwise type by hand more than once ends up here.

| Folder | Purpose |
| --- | --- |
| [`deployment/`](deployment) | Onboarding a system into the SOC: agents, log forwarding, config |
| [`maintenance/`](maintenance) | Routine upkeep: patching, config backups, publishing evidence |
| [`troubleshooting/`](troubleshooting) | Checks I run when data stops flowing or something looks wrong |

## Index

| Script | Runs on | What it does | Build step |
| --- | --- | --- | --- |
| [`deployment/network/catalyst-trunks.ios`](deployment/network/catalyst-trunks.ios) | Catalyst (paste into SSH) | Shuts the loop port, creates VLAN 30, sets the UDR and pve trunks to native 1 / allowed 1,30 with no DTP, turns off `ip routing` | [1.4](../00-START-HERE-Build-Log/04-catalyst-3750x-trunking.md) |
| [`deployment/network/catalyst-port-hardening.ios`](deployment/network/catalyst-port-hardening.ios) | Catalyst (paste into SSH) | Locks the admin PC port to access mode with portfast and BPDU guard, shuts unused copper, uplink and 10G ports | [2.7](../00-START-HERE-Build-Log/14-zeek-suricata.md) |
| [`deployment/network/catalyst-logging-ntp.ios`](deployment/network/catalyst-logging-ntp.ios) | Catalyst (paste into SSH) | UTC clock, NTP, syslog to splunk01, login and config-change logging with keys hidden | [2.3](../00-START-HERE-Build-Log/10-infrastructure-logs.md) |
| [`deployment/linux/install-splunk-enterprise.sh`](deployment/linux/install-splunk-enterprise.sh) | splunk01 (sudo) | Installs Splunk Enterprise, seeds the admin password from a prompt, disables THP, enables boot-start, creates the SOC indexes and opens 9997 | [2.1](../00-START-HERE-Build-Log/08-splunk-installation.md) |
| [`deployment/linux/setup-syslog-collector.sh`](deployment/linux/setup-syslog-collector.sh) | splunk01 (sudo) | rsyslog on 514 UDP/TCP writing one folder per sender, receive-time stamps for the UDR, and the Splunk monitor with the host transform disabled | [2.3](../00-START-HERE-Build-Log/10-infrastructure-logs.md) |
| [`deployment/linux/enable-syslog-forwarding.sh`](deployment/linux/enable-syslog-forwarding.sh) | Linux host (root) | Forwards all syslog to the collector over TCP with a disk queue and RFC 5424 timestamps | [2.3](../00-START-HERE-Build-Log/10-infrastructure-logs.md) |
| [`deployment/linux/install-universal-forwarder.sh`](deployment/linux/install-universal-forwarder.sh) | Linux host (sudo) | Installs the UF, points it at the deployment server and 9997, optionally adds the forwarder to an app group or a local monitor | [2.2](../00-START-HERE-Build-Log/09-pihole-dns.md), [2.5](../00-START-HERE-Build-Log/12-wazuh.md) |
| [`deployment/linux/install-wazuh-manager.sh`](deployment/linux/install-wazuh-manager.sh) | wazuh01 (sudo) | Installs and pins the Wazuh manager, switches it to manager-only (indexer off, index-status off), requires an enrollment password | [2.5](../00-START-HERE-Build-Log/12-wazuh.md) |
| [`deployment/windows/Install-SocEndpoint.ps1`](deployment/windows/Install-SocEndpoint.ps1) | Windows endpoint (admin PowerShell) | Installs or updates Sysmon (sysmon-modular config), enables script block logging and logon auditing, and with `-ForwarderMsi` installs the Splunk UF and enrolls it with the deployment server on splunk01, which pushes the inputs ([`siem/splunk/deployment-apps`](../siem/splunk/deployment-apps)); with `-WazuhManager` installs and enrolls the Wazuh agent (prompts for the enrollment password) | [2.4](../00-START-HERE-Build-Log/11-endpoint-telemetry.md) |
| [`troubleshooting/check-syslog-collector.sh`](troubleshooting/check-syslog-collector.sh) | splunk01 (sudo) | Shows whether rsyslog and Splunk are up, what's listening on 514, and the latest event from each sender | [2.3](../00-START-HERE-Build-Log/10-infrastructure-logs.md) |
| [`troubleshooting/Test-SocEndpoint.ps1`](troubleshooting/Test-SocEndpoint.ps1) | Windows endpoint (admin PowerShell) | Checks Sysmon, UF and Wazuh services, ports to splunk01 and wazuh01, deployed apps, Sysmon channel access (the errorCode=5 cause) and recent agent errors | [2.4](../00-START-HERE-Build-Log/11-endpoint-telemetry.md) |
| [`troubleshooting/check-wazuh-manager.sh`](troubleshooting/check-wazuh-manager.sh) | wazuh01 (sudo) | Verifies the manager-only settings, listening ports, enrolled agents, alerts.json and forwarder read access, and recent errors | [2.5](../00-START-HERE-Build-Log/12-wazuh.md) |
| [`troubleshooting/splunk-health-searches.md`](troubleshooting/splunk-health-searches.md) | Splunk search | Searches for missing forwarders, stale sources, syslog host naming and SCA scores | [2.3](../00-START-HERE-Build-Log/10-infrastructure-logs.md)–[2.5](../00-START-HERE-Build-Log/12-wazuh.md) |
| [`maintenance/redact-screenshots.py`](maintenance/redact-screenshots.py) | Any machine with Python, Pillow and Tesseract | OCRs screenshots and blacks out public IPs, MACs, IPv6, external domains and chosen keywords, plus manual boxes, before they go into `screenshots/` | Evidence for 1.1–2.5 |

The `.ios` files apply under a `reload in 10` timer. After checking the `show` output, run `reload cancel` and `write memory`.

Secrets never go in these scripts. Anything sensitive is prompted for or generated at run time.
