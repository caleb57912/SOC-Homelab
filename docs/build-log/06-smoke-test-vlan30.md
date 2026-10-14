# 1.6 · End-to-End Smoke Test

**Result:** The full VLAN 30 path and every firewall policy were verified, **after diagnosing a failure with packet capture**.

## Troubleshooting
The first test VM had **no connectivity**. Instead of guessing, I captured traffic on the host uplink:

```
VM → who-has 10.30.0.1?   (tagged VLAN 30)   ✅ leaving the host
Switch STP for VLAN 30                       ✅ switch forwarding VLAN 30
Reply from gateway                           ❌ never arrives
```

So the fault was **past the switch**. Root cause: the router's switch-facing port had **Tagged VLANs = "Block All"**, a classic trunk mismatch (one side tags, the other drops). One setting fixed it, and the gateway answered within seconds.

## Test results
| Test | Expected | Result |
| --- | --- | --- |
| SSH from home → SOC VM | Connects | ✅ |
| SOC → internet | Works | ✅ |
| SOC → DNS | Resolves | ✅ |
| SOC → router admin UI | Blocked | ✅ |
| SOC → home network | Blocked | ✅ |

Firewall hit counters confirmed each policy matched.

## Open item
An idle VM caused ~2,800 blocked packets to the router. **Hypothesis:** IPv6 neighbor discovery. Fixed at the source in step 1.7 (IPv6 disabled), not by adding an allow rule.

**Skills:** packet analysis (tcpdump) · structured troubleshooting · firewall validation

➡️ [Deep dive](deep-dives/06-smoke-test-vlan30.md)
