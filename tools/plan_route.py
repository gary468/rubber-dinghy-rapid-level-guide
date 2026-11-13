"""Route planner: builds the 40-60 zone order from Questie's data, optimising XP per distance.

Usage:  python tools/plan_route.py Data.lua "<WoW>/_forever_" tools/plan.json

Starting at 40 it repeatedly picks the zone visit with the best (XP gained) / (travel in the zone +
travel to get there), where XP follows Questie's rules (incl. the low-level penalty) plus kill XP
while questing, and chains unlock as quests get done. Zones can be visited more than once (e.g. once
at 46 and again at 55 for the zone's higher quests). gen_route.py turns plan.json into the route.
"""
import json, re, sys
import routelib as R

DATA, WOW, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
steps, quests, track, base = R.load(DATA, WOW)

import os
E = lambda k, d: float(os.environ.get(k, d))
# Travel costs in yard-equivalents: a flight/ride to another zone, a boat/portal to the other continent.
HOP_SAME_CONTINENT, HOP_OTHER_CONTINENT, HOP_UNKNOWN = E("HOP_SAME", 2500), E("HOP_OTHER", 7000), 4000
VISIT_OVERHEAD = E("OVERHEAD", 600)
MIN_GAIN_SHARE = E("MIN_SHARE", 0.25)   # a visit must give at least this share of a level (or MIN_QUESTS quests)
MIN_QUESTS = E("MIN_QUESTS", 6)
RELAX = os.environ.get("RELAX", "1") == "1"   # allow small visits before grinding
WORTH_LEVELS = 7               # skip quests more than this many levels below you (<= 40% XP)

# map names: route step names, plus lookups from Questie's zone tables
names = {s["map"]: s["name"] for s in steps}
zone_names, area_map = {}, {}
for m in re.finditer(r'\[(-?\d+)\]\s*=\s*"([^"]+)"', open(WOW + r"\Interface\AddOns\Questie\Localization\lookups\lookupZones.lua", encoding="utf-8", errors="replace").read()):
    zone_names.setdefault(int(m.group(1)), m.group(2))
for m in re.finditer(r"\[(\d+)\]\s*=\s*(\d+)", open(WOW + r"\Interface\AddOns\QuestieDB\support\Forever\Zones\areaIdToUiMapId.lua", encoding="utf-8").read()):
    area_map.setdefault(int(m.group(1)), int(m.group(2)))
for area, m in area_map.items():
    if m not in names and area in zone_names: names[m] = zone_names[area]

# Plannable quests: Alliance-wide (no class/race lock), not dungeon/repeatable, a real giver, has XP.
ALL_ALLIANCE = 1 | 4 | 8 | 64
home, points = {}, {}
for qid, q in quests.items():
    if q.get("rep") or q.get("d") or q.get("cl"): continue
    if q.get("ra") and (q["ra"] & ALL_ALLIANCE) != ALL_ALLIANCE: continue
    if qid not in base or base[qid][1] <= 0: continue
    g, o, t = R.loc(q.get("g")), R.loc(q.get("o")), R.loc(q.get("t"))
    if not g: continue
    h = (o or t or g)[0]
    home[qid] = h
    points[qid] = [p for p in (g, o, t) if p and p[0] == h]

by_map = {}
for qid, m in home.items(): by_map.setdefault(m, []).append(qid)


def visit(m, lv, xp, done, start=None):
    """Simulate doing everything worthwhile on map m now. Returns (gain, lv, xp, quests, tour)."""
    done = set(done); did, gain, pts = [], 0, []
    progressed = True
    while progressed:
        progressed = False
        for qid in sorted(by_map.get(m, []), key=lambda i: quests[i].get("l") or 0):
            q = quests[qid]
            if qid in done or not R.available(q, done, lv, allow_class=False): continue
            if (q.get("l") or 0) < lv - WORTH_LEVELS: continue
            g = R.quest_xp(base, qid, lv)
            g = int(g * (1 + R.MOB_FACTOR)) if q.get("ob") else g
            done.add(qid); did.append(qid); gain += g; xp += g; progressed = True
            pts += points[qid]
            while lv < 60 and xp >= R.level_xp(lv):
                xp -= R.level_xp(lv); lv += 1
    return gain, lv, xp, did, R.tour(pts, start)


def hop(a, b):
    if a is None or a == b: return 0
    ca, cb = R.continent(a), R.continent(b)
    if "?" in (ca, cb): return HOP_UNKNOWN
    return HOP_SAME_CONTINENT if ca == cb else HOP_OTHER_CONTINENT


def pick(min_share, min_quests):
    best = None
    for m in by_map:
        if R.continent(m) == "?": continue          # instanced/unknown maps aren't open-world zones
        gain, nlv, nxp, did, trav = visit(m, lv, xp, done)
        if not did: continue
        if gain < min_share * R.level_xp(lv) and len(did) < min_quests: continue
        score = gain / (trav + hop(cur, m) + VISIT_OVERHEAD)
        if not best or score > best[0]: best = (score, m, gain, nlv, nxp, did, trav)
    return best


lv, xp, done, cur, plan, grind_total = 40, 0, set(), None, [], 0
while lv < 60:
    # Prefer substantial visits; relax when the world runs dry; grind (mobs/dungeon) as the last resort.
    best = pick(MIN_GAIN_SHARE, MIN_QUESTS) or (RELAX and (pick(0.08, 3) or pick(0, 1))) or None
    if not best:
        need = R.level_xp(lv) - xp
        plan.append(dict(map=cur, name="GRIND / DUNGEON", lv_in=lv, lv_out=lv + 1, quests=[], xp=need,
                         travel=0, hop=0, score=0))
        grind_total += need
        lv, xp = lv + 1, 0
        continue
    score, m, gain, nlv, nxp, did, trav = best
    plan.append(dict(map=m, name=names.get(m, f"map {m}"), lv_in=lv, lv_out=nlv, quests=did, xp=gain,
                     travel=round(trav), hop=hop(cur, m), score=round(score, 2)))
    lv, xp, cur = nlv, nxp, m
    done.update(did)

json.dump(plan, open(OUT, "w"), indent=1)
total_travel = sum(p["travel"] + p["hop"] for p in plan)
print(f"{'#':>2} {'zone':24} {'cont':4} {'lv':>9} {'quests':>6} {'xp':>8} {'travel':>7} {'hop':>5} {'score':>6}")
for i, p in enumerate(plan, 1):
    print(f"{i:>2} {p['name'][:24]:24} {R.continent(p['map']):4} {str(p['lv_in']) + '->' + str(p['lv_out']):>9} "
          f"{len(p['quests']):>6} {p['xp']:>8,} {p['travel']:>7,} {p['hop']:>5} {p['score']:>6}")
print(f"\nReached level {lv}, {len(plan)} visits, {sum(len(p['quests']) for p in plan)} quests, "
      f"est. travel {total_travel:,} yd, grind/dungeon XP needed {grind_total:,} "
      f"({round(grind_total / sum(R.level_xp(l) for l in range(40, 60)) * 100)}% of 40-60)")
