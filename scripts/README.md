# Scripts

Scripts I use to build and run the SOC. Anything I'd otherwise type by hand more than once ends up here.

| Folder | Purpose |
| --- | --- |
| [`deployment/`](deployment) | Onboarding a system into the SOC: agents, log forwarding, config |
| [`maintenance/`](maintenance) | Routine upkeep: patching, config backups, health checks |
| [`troubleshooting/`](troubleshooting) | Checks I run when data stops flowing or something looks wrong |

## Index

| Script | Runs on | What it does | Build step |
| --- | --- | --- | --- |
| [`deployment/windows/Install-SocEndpoint.ps1`](deployment/windows/Install-SocEndpoint.ps1) | Windows endpoint (admin PowerShell) | Installs or updates Sysmon (sysmon-modular config), enables script block logging and logon auditing, and with `-ForwarderMsi` installs the Splunk UF and enrolls it with the deployment server on splunk01, which pushes the inputs ([`siem/splunk/deployment-apps`](../siem/splunk/deployment-apps)); with `-WazuhManager` installs and enrolls the Wazuh agent (prompts for the enrollment password) | [2.4](../00-START-HERE-Build-Log/) |
| [`deployment/linux/enable-syslog-forwarding.sh`](deployment/linux/enable-syslog-forwarding.sh) | Linux host (root) | Forwards all syslog to the collector over TCP with a disk queue and RFC 5424 timestamps | [2.3](../00-START-HERE-Build-Log/10-infrastructure-logs.md) |
| [`troubleshooting/check-syslog-collector.sh`](troubleshooting/check-syslog-collector.sh) | splunk01 (sudo) | Shows whether rsyslog and Splunk are up, what's listening on 514, and the latest event from each sender | [2.3](../00-START-HERE-Build-Log/10-infrastructure-logs.md) |

Secrets never go in these scripts. Anything sensitive is passed in at run time.
