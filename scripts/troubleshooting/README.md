# Troubleshooting

Checks I run when a data source goes quiet or something looks off.

| Script | Use when |
| --- | --- |
| [`splunk-health-searches.md`](splunk-health-searches.md) | Start here: find which host or source went quiet |
| [`check-syslog-collector.sh`](check-syslog-collector.sh) | A syslog source (UDR, switch, Proxmox) stops showing up in `index=network` |
| [`Test-SocEndpoint.ps1`](Test-SocEndpoint.ps1) | A Windows endpoint stops sending Sysmon, event logs or Wazuh alerts |
| [`check-wazuh-manager.sh`](check-wazuh-manager.sh) | `index=wazuh` goes quiet or an agent won't enroll |
