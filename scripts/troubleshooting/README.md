# Troubleshooting

Checks I run when a data source goes quiet or something looks off.

| Script | Use when |
| --- | --- |
| [`splunk-health-searches.md`](splunk-health-searches.md) | Start here: find which host or source went quiet |
| [`check-syslog-collector.sh`](check-syslog-collector.sh) | A syslog source (UDR, switch, Proxmox) stops showing up in `index=network` |
| [`Test-SocEndpoint.ps1`](Test-SocEndpoint.ps1) | A Windows endpoint stops sending Sysmon, event logs or Wazuh alerts |
| [`check-wazuh-manager.sh`](check-wazuh-manager.sh) | `index=wazuh` goes quiet or an agent won't enroll |
| [`check-sensor.sh`](check-sensor.sh) | `index=zeek` or `index=suricata` goes quiet, or the sensor looks unhealthy |
| [`find-nonip-frames.sh`](find-nonip-frames.sh) | `SURICATA Ethertype unknown` alerts come back after a switch or network change |
| [`test-nids-pipeline.sh`](test-nids-pipeline.sh) | Proving Suricata detection end to end after any sensor change |
| [`check-misp.sh`](check-misp.sh) | The MISP web UI errors (HTTP 500), feeds stop updating, or after rotating a secret |
| [`test-misp-api.sh`](test-misp-api.sh) | misp42splunk searches fail or the API key changed |
