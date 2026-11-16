"""Where each quest on the route starts and ends, read from ForeverChanges' quest pages (the pins on
its zone map: "Start, End: Ketharas, 73.3, 81.7", from what players saw in game). gen_route.py uses
them to correct givers and hand-ins Questie's Forever data has in the wrong place (it filed Ketharas
in Moonglade; he's in Mount Hyjal), and tools/audit_route.py reports every difference.

Usage:  python tools/fetch_fc_locs.py Data.lua tools/forever_locs.json [first-map]
Quests: every quest in the route's steps (quests, pick-ups, hand-ins); the step map given first.
Output: {qid: {"map": uiMap, "start": [name, x, y] | null, "end": [name, x, y] | null}}
One request a second; quests already in the output file are skipped, so it can be re-run.
"""
import html, json, os, re, sys, time, urllib.request

DATA, OUT = sys.argv[1], sys.argv[2]
FIRST = int(sys.argv[3]) if len(sys.argv) > 3 else None
src = open(DATA, encoding="utf-8").read()
steps = re.findall(r'^  \{name="[^"]*", from=\d+, to=\d+, map=(\d+).*$', src, re.M)
todo, seen = [], set()
lines = re.findall(r'^  \{name="[^"]*", from=\d+, to=\d+, map=(\d+)(.*)$', src, re.M)
order = sorted(lines, key=lambda l: 0 if FIRST and int(l[0]) == FIRST else 1)
for m, rest in order:
    for lst in re.findall(r'(?:quests|pick|turn)=\{([^}]*)\}', rest):
        for q in re.findall(r"\d+", lst):
            if q not in seen:
                seen.add(q); todo.append(int(q))
found = json.load(open(OUT, encoding="utf-8")) if os.path.exists(OUT) else {}
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/130.0"
PIN = re.compile(r'class="qp-pin qp-pin-(\w+)"[^>]*aria-label="([^"]*)"')
for q in todo:
    if str(q) in found: continue
    rec = {"map": None, "start": None, "end": None}
    try:
        req = urllib.request.Request(f"https://foreverchanges.pro/quest/{q}", headers={"User-Agent": UA, "Accept": "text/html"})
        page = urllib.request.urlopen(req, timeout=25).read().decode("utf-8", "replace")
        mm = re.search(r'/quests/maps/(\d+)\.webp', page)
        if mm: rec["map"] = int(mm.group(1))
        for kind, label in PIN.findall(page):
            label = html.unescape(label)
            m = re.match(r"^(Start, End|Start|End):\s*(.*),\s*([\d.]+),\s*([\d.]+)$", label)
            if not m: continue
            who, name, x, y = m.group(1), m.group(2).strip(), float(m.group(3)), float(m.group(4))
            if "Start" in who and not rec["start"]: rec["start"] = [name, x, y]
            if "End" in who and not rec["end"]: rec["end"] = [name, x, y]
    except Exception as e:
        rec["error"] = str(e)[:100]
        print(q, "error", e, flush=True)
    found[str(q)] = rec
    json.dump(found, open(OUT, "w", encoding="utf-8"), indent=0, ensure_ascii=False)
    time.sleep(1.0)
print(len(todo), "quests;", sum(1 for v in found.values() if v.get("start") or v.get("end")), "with a start or end pin")
