# Deployment

Scripts that onboard a system into the SOC.

| Script | Target |
| --- | --- |
| [`windows/Install-SocEndpoint.ps1`](windows/Install-SocEndpoint.ps1) | Windows endpoints: Sysmon, script block logging, logon auditing, Splunk Universal Forwarder |
| [`linux/enable-syslog-forwarding.sh`](linux/enable-syslog-forwarding.sh) | Linux hosts: syslog forwarding to splunk01 |
