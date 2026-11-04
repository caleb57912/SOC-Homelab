# 3.4 · Baseline Week (Deep Dive)

> **Result:** 11 days recorded (2026-10-24 to 11-03), 7 of 7 scheduled runs successful, a dashboard and a silence alert tuned from the recorded gaps. Findings are in [The recorded week](#the-recorded-week).

A baseline is a record of what normal looks like, so that later detections have something to be measured against. For one week I recorded, for every log source, how many events arrived each day and in how many of the 24 hours it was active. The numbers go into a summary index, an index that holds search results instead of raw logs, written by a scheduled search.

## Design

| Choice | Reason |
| --- | --- |
| Count with `tstats` | It reads index metadata rather than raw events, so it can cover every index in about a second |
| One row per index, sourcetype, source and host per day | `source` splits the `os` index into Security, Sysmon, System, Application and PowerShell; everywhere else it maps one-to-one onto sourcetype |
| `active_hours` alongside `events` | Volume alone hides a source that sends everything in one burst; hours show whether it reports continuously |
| UTC days | splunk01 and my Splunk account are on UTC, as are Shuffle and Velociraptor, so the days line up across tools |
| Summary index written with `collect` | Results stay after the raw data ages out, and the default `stash` sourcetype doesn't count against the license |
| Scheduled at 00:15 UTC for the previous day | The 15 minutes give forwarders time to deliver the day's last events |

## Index

On splunk01:

```bash
sudo -u splunk /opt/splunk/bin/splunk btool indexes list --debug 2>/dev/null | grep -E '\[(os|network|dns|wazuh|intel|zeek|suricata)\]'
sudo -u splunk /opt/splunk/bin/splunk add index baseline -app search
sudo -u splunk /opt/splunk/bin/splunk btool indexes list baseline --debug 2>/dev/null | grep -E '\[baseline\]|homePath ='
sudo systemctl restart Splunkd && sleep 30 && systemctl is-active Splunkd; timedatectl | grep "Time zone"
```

All seven existing indexes are defined in `apps/search/local/indexes.conf`, so `baseline` went into the same file. The CLI logs in as a Splunk user (`admin`), not as the Linux `splunk` service account. It reported that the new index needed a restart before it could take data. Time zone: `Etc/UTC`.

## Daily summary search

```
| tstats count where index=* NOT index=baseline earliest=-1d@d latest=@d by _time span=1h index sourcetype source host
| stats sum(count) as events dc(_time) as active_hours by index sourcetype source host
| eval _time=relative_time(now(),"-1d@d"), day=strftime(_time,"%Y-%m-%d")
| collect index=baseline source=baseline_daily
```

- `index=*` leaves out the internal indexes (`_internal`, `_audit`), and `NOT index=baseline` keeps the summary from counting itself.
- `tstats ... by _time span=1h`, then `dc(_time)`, gives the number of hours with at least one event.
- `eval _time` stamps each row with the day it describes. Without it, `collect` would use the time the search ran.

Saved as the report `SOC - Baseline daily summary` in the `search` app, owner `admin`, shared with the app, read and write for `admin` only. Cron `15 0 * * *`, earliest `-1d@d`, latest `@d`, first scheduled run 2026-10-27 00:15 UTC. The configuration is in [`siem/splunk/saved-searches/soc_baseline_daily_summary.conf`](../../siem/splunk/saved-searches/soc_baseline_daily_summary.conf).

## Backfill

I ran the search by hand for the two days before the schedule existed.

| Day | Rows | Events |
| --- | --- | --- |
| 2026-10-24 (Saturday) | 24 | 531,798 |
| 2026-10-25 (Sunday) | 24 | 420,001 |

### Issue: zero-event sources disappear

`intel` and the Catalyst switch's syslog had no events on 10/24, and `tstats` returned no row for them at all rather than a row with 0. A silent source can't be found by looking for zeros; it has to be found by comparing against the list of sources expected to report.

### Issue: a real-time time picker

The first check of the summary index returned nothing with the time picker on "All time (real-time)". A real-time search only watches events arriving from that moment on, so it never saw rows already written. With "All time" the 24 rows for 10/24 appeared.

### Issue: duplicate days

`collect` appends every time the search runs and doesn't check whether the day is already there. Splunk Web reruns the search in the bar when the time picker changes or the page reloads, and I also ran it again while checking whether an earlier run had happened. 10/25 ended up in the index three times: 72 rows and 1,260,003 events.

| Check | Search | Result |
| --- | --- | --- |
| Collect runs | `index=_audit action=search info=completed search="*collect index=baseline*"` over 7 days | One run for 10/24, and a 10/25 run before the check I meant to make first |
| Rows to delete | `index=baseline source=baseline_daily day="2026-10-25" \| stats count sum(events)` (All time) | 72 rows, 1,260,003 events |

The fix:

1. Added the `can_delete` role to `admin`. No role has it by default.
2. Ran `index=baseline day="2026-10-25" | delete` over All time, twice in total, since a further run had added another copy in between.
3. Removed `can_delete` from `admin` again.
4. Ran the collect once from a fresh browser tab with the time picker set first, and closed the tab after it finished.

`delete` makes events unsearchable but doesn't free the disk space, which is negligible for 48 rows. From here the scheduled report is the only thing that writes to `baseline`.

Result: 24 rows per day, with totals matching the dry runs.

## First scheduled run

The first scheduled run, 2026-10-27 00:15 UTC, finished with `status=success` and `result_count=0`. Nothing was written for 10/26.

```
index=_internal sourcetype=scheduler savedsearch_name="SOC - Baseline daily summary" | eval scheduled=strftime(scheduled_time,"%F %T") | table _time scheduled status result_count run_time
```

### Issue: the report's search was overwritten

I read the stored definition back over REST:

```
| rest /servicesNS/-/-/saved/searches splunk_server=local | search title="SOC - Baseline daily summary" | table title search dispatch.earliest_time dispatch.latest_time cron_schedule is_scheduled eai:acl.owner eai:acl.app
```

The `search` field held my row-count check, `index=baseline source=baseline_daily | stats count as rows sum(events) as events by day`, instead of the summary search. Schedule, time range, owner and app were unchanged. A search tab opened from a report saves back into that report, so running the check there and pressing Save replaced the search. Over `-1d@d` to `@d` there were no `baseline` rows for 10/26, so the scheduler counted nothing and reported success.

`status=success` only says the search ran without error. The row count is what shows whether it did its job.

The fix:

1. Settings → Searches, reports, and alerts → `SOC - Baseline daily summary` → Edit → Edit Search, pasted the four-line summary search back, and saved without running it.
2. Read the definition back over REST: the search started with `| tstats` and ended with `collect index=baseline source=baseline_daily`.
3. Backfilled 10/26 once from a fresh tab (on 10/27 UTC, `-1d@d` is 10/26) and closed the tab: 23 rows, 470,898 events. The Catalyst switch sent no syslog that day, so it had no row.
4. Checked with All time: one copy each of 10/24 (24 rows), 10/25 (24) and 10/26 (23), 71 rows in total.

Checks of the summary index run from a New Search tab only, and always over All time: each row is stamped with midnight of the day it describes, so "Last 24 hours" can't see yesterday's rows.

## Dashboard

I built the dashboard `SOC - Baseline week` in Dashboard Studio (grid layout, shared in the `search` app). The definition is in [`siem/splunk/dashboards/soc_baseline_week.json`](../../siem/splunk/dashboards/soc_baseline_week.json) and goes in through the editor's Source view.

| Panel | What it shows |
| --- | --- |
| Days recorded, Sources on the last day, Events on the last day | Whether the latest day arrived and how big it was |
| Expected sources: silence check | The silence alert's logic with every expected source listed as `ok` or `SILENT` |
| Daily events per index | Stacked columns, one per day |
| Per source: daily volume and active hours | Days seen, average, minimum and maximum events, average active hours, last day, change from average |
| Active hours per source per day | Which sources report around the clock and which in bursts |
| Daily events per source | Log scale, so small sources stay visible next to `zeek:conn` |

Every panel except the silence check starts with the same search and adds its own `stats` or `chart`:

```
index=baseline source=baseline_daily
| rename orig_index as src_index, orig_sourcetype as src_sourcetype, orig_source as src_source, orig_host as src_host
| dedup day src_index src_sourcetype src_source src_host
| eval label=src_index." · ".if(src_index="os",replace(src_source,"^XmlWinEventLog:",""),src_sourcetype)." · ".src_host
| table _time day src_index label events active_hours
| rename src_index as index
```

`dedup` keeps one row per source per day even if a day is ever written twice. I first ran it once as a base search with chained panels; after layout edits two chained tables showed "Unknown sid" while the tiles kept a pre-backfill result, so each panel now runs its own search. At 71 rows this costs nothing.

### Issue: every row looked like `baseline · stash · splunk01`

The first version grouped by `index`, `sourcetype`, `source` and `host` and showed one source with 54 events. `collect` gives each summary event its own metadata (index `baseline`, sourcetype `stash`, source `baseline_daily`, host `splunk01`) and keeps the values from the search results as `orig_index`, `orig_sourcetype`, `orig_source` and `orig_host`. The dedup therefore collapsed each day into one arbitrary row. `index=baseline source=baseline_daily | stats count as rows sum(events) as events by day orig_index` confirmed the `orig_` fields, and the dashboard then showed 24 sources and 420,001 events for 10/25, matching the backfill.

## Silence alert

`tstats` returns no row for a source that sent nothing, so a silent source can't be found by looking for zeros. The alert builds the list of expected sources from `baseline` and compares it with each source's latest event over the last 15 days.

```
index=baseline source=baseline_daily earliest=-15d@d latest=@d
| dedup day orig_index orig_sourcetype orig_source orig_host
| stats dc(day) as days_seen avg(active_hours) as avg_hours by orig_index orig_sourcetype orig_source orig_host
| rename orig_index as index, orig_sourcetype as sourcetype, orig_source as source, orig_host as host
| where days_seen>=2
| append [| tstats latest(_time) as last_seen where index=* NOT index=baseline earliest=-15d by index sourcetype source host]
| stats max(days_seen) as days_seen max(avg_hours) as avg_hours max(last_seen) as last_seen by index sourcetype source host
| where isnotnull(days_seen)
| eval threshold_h=case(sourcetype="zeek:ssh",168, host="192.168.1.213",336, avg_hours>=23,3, avg_hours>=20,8, avg_hours>=8,26, true(),74)
| eval silent_h=round((now()-coalesce(last_seen,relative_time(now(),"-15d")))/3600,1)
| where silent_h>threshold_h
| eval avg_hours=round(avg_hours,1), last_seen=if(isnull(last_seen),"none in 15 days",strftime(last_seen,"%F %T"))
| table index sourcetype source host days_seen avg_hours threshold_h silent_h last_seen
```

The thresholds below are the tuned ones from [the recorded week](#threshold-tuning); the first version used 2, 26 and 74 hours.

| Average active hours per day | Example sources | Silent longer than |
| --- | --- | --- |
| `zeek:ssh` (override) | Written only when an SSH session crosses the SPAN | 168 h |
| Catalyst syslog (override, `host="192.168.1.213"`) | Logs only on logins and config changes | 336 h |
| 23 or more | Pi-hole, UDR and Proxmox syslog, Sysmon, Security, Application, Suricata, Wazuh, Zeek conn/dns/ssl/http/files/notice | 3 h |
| 20 to 22 | `zeek:weird`, `zeek:x509` | 8 h |
| 8 to 19 | System, `zeek:software`, `zeek:known_services` | 26 h |
| Under 8 | PowerShell, `zeek:dhcp`, `zeek:known_hosts`, `zeek:ssh` | 74 h |
| Seen on fewer than 2 days | Catalyst syslog, `intel` | Not expected yet |

A source that stops entirely shows `none in 15 days` because the `coalesce` counts it as silent since the start of the window.

Saved as the alert `SOC - Baseline silent log source` (search app, shared in app): cron `20 * * * *`, trigger when the number of results is greater than 0, once per result, throttled 12 hours on `index,sourcetype,source,host`, action Add to Triggered Alerts, severity Medium. The configuration is in [`siem/splunk/saved-searches/soc_baseline_silent_log_source.conf`](../../siem/splunk/saved-searches/soc_baseline_silent_log_source.conf).

Verification:

- The status version (no final `where`, a `status` column instead) listed 24 expected sources, all `ok`.
- With `threshold_h=0.1` in the search bar (not saved), every source quiet for more than six minutes turned `SILENT` and the busy ones stayed `ok`.
- `zeek:ssh` was last seen 2026-10-25 01:49, about 50 hours earlier. Zeek only writes it when an SSH session crosses the SPAN, so it will fire after 74 hours without one. That is a quiet source rather than a broken one.

### Issue: the alert saved the status search

The REST check of the new alert showed the status search (ending in `sort` and `table status ...`) instead of the alert search. It returns all 24 sources every time, so the first hourly run would have raised 24 alerts. The status search was still on the clipboard when I saved the alert. I replaced it through Edit Search, as with the report, and read it back:

```
| rest /servicesNS/-/-/saved/searches splunk_server=local | search title="SOC - Baseline silent log source" | table title search alert_type alert_comparator alert_threshold alert.digest_mode
```

Result: the search ends in `where silent_h>threshold_h` and the alert `table`; `alert_type` is `number of events`, `alert_comparator` is `greater than`, `alert_threshold` is `0`, `alert.digest_mode` is `0` (once per result). On Splunk 10 the trigger settings come back over REST under those names, not `counttype`, `relation` and `quantity` as in savedsearches.conf.

## The recorded week

### Runs

| Check | Search | Result |
| --- | --- | --- |
| Days in the index | `index=baseline source=baseline_daily \| stats count as rows sum(events) as events by day` (All time) | 11 days, 10/24–11/03, 23–24 rows each, no duplicates |
| Scheduled runs, 7 days | `index=_internal sourcetype=scheduler (savedsearch_name="SOC - Baseline daily summary" OR savedsearch_name="SOC - Baseline silent log source") status=* \| stats count as runs sum(eval(if(status="success",1,0))) as ok max(result_count) as max_results by savedsearch_name` | Daily summary 7/7 successful, at most 24 rows; silence alert 169/169 successful, at most 3 results |

The alert's action, Add to Triggered Alerts, doesn't show up in the scheduler's `alert_actions` field, and triggered alerts expire after 24 hours, so I read the firing history from the scheduler log instead: `index=_internal sourcetype=scheduler savedsearch_name="SOC - Baseline silent log source" result_count>0 | table _time result_count sid`.

### Daily volume per index

```
index=baseline source=baseline_daily | dedup day orig_index orig_sourcetype orig_source orig_host | chart sum(events) over day by orig_index | addtotals
```

| Day (UTC) | dns | network | os | suricata | wazuh | zeek | Total |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Sat 10/24 | 164,076 | 31,506 | 47,324 | 12,250 | 764 | 275,878 | 531,798 |
| Sun 10/25 | 112,708 | 32,204 | 44,333 | 10,656 | 698 | 219,402 | 420,001 |
| Mon 10/26 | 105,403 | 32,778 | 45,696 | 10,336 | 826 | 275,859 | 470,898 |
| Tue 10/27 | 174,440 | 33,925 | 69,282 | 22,136 | 697 | 330,973 | 631,453 |
| Wed 10/28 | 128,492 | 32,226 | 77,909 | 8,165 | 759 | 217,097 | 464,648 |
| Thu 10/29 | 121,840 | 33,799 | 52,879 | 3,654 | 948 | 200,354 | 413,474 |
| Fri 10/30 | 76,158 | 34,876 | 42,848 | 2,720 | 869 | 171,340 | 328,811 |
| Sat 10/31 | 77,724 | 35,137 | 54,902 | 2,109 | 850 | 169,775 | 340,497 |
| Sun 11/01 | 83,645 | 37,167 | 55,818 | 2,284 | 967 | 178,253 | 358,134 |
| Mon 11/02 | 145,379 | 28,973 | 76,009 | 5,791 | 713 | 209,823 | 466,688 |
| Tue 11/03 | 141,713 | 28,861 | 68,548 | 10,042 | 946 | 204,153 | 454,263 |

| Index | Median per day | Range | Spread from median |
| --- | --- | --- | --- |
| zeek | 209,823 | 169,775 – 330,973 | −19% / +58% |
| dns | 121,840 | 76,158 – 174,440 | −37% / +43% |
| os | 54,902 | 42,848 – 77,909 | −22% / +42% |
| network | 32,778 | 28,861 – 37,167 | −12% / +13% |
| suricata | 8,165 | 2,109 – 22,136 | −74% / +171% |
| wazuh | 826 | 697 – 967 | −16% / +17% |
| **Total** | **454,263** | 328,811 – 631,453 | −28% / +39% |

### Findings

- **Two kinds of source.** `network` (UDR and Proxmox syslog) and `wazuh` stayed within about ±15% of their medians every day. They are machine-generated and don't depend on what anyone in the house is doing, so a volume check on them can be tight. `dns`, `zeek` and `os` follow household and PC use and swing by 40–60%.
- **Suricata is the least stable source.** It went from 10–12k alerts a day to 2–3k on 10/29–11/01, then back to 10k by 11/03. A fixed volume threshold would be useless here; what matters is which signatures fire, not how many.
- **10/27 was the busiest day** (631,453 events, +39%). `dns`, `zeek` and `suricata` all peaked that day, and `suricata` doubled. I didn't trace the cause during the baseline; the drill-down is on the backlog.
- **10/30–11/01 was the quietest stretch** (329k–358k). `dns` and `zeek` dropped together while `network` and `wazuh` didn't, which fits less household traffic rather than a collection problem. The first weekend (10/24–25) was not low, so it isn't a weekday pattern.
- **Event-driven sources aren't silent by failure.** `zeek:ssh` and Catalyst syslog only log when someone connects to or changes something. The switch logged on one day in the window (4 events on 11/03).
- **`intel` never appeared in the daily summary,** so it isn't an expected source and is monitored by the MISP lookup's own schedule instead.

### Issue: the silence alert fired on 168 of 169 runs

Every hourly run from 10/28 onward returned one result, and the 10/31 17:20 run returned two. The 12-hour throttle kept Triggered Alerts to about two entries a day, but the search itself was flagging the same source all week.

The longest gap per source over the eight full days before 11/04:

```
| tstats count where index=* NOT index=baseline earliest=-8d@d latest=@d by _time span=1h index sourcetype source host
| sort 0 index sourcetype source host _time
| streamstats current=f last(_time) as prev by index sourcetype source host
| eval gap_h=round((_time-prev)/3600-1,0)
| stats max(gap_h) as max_gap_h count as active_hours earliest(_time) as first latest(_time) as last by index sourcetype source host
| eval first=strftime(first,"%F %H:%M"), last=strftime(last,"%F %H:%M")
| sort - max_gap_h
```

`streamstats` gives each hourly bucket the time of the previous bucket for the same source, so `gap_h` is the number of empty hours between them and `max(gap_h)` is the longest silence that source had.

| Source | Longest gap | First threshold |
| --- | --- | --- |
| `zeek:ssh` | No events in the 8 days | 74 h |
| `zeek:known_services` | 15 h | 74 h |
| PowerShell/Operational | 12 h | 74 h |
| `zeek:dhcp` | 11 h | 74 h |
| `zeek:known_hosts` | 10 h | 74 h |
| `zeek:software` | 8 h | 26 h |
| `zeek:weird` | 5 h | 2 h |
| System | 4 h | 26 h |
| Application, `wazuh:alerts` | 2 h | 2 h |
| Suricata, `zeek:x509` | 1 h | 2 h |
| Pi-hole | 0 h | 2 h |

`zeek:ssh` was the steady result: last seen 10/25 01:49, past 74 hours on 10/28. `zeek:weird`, with a 5-hour gap against a 2-hour threshold, is the likely second result on 10/31.

I hadn't used SSH all week, so the question was whether the sensor had gone blind to it. I opened one session from my PC to splunk01 (`ssh caleb@10.30.0.10 exit`) and searched `index=zeek sourcetype=zeek:ssh | table _time id.orig_h id.resp_h auth_success client server` over the last 15 minutes: one row, 192.168.1.11 → 10.30.0.10, `auth_success=true`. The SPAN copies PC traffic up to three times, but Zeek tracks a connection by its addresses and ports, so the copies merge into one `ssh.log` entry. The pipeline worked; the source was simply idle.

The alert did its job: a source that had always reported stopped, and it said so. The silence was explained by my own behaviour, which is a tuning result, not a broken detection.

### Threshold tuning

| Average active hours per day | Before | After | Reason |
| --- | --- | --- | --- |
| `zeek:ssh` | 74 h | 168 h | Event-driven; still alerts if a whole week of admin SSH never reaches the sensor |
| 23 or more | 2 h | 3 h | Application and Wazuh reached 2-hour gaps |
| 20 to 22 | 2 h | 8 h | `zeek:weird` had a 5-hour gap |
| 8 to 19 | 26 h | 26 h | Longest gap 8 h |
| Under 8 | 74 h | 74 h | Longest gap 15 h |

I changed the threshold line through Edit Search and read it back over REST: `| rest /servicesNS/-/-/saved/searches splunk_server=local | search title="SOC - Baseline silent log source" | table search description`. The override comes first because `case()` returns the value of the first condition that matches; after the hour tiers, `zeek:ssh` (about 2 active hours a day) would fall through to 74 h.

### Issue: the 168-hour override could never fire

Before adding a Catalyst override I checked the longest silence the search can measure. `tstats` only looked back 4 days, and a source with no events in that window got `coalesce(last_seen, now-4d)`, so `silent_h` topped out at 96 hours. Any threshold above 96, including the 168 h for `zeek:ssh`, could never be crossed. I widened the `tstats` window and the `coalesce` default to 15 days, matching the expected-source window, so thresholds up to 360 hours work. Catalyst syslog then got its own override of 336 h (two weeks) ahead of the hour tiers, because the switch only logs on logins and config changes and would otherwise become expected at 74 h once it logged on a second day.

### Issue: silent sources sorted to the bottom

The dashboard's silence table never showed `zeek:ssh` at the top while it was silent. `sort - status` sorts descending, and lowercase `ok` sorts after uppercase `SILENT`, so descending put every `ok` row first. I changed it to `sort status`.

### Issue: a quote broke the dashboard JSON

After the threshold change the Source view refused the definition: "Expected ',' or ']' after property value in JSON". Each search lives inside a JSON string, and the `"zeek:ssh"` I added ended that string early. Inside JSON the quotes have to be written `\"zeek:ssh\"`. I fixed the file and checked it parses before pasting.

## Evidence

**The baseline index added through the CLI, the restart warning, and the index in the same file as the others.**

![The baseline index added through the CLI, the restart warning, and the index in the same file as the others.](../../screenshots/build-log/18-baseline-week/01-index-added-restart-needed.png)

**Dry run for 10/24: 20 index, sourcetype and host combinations, 531,798 events.**

![Dry run for 10/24: 20 index, sourcetype and host combinations, 531,798 events.](../../screenshots/build-log/18-baseline-week/02-dry-run-2026-10-24.png)

**The baseline index after the restart, still empty.**

![The baseline index after the restart, still empty.](../../screenshots/build-log/18-baseline-week/03-baseline-index-exists.png)

**The collect for 10/24, split by source: 24 rows.**

![The collect for 10/24, split by source: 24 rows.](../../screenshots/build-log/18-baseline-week/04-collect-2026-10-24.png)

**No results with a real-time time picker.**

![No results with a real-time time picker.](../../screenshots/build-log/18-baseline-week/05-realtime-picker-no-results.png)

**10/24 in the summary index with All time: 24 rows, 531,798 events.**

![10/24 in the summary index with All time: 24 rows, 531,798 events.](../../screenshots/build-log/18-baseline-week/06-day-1-verified.png)

**The report shared with the app.**

![The report shared with the app.](../../screenshots/build-log/18-baseline-week/07-report-permissions.png)

**The report scheduled at 15 0 * * * with its first run at 2026-10-27 00:15 UTC.**

![The report scheduled at 15 0 * * * with its first run at 2026-10-27 00:15 UTC.](../../screenshots/build-log/18-baseline-week/08-report-scheduled.png)

**The audit log of collect runs.**

![The audit log of collect runs.](../../screenshots/build-log/18-baseline-week/09-audit-collect-runs.png)

**10/25 in the index three times: 72 rows, 1,260,003 events.**

![10/25 in the index three times: 72 rows, 1,260,003 events.](../../screenshots/build-log/18-baseline-week/10-2026-10-25-three-copies.png)

**The rows selected for deletion.**

![The rows selected for deletion.](../../screenshots/build-log/18-baseline-week/11-rows-to-delete.png)

**Two copies after the delete, from another run in between.**

![Two copies after the delete, from another run in between.](../../screenshots/build-log/18-baseline-week/12-two-copies-after-delete.png)

**Clean: one copy of each day.**

![Clean: one copy of each day.](../../screenshots/build-log/18-baseline-week/13-clean-two-days.png)

**The first dashboard: every row collapsed into the summary event's own metadata.**

![The first dashboard: every row collapsed into the summary event's own metadata.](../../screenshots/build-log/18-baseline-week/14-dashboard-stash-fields.png)

**The original index kept as orig_index.**

![The original index kept as orig_index.](../../screenshots/build-log/18-baseline-week/15-orig-index-fields.png)

**The first scheduled run: success with 0 results.**

![The first scheduled run: success with 0 results.](../../screenshots/build-log/18-baseline-week/16-scheduled-run-zero-results.png)

**The report's stored search replaced by the row-count check.**

![The report's stored search replaced by the row-count check.](../../screenshots/build-log/18-baseline-week/17-report-search-overwritten.png)

**The 10/26 backfill: 23 rows, 470,898 events.**

![The 10/26 backfill: 23 rows, 470,898 events.](../../screenshots/build-log/18-baseline-week/18-backfill-2026-10-26.png)

**Three days, one copy each.**

![Three days, one copy each.](../../screenshots/build-log/18-baseline-week/19-three-days-clean.png)

**The dashboard on orig_ fields: 24 sources, 420,001 events for 10/25.**

![The dashboard on orig_ fields: 24 sources, 420,001 events for 10/25.](../../screenshots/build-log/18-baseline-week/20-dashboard-fixed.png)

**The silence check: 24 expected sources, all ok.**

![The silence check: 24 expected sources, all ok.](../../screenshots/build-log/18-baseline-week/21-silence-status-check.png)

**Threshold forced to 0.1 h: the quieter sources turn SILENT.**

![Threshold forced to 0.1 h: the quieter sources turn SILENT.](../../screenshots/build-log/18-baseline-week/22-silence-threshold-test.png)

**The alert as first saved, with the status search.**

![The alert as first saved, with the status search.](../../screenshots/build-log/18-baseline-week/23-alert-saved-with-status-search.png)

**The alert search replaced.**

![The alert search replaced.](../../screenshots/build-log/18-baseline-week/24-alert-search-fixed.png)

**The alert read back over REST: correct search, number of results greater than 0, once per result.**

![The alert read back over REST: correct search, number of results greater than 0, once per result.](../../screenshots/build-log/18-baseline-week/25-alert-verified.png)

**The dashboard with the silence panel.**

![The dashboard with the silence panel.](../../screenshots/build-log/18-baseline-week/26-dashboard-silence-panel.png)

**11 days in the summary index, one copy each.**

![11 days in the summary index, one copy each.](../../screenshots/build-log/18-baseline-week/27-eleven-days-recorded.png)

**The week's scheduled runs: 7/7 and 169/169 successful.**

![The week's scheduled runs: 7/7 and 169/169 successful.](../../screenshots/build-log/18-baseline-week/28-scheduled-runs-week.png)

**Silence alert runs with results: nearly every hour from 10/28.**

![Silence alert runs with results: nearly every hour from 10/28.](../../screenshots/build-log/18-baseline-week/29-silence-alert-runs.png)

**Longest gap per source over eight days.**

![Longest gap per source over eight days.](../../screenshots/build-log/18-baseline-week/30-longest-gap-per-source.png)

**The dashboard with 11 days.**

![The dashboard with 11 days.](../../screenshots/build-log/18-baseline-week/31-dashboard-eleven-days.png)

**One SSH session reaching ssh.log.**

![One SSH session reaching ssh.log.](../../screenshots/build-log/18-baseline-week/32-zeek-ssh-test.png)

**The retuned alert read back over REST.**

![The retuned alert read back over REST.](../../screenshots/build-log/18-baseline-week/33-alert-retuned.png)

**Daily volume per index.**

![Daily volume per index.](../../screenshots/build-log/18-baseline-week/34-daily-volume-per-index.png)

**The final dashboard.**

![The final dashboard.](../../screenshots/build-log/18-baseline-week/35-dashboard-final.png)

## Backlog

- Make the daily search safe to rerun, for example by skipping a day that already exists in `baseline`
- Commit the `indexes.conf` stanzas for all eight indexes to the repo
- Alert on the daily summary itself: a scheduled run with 0 results should raise an alert, not report success
- Drill into 10/27 (dns, zeek and suricata peak) and the suricata drop on 10/29–11/01
- Volume checks on the stable sources (`network`, `wazuh`): alert outside about ±25% of the median
- Send silence alerts to TheHive through Shuffle once the workflow handles more than Suricata alerts
