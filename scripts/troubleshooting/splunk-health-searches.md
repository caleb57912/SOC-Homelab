# Splunk health searches

Searches I run when data looks missing. Set the time picker to a fixed range like **Last 15 minutes**, not real time.

## Is every forwarder checking in?

```
index=_internal earliest=-15m | stats count by host
```

A host missing here has a forwarder or network problem, not a data input problem.

## Latest event per index and host

```
| tstats latest(_time) as last count where index=* by index host
| eval minutes_ago=round((now()-last)/60,1)
| convert ctime(last)
| sort - minutes_ago
```

## Syslog senders in index=network

```
index=network earliest=-1h | stats count by host
```

Hosts should show as IPs (10.30.0.1, 192.168.1.213, 192.168.1.3). If one shows as a hostname, the syslog `host` transform is back on.

## Windows sources in index=os

```
index=os earliest=-24h | timechart span=1h count by source
```

No Sysmon source while the others are flowing means the forwarder can't read the Sysmon channel. Run `Test-SocEndpoint.ps1`.

## Forwarder errors reported to splunk01

```
index=_internal sourcetype=splunkd log_level=ERROR earliest=-1h
| stats count latest(_raw) as example by host component
```

## Wazuh SCA scores

```
index=wazuh data.sca.type=summary
| dedup agent.name data.sca.policy
| table _time agent.name data.sca.policy data.sca.score data.sca.passed data.sca.failed
```
