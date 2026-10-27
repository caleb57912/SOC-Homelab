# 🗺️ Roadmap

_Updated 2026-10-27._

Where the build stands, what comes next, and the improvements queued alongside it. Write-ups for every finished step are in the [Build Log](README.md).

## Phases

```mermaid
flowchart LR
    P1["1 · Foundation ✅<br/>segmentation, switch,<br/>8 SOC systems"] --> P2["2 · Telemetry + intel ✅<br/>Splunk, DNS, syslog, Sysmon,<br/>Wazuh, MISP, Zeek + Suricata"] --> P3["3 · Response + baseline 🚧<br/>TheHive, Shuffle,<br/>Velociraptor, baseline week"] --> P4["4 · Use-case loop<br/>build, test, tune,<br/>work cases"] --> P5["5 · Reporting<br/>weekly SOC report,<br/>monthly threat brief"]

    classDef done fill:#1f6f43,stroke:#2ea86b,color:#ffffff
    classDef now fill:#b8860b,stroke:#ffd166,color:#000000,stroke-width:3px
    classDef todo fill:#3a3f47,stroke:#8a929c,color:#ffffff
    class P1,P2 done
    class P3 now
    class P4,P5 todo
```

## Phase 3 in detail

```mermaid
flowchart TB
    subgraph P3["Phase 3 · Response + baseline"]
        direction LR
        A1["3.1 TheHive ✅"] --> A2["3.2 Shuffle ✅<br/>gate met"] --> A3["3.3 Velociraptor ✅"] --> A4["3.4 Baseline week 🚧"]
    end

    subgraph B["3.4 Baseline week"]
        direction TB
        subgraph DONE["Done"]
            direction LR
            D1["baseline<br/>summary index"] --> D2["daily report<br/>00:15 UTC"] --> D3["10/24–10/26<br/>recorded"] --> D4["baseline<br/>dashboard"] --> D5["silence alert:<br/>a source stops sending"]
        end
        subgraph AUTO["Records nightly"]
            direction LR
            R1["one day per run<br/>events + active hours<br/>per log source"]
        end
        subgraph NEXT["Next"]
            direction LR
            N1["watch the alert's<br/>first firings"] --> N2["tune thresholds"]
        end
        subgraph END["After 7 days"]
            direction LR
            E1["findings:<br/>normal ranges, anomalies"] --> E2["write-up 18"] --> E3["Phase 3 ✅"]
        end
        DONE --> AUTO --> NEXT --> END
    end

    subgraph P4["Phase 4 · Use-case loop"]
        direction LR
        F1["4.1 Failed<br/>Proxmox logins"] --> F2["4.2 New device<br/>on the network"] --> F3["4.3 Vulnerable<br/>software"] --> F4["4.4 IoC match<br/>DNS vs MISP"]
    end

    A4 --> B
    END --> P4

    classDef done fill:#1f6f43,stroke:#2ea86b,color:#ffffff
    classDef now fill:#b8860b,stroke:#ffd166,color:#000000,stroke-width:3px
    classDef auto fill:#1d4e89,stroke:#4c8ed9,color:#ffffff
    classDef todo fill:#3a3f47,stroke:#8a929c,color:#ffffff
    class A1,A2,A3,D1,D2,D3,D4,D5 done
    class A4 now
    class R1 auto
    class N1,N2,E1,E2,E3,F1,F2,F3,F4 todo
```

## Improvement backlog

Each build step ends with a backlog. These are those items, grouped and put in the order I plan to work them: housekeeping during the baseline week, then what the Phase 4 use cases depend on, then hardening, monitoring of the SOC itself, and tuning once the baseline gives real numbers.

