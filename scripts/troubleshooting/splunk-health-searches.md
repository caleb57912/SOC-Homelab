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


License usage per index per day, one column per index:

```
index=_internal source=*license_usage.log* type=Usage earliest=-7d@d | eval day=strftime(_time,"%Y-%m-%d") | stats sum(b) as bytes by day idx | eval MB=round(bytes/1048576,1) | xyseries day idx MB | addtotals fieldname=total_MB
```

## Which license is active

```
| rest /services/licenser/licenses splunk_server=local | eval expires=strftime(expiration_time,"%Y-%m-%d") | table label type status quota expires
```

```
| rest /services/licenser/groups splunk_server=local | table title is_active
```

`Enterprise` must be 1. If `Free` is active, scheduled searches and alerts stop without any error, which would break the baseline and the Shuffle webhook.

## Baseline: one copy of each day

Time picker **All time**, not "All time (real-time)": a real-time search only sees events arriving from now on and returns nothing for rows already written.

```
index=baseline source=baseline_daily | stats count as rows sum(events) as events by day
```

Each day should have about the same number of rows (24 at the start). Double or triple the rows means the day was collected more than once.

## Baseline: how many times a collect ran

Time picker **Last 7 days**. Every run of a search ending in `collect` appends another copy of the day, and Splunk Web reruns the search bar on a time-picker change or a page reload.

```
index=_audit action=search info=completed search="*collect index=baseline*" | table _time user search_id total_run_time | sort _time
```

Scheduled runs show `user` as the report owner shortly after 00:15 UTC. Anything else was a hand run.

## Baseline: the report's schedule

```
| rest /servicesNS/-/-/saved/searches splunk_server=local | search title="SOC - Baseline*" | table title eai:acl.app eai:acl.owner eai:acl.sharing cron_schedule is_scheduled next_scheduled_time
```

`/servicesNS/-/-/` lists every owner in every app. The Settings → Searches, reports, and alerts page is filtered by app and owner and can hide a report that exists.

## An index exists and is receiving

```
| rest /services/data/indexes splunk_server=local | search title=baseline | table title homePath currentDBSizeMB totalEventCount
```

An index added from the CLI needs a Splunk restart before it takes data.

## Shuffle webhook deliveries from alerts

```
index=_internal sourcetype=splunkd component=sendmodalert action=webhook | table _time log_level event_message
```

Look for `Webhook receiver responded with HTTP status=200`. The alert form rejects `http://` webhook URLs, so use Shuffle's HTTPS port (3443). To rule out the allow list, on splunk01:

```bash
sudo -u splunk /opt/splunk/bin/splunk btool alert_actions list webhook --debug | grep -iE "allowlist|enable"
```
