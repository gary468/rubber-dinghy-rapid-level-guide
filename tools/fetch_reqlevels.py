"""Minimum levels for quests QuestieDB has none for (mostly Forever-only quests), read from
ForeverChanges (foreverchanges.pro), whose quest pages say "requires level N" from what players see in
game. Writes tools/forever_reqlevels.json {questId: level}; gen_route.py uses it.

Usage:  python tools/fetch_reqlevels.py tools/data.json tools/forever_reqlevels.json
One request a second; quests already in the output file are skipped, so it can be re-run.
"""
import json, os, re, sys, time, urllib.request

DATA, OUT = sys.argv[1], sys.argv[2]
quests = json.load(open(DATA, encoding="utf-8"))["quests"]
todo = sorted(int(k) for k, v in quests.items() if not v.get("requiredLevel") and (v.get("questLevel") or 0) >= 10)
found = json.load(open(OUT)) if os.path.exists(OUT) else {}
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/130.0"
for q in todo:
    if str(q) in found: continue
    try:
        req = urllib.request.Request(f"https://foreverchanges.pro/quest/{q}", headers={"User-Agent": UA, "Accept": "text/html"})
        html = urllib.request.urlopen(req, timeout=25).read().decode("utf-8", "replace")
        m = re.search(r"requires level (\d+)", html)
        found[str(q)] = int(m.group(1)) if m else None
    except Exception as e:
        found[str(q)] = None
        print(q, "error", e, flush=True)
    json.dump(found, open(OUT, "w"), indent=0)
    time.sleep(1.0)
print(len(todo), "quests;", sum(1 for v in found.values() if v), "with a minimum level")
