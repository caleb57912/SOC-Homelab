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

## Sensor: Zeek logs by type

```
index=zeek earliest=-1h | stats count by sourcetype
```

`zeek:conn` should be the largest. A missing sourcetype that used to appear means the forwarder lost read access or the log isn't being written. Run `check-sensor.sh`.

## Sensor: only alerts reach index=suricata

```
index=suricata _index_earliest=-1h | stats count by event_type
```

Anything other than `alert` means the nullQueue filter in TA-soc-homelab isn't applied (parse-time change without a Splunk restart).

## Sensor: test alert

```
index=suricata alert.signature_id=9000001 earliest=-15m | table _time src_ip dest_ip alert.signature vlan{}
```

Run `test-nids-pipeline.sh` on sensor01 first.

## Sensor: indexing lag on new data

```
index=zeek OR index=suricata earliest=-15m | eval lag=_indextime-_time | stats count avg(lag) as avg_lag max(lag) as max_lag by index sourcetype
```

`suricata:eve` should be seconds. `zeek:conn` and `zeek:ssl` run higher because Zeek writes a record when the connection ends but stamps it with the start time. Negative lag means a timestamp parsing problem.

## Sensor: top Suricata signatures

```
index=suricata earliest=-24h | stats count by alert.signature_id alert.signature | sort - count | head 20
```

## MISP lookup rebuild runs

```
index=_internal sourcetype=scheduler savedsearch_name="MISP - Build DNS IOC lookup" | table _time status result_count run_time
```

```
| inputlookup misp_dns_iocs.csv | stats count
```

## License usage per day

```
index=_internal source=*license_usage.log* type=Usage earliest=-7d@d | timechart span=1d sum(b) as bytes | eval MB=round(bytes/1048576,1) | fields _time MB
```

```
index=_internal source=*license_usage.log* type=Usage earliest=-1d@d | stats sum(b) as bytes by idx | eval MB=round(bytes/1048576,1) | sort - MB
```

