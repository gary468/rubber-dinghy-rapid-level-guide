"""Extract the game's geography that Geo.lua saved (zone world rects, flight masters) into
tools/geo.json for the route planner.

Usage:  python tools/geo.py "<WoW>/_forever_" tools/geo.json
Reads every character's RubberDinghyRapidLevelGuide saved variables; the newest build wins. Needs lupa.
"""
import glob, json, sys
from lupa import lua51

WOW, OUT = sys.argv[1], sys.argv[2]
best = None
for path in glob.glob(WOW + r"\WTF\Account\*\*\*\SavedVariables\RubberDinghyRapidLevelGuide.lua"):
    L = lua51.LuaRuntime(unpack_returned_tuples=True)
    try:
        L.execute(open(path, encoding="utf-8", errors="replace").read())
    except Exception:
        continue
    db = L.globals().RubberDinghyDB
    geo = db and db.geo
    if not geo or not geo.maps: continue
    maps = {}
    for m, r in geo.maps.items():
        maps[int(m)] = {"name": r.n, "type": r.t, "parent": r.p, "cont": r.c,
                        "x1": r.x1, "y1": r.y1, "x2": r.x2, "y2": r.y2}
    taxi = []
    for _, n in (geo.taxi or {}).items():
        if n.x is None: continue
        taxi.append({"id": n.id, "name": n.n, "map": n.m, "x": n.x, "y": n.y, "faction": n.f})
    cand = {"build": geo.build, "maps": maps, "taxi": taxi}
    if not best or str(cand["build"]) > str(best["build"]) or len(maps) > len(best["maps"]):
        best = cand
if not best:
    sys.exit("no geography saved yet: /reload in game twice with the addon installed")
json.dump(best, open(OUT, "w", encoding="utf-8"), indent=0)
print(f"geo: build {best['build']}, {len(best['maps'])} maps, {len(best['taxi'])} flight masters")
