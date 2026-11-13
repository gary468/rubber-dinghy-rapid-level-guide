"""Collect what the addon learned in game (real quest objective counts, flight times) into
tools/learned.json for the route planner. Only facts about the game - never the player's pace.

Usage:  python tools/learn.py "<WoW>/_forever_" tools/learned.json
Reads every character's RubberDinghyRapidLevelGuide saved variables under WTF. Needs `lupa`.
"""
import glob, json, statistics, sys
from lupa import lua51

WOW, OUT = sys.argv[1], sys.argv[2]
counts, flights = {}, []
for path in glob.glob(WOW + r"\WTF\Account\*\*\*\SavedVariables\RubberDinghyRapidLevelGuide.lua"):
    L = lua51.LuaRuntime(unpack_returned_tuples=True)
    try:
        L.execute(open(path, encoding="utf-8", errors="replace").read())
    except Exception:
        continue
    db = L.globals().RubberDinghyDB
    learn = db and db.learn
    if not learn: continue
    for qid, s in (learn.obj or {}).items():
        c = {"m": 0, "i": 0, "o": 0}
        for part in str(s).split(","):
            if not part: continue
            kind, n = part[0], part[1:]
            n = int(n) if n.isdigit() else 1
            if kind == "m": c["m"] += n
            elif kind == "i": c["i"] += n
            elif kind in ("o", "e", "x", "l"): c["o"] += n
        counts[int(qid)] = c
    for i in range(1, len(learn.fl or {}) + 1):
        fl = learn.fl[i]
        if fl and fl.s: flights.append(int(fl.s))

out = {"counts": counts}
if len(flights) >= 3:
    out["flight_s"] = statistics.median(flights)
json.dump(out, open(OUT, "w"), indent=1)
print(f"learned: {len(counts)} quests' objective counts, {len(flights)} flights"
      + (f" (median {out['flight_s']:.0f} s)" if "flight_s" in out else ""))