```mermaid
flowchart LR
    subgraph T1["① Now · during the baseline week"]
        direction TB
        a1["velo01: CA key down to<br/>one offline backup"]
        a2["Clean up leftover installers<br/>and test artifacts"]
        a3["Proxmox backup jobs<br/>for every SOC system"]
        a4["App backups: Shuffle DB,<br/>TheHive/Cassandra/ES,<br/>Velociraptor datastore"]
        a5["Commit TheHive, ES, Cassandra<br/>and index configs to the repo"]
        a6["Switch config backup"]
        a1 --> a2 --> a3 --> a4 --> a5 --> a6
    end

    subgraph T2["② Before Phase 4 · use cases need these"]
        direction TB
        b1["Shuffle: skip VT/AbuseIPDB<br/>for private IPs"]
        b2["Shuffle: 'lookup failed'<br/>instead of blanks"]
        b3["Shuffle: escape quotes,<br/>multi-row alerts"]
        b4["Working Splunk links<br/>in TheHive alerts"]
        b5["Splunk CIM mappings:<br/>Network_Traffic, DNS, IDS"]
        b6["Monitor Zeek capture loss<br/>and Suricata drops"]
        b7["Non-admin Splunk<br/>analyst account"]
        b8["Velociraptor linked to<br/>TheHive/Shuffle"]
        b9["Alert when the daily<br/>baseline run writes 0 rows"]
        b10["Silence alerts<br/>into TheHive"]
        b1 --> b2 --> b3 --> b4 --> b5 --> b6 --> b7 --> b8 --> b9 --> b10
    end

    subgraph T3["③ Hardening · access + encryption"]
        direction TB
        c1["Host firewalls on<br/>TheHive, Shuffle, Velociraptor"]
        c2["Firewall: Internal → SOC<br/>limited to specific ports"]
        c3["Switch: VTY access-class,<br/>remove legacy VLANs"]
        c4["Non-root users in LXCs"]
        c5["Authenticated Shuffle webhook,<br/>API keys in headers"]
        c6["Internal CA, then TLS for<br/>forwarders, syslog and every UI"]
        c1 --> c2 --> c3 --> c4 --> c5 --> c6
    end

    subgraph T4["④ Coverage · watch the SOC itself"]
        direction TB
        d1["SOC tool logs into Splunk:<br/>MISP, TheHive, Shuffle,<br/>Velociraptor"]
        d2["Wazuh agents and Velociraptor<br/>clients on the SOC servers"]
        d3["All forwarders on the<br/>deployment server"]
        d4["SOC VLAN DNS<br/>through Pi-hole"]
        d5["Per-index retention"]
        d1 --> d2 --> d3 --> d4 --> d5
    end

    subgraph T5["⑤ After the baseline · tune with real numbers"]
        direction TB
        e1["Revisit JVM heaps:<br/>TheHive, Elasticsearch, OpenSearch"]
        e2["Revisit Velociraptor<br/>server memory"]
        e3["Velociraptor client<br/>event monitoring"]
        e4["Shuffle worker tuning,<br/>pin remaining images"]
        e5["Baseline search<br/>safe to rerun"]
        e6["Tune silence thresholds;<br/>zeek:ssh, Catalyst expected?"]
        e7["misp-modules<br/>if RAM allows"]
        e1 --> e2 --> e3 --> e4 --> e5 --> e6 --> e7
    end

    T1 ==> T2 ==> T3
    T2 -.-> T4
    T3 ==> T5
    T4 -.-> T5

    classDef now fill:#b8860b,stroke:#ffd166,color:#000000
    classDef pre fill:#1d4e89,stroke:#4c8ed9,color:#ffffff
    classDef hard fill:#8b1e1e,stroke:#e05252,color:#ffffff
    classDef cov fill:#1f6f43,stroke:#2ea86b,color:#ffffff
    classDef tune fill:#3a3f47,stroke:#8a929c,color:#ffffff
    class a1,a2,a3,a4,a5,a6 now
    class b1,b2,b3,b4,b5,b6,b7,b8,b9,b10 pre
    class c1,c2,c3,c4,c5,c6 hard
    class d1,d2,d3,d4,d5 cov
    class e1,e2,e3,e4,e5,e6,e7 tune
```

Backups come first on purpose: Phase 4 triggers detections on live systems, so restore points should exist before that starts.
