# Deployment

Scripts that onboard a system into the SOC.

| Script | Target |
| --- | --- |
| [`network/catalyst-trunks.ios`](network/catalyst-trunks.ios) | Catalyst: VLAN 30 and the UDR/pve trunks |
| [`network/catalyst-port-hardening.ios`](network/catalyst-port-hardening.ios) | Catalyst: access port hardening and unused port shutdown |
| [`network/catalyst-span.ios`](network/catalyst-span.ios) | Catalyst: SPAN to the sensor, CDP off on edge ports |
| [`network/catalyst-logging-ntp.ios`](network/catalyst-logging-ntp.ios) | Catalyst: NTP and syslog to splunk01 |
| [`linux/install-splunk-enterprise.sh`](linux/install-splunk-enterprise.sh) | splunk01: Splunk Enterprise, indexes, receiving |
| [`linux/setup-syslog-collector.sh`](linux/setup-syslog-collector.sh) | splunk01: rsyslog collector and Splunk monitor |
| [`linux/enable-syslog-forwarding.sh`](linux/enable-syslog-forwarding.sh) | Linux hosts: syslog forwarding to splunk01 |
| [`linux/install-universal-forwarder.sh`](linux/install-universal-forwarder.sh) | Linux hosts: Splunk Universal Forwarder |
| [`linux/install-wazuh-manager.sh`](linux/install-wazuh-manager.sh) | wazuh01: manager-only Wazuh |
| [`linux/add-swapfile.sh`](linux/add-swapfile.sh) | Cloud-init VMs: swapfile before heavy installs |
| [`linux/setup-span-bridge.sh`](linux/setup-span-bridge.sh) | pve: SPAN capture bridge to sensor01 |
| [`linux/setup-sensor-capture-nic.sh`](linux/setup-sensor-capture-nic.sh) | sensor01: no-IP capture NIC, offloads off |
| [`linux/install-zeek.sh`](linux/install-zeek.sh) | sensor01: Zeek |
| [`linux/install-suricata.sh`](linux/install-suricata.sh) | sensor01: Suricata, ET Open, test rule, daily updates |
| [`linux/configure-sensor-ingest.sh`](linux/configure-sensor-ingest.sh) | splunk01: indexes, parsing, alert-only filter, deployment app for the sensor |
| [`linux/install-misp.sh`](linux/install-misp.sh) | misp01: MISP install and tuning |
| [`linux/set-misp-redis-password.sh`](linux/set-misp-redis-password.sh) | misp01: Redis password rotation across every consumer |
| [`linux/install-thehive.sh`](linux/install-thehive.sh) | thehive01: Java, Cassandra, Elasticsearch, TheHive |
| [`linux/install-shuffle.sh`](linux/install-shuffle.sh) | shuffle01: Docker and a pinned, locked-down Shuffle |
| [`linux/install-velociraptor-server.sh`](linux/install-velociraptor-server.sh) | velo01: verified Velociraptor server as a systemd package |
| [`linux/build-velociraptor-msi.sh`](linux/build-velociraptor-msi.sh) | velo01: verified, repacked Windows client MSI |
| [`windows/Install-SocEndpoint.ps1`](windows/Install-SocEndpoint.ps1) | Windows endpoints: Sysmon, script block logging, logon auditing, Splunk UF, Wazuh agent |
| [`windows/Install-VelociraptorClient.ps1`](windows/Install-VelociraptorClient.ps1) | Windows endpoints: Velociraptor client, hash-checked |
