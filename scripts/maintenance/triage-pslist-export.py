#!/usr/bin/env python3
import argparse
import json
import re
import sys
from collections import Counter

USER_WRITABLE = re.compile(r"\\(users\\[^\\]+\\(appdata|downloads|desktop|documents)|users\\public|programdata|windows\\temp|temp)\\", re.I)


def load(path):
    text = open(path, encoding="utf-8").read().strip()
    if text.startswith("["):
        return json.loads(text)
    return [json.loads(line) for line in text.splitlines() if line.strip()]


def trust(row):
    auth = row.get("Authenticode") or {}
    return auth.get("Trusted") if isinstance(auth, dict) else None


def main():
    p = argparse.ArgumentParser(description="Triage a Velociraptor Windows.System.Pslist JSON export by signature, path and user")
    p.add_argument("export", help="JSON or JSON-lines export of the collection results")
    p.add_argument("--cmdline", action="store_true", help="also print command lines (keep these out of the repo)")
    args = p.parse_args()

    rows = load(args.export)
    print(f"{len(rows)} processes")
    counts = Counter(trust(r) or "no file" for r in rows)
    for k, v in counts.most_common():
        print(f"  {k:<10} {v}")

    unsigned = [r for r in rows if trust(r) not in ("trusted",)]
    unsigned.sort(key=lambda r: (not USER_WRITABLE.search(r.get("Exe") or ""), (r.get("Exe") or "").lower()))

    print("\nNot trusted, user-writable paths first (the pattern to explain before anything else):")
    print(f"{'PID':>7}  {'FLAG':<6} {'TRUST':<10} {'USER':<28} NAME | EXE")
    for r in unsigned:
        exe = r.get("Exe") or ""
        flag = "UWPATH" if USER_WRITABLE.search(exe) else ""
        user = (r.get("Username") or "")[:28]
        print(f"{r.get('Pid', ''):>7}  {flag:<6} {trust(r) or 'no file':<10} {user:<28} {r.get('Name', '')} | {exe}")
        if args.cmdline and r.get("CommandLine"):
            print(f"{'':>7}  cmd: {r['CommandLine'][:200]}")

    system_exes = Counter((r.get("Name") or "").lower() for r in rows if (r.get("Username") or "").upper().endswith("SYSTEM"))
    velo = [r for r in rows if (r.get("Name") or "").lower() == "velociraptor.exe"]
    print("\nVelociraptor client:", ", ".join(f"PID {r['Pid']} {trust(r)} {r.get('Username')}" for r in velo) or "not found")
    print(f"Distinct process names running as SYSTEM: {len(system_exes)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
