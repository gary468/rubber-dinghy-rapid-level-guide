"""Time-to-60 of the current route (plan.json, played the way the addon plays it today) and the v2 route
(plan_v2.json), on the same clock: plan_v2.py's simulation (real travel, kill/collect time, levels,
chains, the 20-quest log).

The current route as played: each zone's quests nearest-first; anything in another zone (pick-up or
hand-in) is a detour made at the end of that zone, then back.

Usage:  python tools/compare_routes.py Data.lua "<WoW>/_forever_" tools/qmeta.json tools/plan.json tools/plan_v2.json
"""
import json, sys
V2 = sys.argv[5]
sys.argv = [sys.argv[0]] + sys.argv[1:5] + ["NUL", "--minutes", "0"]
src = open(__file__.replace("compare_routes.py", "plan_v2.py"), encoding="utf-8").read()
exec(src.split('if __name__ == "__main__":')[0])


def as_played(plan):
    seq, pos, placed, rets = [], None, set(), set()
    for v in plan:
        if v.get("kind") != "zone" or v.get("optional"): continue
        m, local, away = v["map"], [], []
        for q in v.get("quests", []) + v.get("pick", []):
            if q not in POOL or q in placed: continue
            placed.add(q)
            for a in [("acc", q)] + ([("obj", q)] if q in O else []) + [("ret", q)]:
                (local if where(a)[0] == m else away).append(a)
        local = nearest_order(local, pos, rets)
        seq += local + away            # detours at the end of the zone
        if local: pos = where(local[-1])
    return seq


def from_v2(plan):
    return [tuple(a) for v in plan if v.get("kind") == "zone" for a in v.get("order", [])]


old = json.load(open(PLAN))
h_old, r_old = simulate(as_played(old), record=True)
v2 = json.load(open(V2))
h_new, r_new = simulate(from_v2(v2), record=True)
def quests_done(seq, recs):
    return sum(1 for i, *_ in recs if seq[i][0] == "ret")
print(f"current route, as played: {h_old:6.1f} h to 60 ({quests_done(as_played(old), r_old)} quests)")
print(f"route v2:                 {h_new:6.1f} h to 60 ({quests_done(from_v2(v2), r_new)} quests)")
print(f"saving:                   {h_old - h_new:6.1f} h ({(h_old - h_new) / h_old * 100:.0f}%)")
