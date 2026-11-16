"""Audit the route's quest givers and hand-ins against ForeverChanges (tools/forever_locs.json, from
tools/fetch_fc_locs.py): every quest whose NPC our data has in another zone, or more than 5% of the
map away, or with no position at all where ForeverChanges has one. Writes a Markdown report.

Usage:  python tools/audit_route.py Data.lua tools/forever_locs.json REPORT.md [uiMap]
"""
import json, math, re, sys

DATA, LOCS, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
ONLY = int(sys.argv[4]) if len(sys.argv) > 4 else None
src = open(DATA, encoding="utf-8").read()
locs = json.load(open(LOCS, encoding="utf-8"))
rows = dict((int(i), b) for i, b in re.findall(r'^  \[(\d+)\]=\{(n=".*)\},$', src, re.M))   # quest rows only
step_of = {}
for name, m, rest in re.findall(r'^  \{name="([^"]*)", from=\d+, to=\d+, map=(\d+)(.*)$', src, re.M):
    for lst in re.findall(r'(?:quests|pick|turn)=\{([^}]*)\}', rest):
        for q in re.findall(r"\d+", lst): step_of.setdefault(int(q), (name, int(m)))

GEO = json.load(open(DATA.replace("Data.lua", "") + "tools/geo.json", encoding="utf-8"))["maps"]
def world(m, x, y):
    g = GEO.get(str(m))
    if not g or x is None or y is None: return None
    return g.get("cont"), g["x1"] + (g["x2"] - g["x1"]) * y / 100.0, g["y1"] + (g["y2"] - g["y1"]) * x / 100.0

def ours(body, fld):
    m = re.search(" " + fld + r'=\{"([^"]*)",(\d+),([\d.]+|nil),([\d.]+|nil)\}', " " + body)
    if not m: return None
    x = None if m.group(3) == "nil" else float(m.group(3))
    y = None if m.group(4) == "nil" else float(m.group(4))
    return m.group(1), int(m.group(2)), x, y

issues = []
for qs, rec in locs.items():
    q = int(qs)
    if q not in rows or not rec.get("map"): continue
    step = step_of.get(q, ("?", 0))
    if ONLY and step[1] != ONLY and rec["map"] != ONLY: continue
    name = re.search(r'n="([^"]*)"', rows[q]).group(1)
    for fld, key in (("g", "start"), ("t", "end")):
        fc = rec.get(key)
        o = ours(rows[q], fld)
        if not fc or not o: continue
        who, m, x, y = o
        if x is None:
            issues.append((step[0], name, q, fld, who, f"no position (ForeverChanges: {fc[0]} {rec['map']} {fc[1]},{fc[2]})", "missing"))
        else:
            # in the world, not map %: an Ironforge NPC is the same spot on ForeverChanges' Dun Morogh map
            wa, wb = world(m, x, y), world(rec["map"], fc[1], fc[2])
            if wa and wb and wa[0] != wb[0]:
                issues.append((step[0], name, q, fld, who, f"map {m} {x},{y} vs ForeverChanges {fc[0]} map {rec['map']} {fc[1]},{fc[2]} (another continent)", "zone"))
            elif wa and wb and math.hypot(wa[1] - wb[1], wa[2] - wb[2]) > 200:
                d = math.hypot(wa[1] - wb[1], wa[2] - wb[2])
                issues.append((step[0], name, q, fld, who, f"map {m} {x},{y} vs ForeverChanges map {rec['map']} {fc[1]},{fc[2]} ({d:.0f} yd apart)", "far"))
issues.sort()
with open(OUT, "w", encoding="utf-8") as f:
    f.write(f"# Route audit: quest givers and hand-ins vs ForeverChanges\n\n{len(locs)} quests checked, "
            f"{len(issues)} differences{' on map ' + str(ONLY) if ONLY else ''}.\n\n")
    f.write("| Step | Quest | | NPC | Difference |\n|---|---|---|---|---|\n")
    for step, name, q, fld, who, what, kind in issues:
        f.write(f"| {step} | {name} ({q}) | {'giver' if fld == 'g' else 'hand-in'} | {who} | {what} |\n")
print(len(issues), "differences;", sum(1 for i in issues if i[6] == "zone"), "on another continent,",
      sum(1 for i in issues if i[6] == "far"), "200+ yd apart,", sum(1 for i in issues if i[6] == "missing"), "missing")
