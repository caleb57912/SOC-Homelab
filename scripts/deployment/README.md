# Deployment

Scripts that onboard a system into the SOC.

| Script | Target |
| --- | --- |
| [`network/catalyst-trunks.ios`](network/catalyst-trunks.ios) | Catalyst: VLAN 30 and the UDR/pve trunks |
| [`network/catalyst-port-hardening.ios`](network/catalyst-port-hardening.ios) | Catalyst: access port hardening and unused port shutdown |
| [`network/catalyst-logging-ntp.ios`](network/catalyst-logging-ntp.ios) | Catalyst: NTP and syslog to splunk01 |
| [`linux/install-splunk-enterprise.sh`](linux/install-splunk-enterprise.sh) | splunk01: Splunk Enterprise, indexes, receiving |
| [`linux/setup-syslog-collector.sh`](linux/setup-syslog-collector.sh) | splunk01: rsyslog collector and Splunk monitor |
| [`linux/enable-syslog-forwarding.sh`](linux/enable-syslog-forwarding.sh) | Linux hosts: syslog forwarding to splunk01 |
| [`linux/install-universal-forwarder.sh`](linux/install-universal-forwarder.sh) | Linux hosts: Splunk Universal Forwarder |
| [`linux/install-wazuh-manager.sh`](linux/install-wazuh-manager.sh) | wazuh01: manager-only Wazuh |
| [`windows/Install-SocEndpoint.ps1`](windows/Install-SocEndpoint.ps1) | Windows endpoints: Sysmon, script block logging, logon auditing, Splunk UF, Wazuh agent |
