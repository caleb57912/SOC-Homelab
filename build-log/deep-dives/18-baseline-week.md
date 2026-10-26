# 3.4 · Baseline Week (Deep Dive)

> **Work in progress.** Recording started 2026-10-26 with 10/24 and 10/25 backfilled. Still to come: the dashboard, the silence alert, seven recorded days, and the findings.

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

## Backlog

- Make the daily search safe to rerun, for example by skipping a day that already exists in `baseline`
- Commit the `indexes.conf` stanzas for all eight indexes to the repo
