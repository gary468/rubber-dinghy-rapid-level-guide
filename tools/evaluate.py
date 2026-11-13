"""Time a plan with the model in routelib.py, so routes can be compared on minutes played.

Usage:  python tools/evaluate.py Data.lua "<WoW>/_forever_" tools/qmeta.json plan1.json [plan2.json ...]

Each visit does the quests it lists that are available at that point (as they unlock), in the
listed order of visits. Dungeon visits add the group/run time and the kill XP inside. Whatever XP
is still missing at the end is ground at the solo rate.
"""
import json, sys
import routelib as R

DATA, WOW, QMETA = sys.argv[1], sys.argv[2], sys.argv[3]
steps, quests, track, base = R.load(DATA, WOW)
meta = {int(k): v for k, v in json.load(open(QMETA)).items()}
dun = {d["name"]: d for d in R.load_dungeons(WOW)}


def evaluate(plan):
    lv, xp, done, cur = 40, 0, set(), None
    t = {"zone": 0.0, "dungeon": 0.0, "grind": 0.0, "hops": 0}
    nq = 0
    for v in plan:
        if lv >= 60: break
        kind = v.get("kind", "zone")
        if kind == "grind":
            # Grind in place up to the planned level, so the quests after it open up as planned.
            while lv < min(60, v["lv_out"]):
                t["grind"] += (R.level_xp(lv) - xp) / R.grind_xph(lv) * 3600
                xp = 0; lv += 1
            continue
        m = v["map"]
        if cur is not None and m != cur: t["hops"] += 1
        hop = R.hop_s(cur, m)
        if kind == "dungeon":
            d = dun.get(v["name"])
            run_s = d["run_s"] if d else R.RUN_BASE_S + R.BOSS_S * 6
            qs = [q for q in v["quests"] if q in quests and q not in done]
            gain = sum(R.quest_xp(base, q, lv) for q in qs) + int(R.grind_xph(lv) * (d["kill_rate"] if d else R.DUNGEON_KILL_RATE) * run_s / 3600)
            secs = hop + R.GROUP_S + run_s + len(qs) * R.TURNIN_S + len(v.get("fetch", [])) * R.CITY_PICKUP_S
            done.update(qs); nq += len(qs)
            xp += gain
            t["dungeon"] += secs
        else:
            secs, pts, left, progressed = hop + R.VISIT_S, [], [q for q in v["quests"] if q in quests], True
            while progressed:
                progressed = False
                for q in list(left):
                    if q in done or not R.available(quests[q], done, lv, allow_class=False, dungeon=True): continue
                    s, kxp = R.quest_cost(meta.get(q), lv)
                    xp += R.quest_xp(base, q, lv) + kxp; secs += s
                    done.add(q); left.remove(q); nq += 1; progressed = True
                    for k in ("g", "o", "t"):
                        l = R.loc(quests[q].get(k))
                        if l and l[0] == m: pts.append(l)
                    while lv < 60 and xp >= R.level_xp(lv): xp -= R.level_xp(lv); lv += 1
            secs += 30 * len(v.get("pick", []))
            t["zone"] += secs + R.tour(pts) / R.SPEED
        while lv < 60 and xp >= R.level_xp(lv): xp -= R.level_xp(lv); lv += 1
        cur = m
    while lv < 60:
        t["grind"] += (R.level_xp(lv) - xp) / R.grind_xph(lv) * 3600
        xp = 0; lv += 1
    total = (t["zone"] + t["dungeon"] + t["grind"]) / 3600
    return total, t, nq


for p in sys.argv[4:]:
    total, t, nq = evaluate(json.load(open(p)))
    print(f"{p.split(chr(92))[-1]:28} {total:5.1f} h  (questing {t['zone'] / 3600:.1f}, dungeons {t['dungeon'] / 3600:.1f}, "
          f"grinding {t['grind'] / 3600:.1f}; {t['hops']} zone changes, {nq} quests)")
