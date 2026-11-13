"""Route planner: the fastest 40-60, in minutes, from Questie's data and the dungeon journal.

Usage:  python tools/plan_route.py Data.lua "<WoW>/_forever_" tools/plan.json [tools/qmeta.json]

One goal: the fewest minutes to 60. Every option is timed with the model in routelib.py:
  * a zone visit: getting there (flight/boat), riding between its quest spots, and doing each quest
    (objective kills/objects + accepting and handing in), for its quest XP plus the kill XP;
  * a dungeon run: finding a group, the run itself and fetching its quests, for its quest XP plus the
    kill XP inside;
  * grinding: solo kill XP per hour at your level.
At each point the planner takes the option with the most XP per minute. A quest is only taken if it
beats grinding on its own (so slow, low-XP quests are dropped). Dungeon quests whose giver is in a
zone you visit are picked up then, at no extra cost. gen_route.py turns plan.json into the route.
"""
import json, os, re, sys
import routelib as R
import os as _os_start
START_LEVEL = int(_os_start.environ.get("START_LEVEL", 30))   # the route runs START_LEVEL-60

DATA, WOW, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
QMETA = sys.argv[4] if len(sys.argv) > 4 else os.path.join(os.path.dirname(OUT), "qmeta.json")
steps, quests, track, base = R.load(DATA, WOW)
meta = {int(k): v for k, v in json.load(open(QMETA)).items()}
import os as _os
_learned = R.apply_learned(meta, _os.path.join(_os.path.dirname(_os.path.abspath(QMETA)), "learned.json"))
if _learned: print(f"using {_learned} real objective counts learned in game", flush=True)
DUNGEONS_ON = os.environ.get("DUNGEONS", "1") == "1"
dungeons = R.load_dungeons(WOW) if DUNGEONS_ON else []
WORTH_LEVELS = 9               # never consider quests this far below you

# map names: route step names, plus lookups from Questie's zone tables
names = {s["map"]: s["name"] for s in steps}
zone_names, area_map = {}, {}
for m in re.finditer(r'\[(-?\d+)\]\s*=\s*"([^"]+)"', open(WOW + r"\Interface\AddOns\Questie\Localization\lookups\lookupZones.lua", encoding="utf-8", errors="replace").read()):
    zone_names.setdefault(int(m.group(1)), m.group(2))
for m in re.finditer(r"\[(\d+)\]\s*=\s*(\d+)", open(WOW + r"\Interface\AddOns\QuestieDB\support\Forever\Zones\areaIdToUiMapId.lua", encoding="utf-8").read()):
    area_map.setdefault(int(m.group(1)), int(m.group(2)))
for area, m in area_map.items():
    if m not in names and area in zone_names: names[m] = zone_names[area]

# Dungeon quests (from the journal, plus Questie's own dungeon flag) are only done in dungeon runs.
dq_of = {}
for d in dungeons:
    for q in d["quests"]:
        if q in quests: dq_of.setdefault(q, d["name"])
dun_by_name = {d["name"]: d for d in dungeons}

# Plannable open-world quests: Alliance-wide (no class/race lock), not repeatable, a real giver, has XP.
ALL_ALLIANCE = 1 | 4 | 8 | 64
home, points = {}, {}
for qid, q in quests.items():
    if q.get("rep") or q.get("cl") or qid in dq_of or q.get("d"): continue
    if q.get("ra") and (q["ra"] & ALL_ALLIANCE) != ALL_ALLIANCE: continue
    if qid not in base or base[qid][1] <= 0: continue
    g, o, t = R.loc(q.get("g")), R.loc(q.get("o")), R.loc(q.get("t"))
    if not g: continue
    h = (o or t or g)[0]
    home[qid] = h
    points[qid] = [p for p in (g, o, t) if p and p[0] == h]
by_map = {}
for qid, m in home.items(): by_map.setdefault(m, []).append(qid)
UNLOCKS = {p for q in quests.values() for p in (q.get("pg") or []) + (q.get("ps") or []) if isinstance(p, int) and p > 0}
# Dungeon quests by the map their giver stands on (picked up when you're there anyway).
dpick_by_map = {}
for qid in dq_of:
    g = R.loc(quests[qid].get("g"))
    if g: dpick_by_map.setdefault(g[0], []).append(qid)


def qvalue(qid, lv):
    """(xp incl. kill XP, seconds) for doing one quest at level lv."""
    secs, kxp = R.quest_cost(meta.get(qid), lv)
    return R.quest_xp(base, qid, lv) + kxp, secs


def level_up(lv, xp):
    while lv < 60 and xp >= R.level_xp(lv):
        xp -= R.level_xp(lv); lv += 1
    return lv, xp


def visit(m, lv, xp, done):
    """Do every quest on map m that beats grinding, in level order, as they unlock."""
    done = set(done); did, gain, secs, pts = [], 0, R.VISIT_S, []
    progressed = True
    while progressed:
        progressed = False
        for qid in sorted(by_map.get(m, []), key=lambda i: quests[i].get("l") or 0):
            q = quests[qid]
            if qid in done or not R.available(q, done, lv, allow_class=False): continue
            if (q.get("l") or 0) < lv - WORTH_LEVELS: continue
            g, s = qvalue(qid, lv)
            if qid not in UNLOCKS and g / s * 3600 < R.grind_xph(lv): continue   # grinding is faster
            done.add(qid); did.append(qid); gain += g; secs += s; xp += g; progressed = True
            pts += points[qid]
            lv, xp = level_up(lv, xp)
    secs += R.tour(pts) / R.SPEED
    return gain, secs, lv, xp, did


def dungeon_run(d, lv, xp, done, held):
    """One run of dungeon d now: quests you hold or can fetch, plus kill XP inside."""
    if not (d["lo"] + 2 <= lv <= d["hi"] - 1) or d["name"] in ran: return None
    qs, fetch_maps = [], set()
    for qid in d["quests"]:
        q = quests.get(qid)
        if not q or qid in done or qid not in base: continue
        if not R.available(q, done | set(qs), lv, allow_class=False, dungeon=True): continue
        if q.get("ra") and (q["ra"] & ALL_ALLIANCE) != ALL_ALLIANCE: continue
        if R.quest_xp(base, qid, lv) <= 0: continue
        qs.append(qid)
        g = R.loc(q.get("g"))
        if qid not in held and g and g[0] != d["entrance"][1]: fetch_maps.add(g[0])
    run_s = d["run_s"]
    secs = R.GROUP_S + run_s + len(fetch_maps) * R.CITY_PICKUP_S + len(qs) * R.TURNIN_S
    gain = sum(R.quest_xp(base, q, lv) for q in qs) + int(R.grind_xph(lv) * d["kill_rate"] * run_s / 3600)
    nlv, nxp = level_up(lv, xp + gain)
    return gain, secs, nlv, nxp, qs


lv, xp, done, held, ran, cur, plan, clock = START_LEVEL, 0, set(), set(), set(), None, [], 0.0
while lv < 60:
    best = None   # (xp per hour, kind, payload)
    for m in by_map:
        if R.continent(m) == "?": continue
        gain, secs, nlv, nxp, did = visit(m, lv, xp, done)
        if not did: continue
        secs += R.hop_s(cur, m)
        rate = gain / secs * 3600
        if not best or rate > best[0]: best = (rate, "zone", (m, gain, secs, nlv, nxp, did))
    for d in dungeons:
        r = dungeon_run(d, lv, xp, done, held)
        if not r or not r[4]: continue
        gain, secs, nlv, nxp, qs = r
        secs += R.hop_s(cur, d["entrance"][1])
        rate = gain / secs * 3600
        if not best or rate > best[0]: best = (rate, "dungeon", (d, gain, secs, nlv, nxp, qs))
    if not best or best[0] < R.grind_xph(lv):
        need = R.level_xp(lv) - xp
        secs = need / R.grind_xph(lv) * 3600
        plan.append(dict(kind="grind", map=cur, name=names.get(cur, "here"), lv_in=lv, lv_out=lv + 1, quests=[],
                         xp=need, secs=round(secs), rate=round(R.grind_xph(lv))))
        clock += secs; lv, xp = lv + 1, 0
        continue
    rate, kind, p = best
    if kind == "zone":
        m, gain, secs, nlv, nxp, did = p
        # Dungeon quests whose giver is here: pick them up now for a later run (if you can take them).
        pick = [q for q in dpick_by_map.get(m, []) if q not in held and q not in done
                and R.available(quests[q], done | set(did), nlv, allow_class=False, dungeon=True)]
        secs += 30 * len(pick)
        held.update(pick)
        plan.append(dict(kind="zone", map=m, name=names.get(m, f"map {m}"), lv_in=lv, lv_out=nlv, quests=did,
                         pick=pick, xp=gain, secs=round(secs), rate=round(rate)))
        lv, xp, cur = nlv, nxp, m
        done.update(did)
    else:
        d, gain, secs, nlv, nxp, qs = p
        ran.add(d["name"])
        plan.append(dict(kind="dungeon", map=d["entrance"][1], name=d["name"], dj=d["dj"], entrance=list(d["entrance"]),
                         lv_in=lv, lv_out=nlv, quests=qs, xp=gain, secs=round(secs), rate=round(rate)))
        lv, xp, cur = nlv, nxp, d["entrance"][1]
        done.update(qs)
    clock += secs

json.dump(plan, open(OUT, "w"), indent=1)
print(f"{'#':>2} {'kind':7} {'where':26} {'lv':>7} {'q':>3} {'xp':>8} {'min':>5} {'xp/h':>7}")
for i, p in enumerate(plan, 1):
    print(f"{i:>2} {p['kind']:7} {p['name'][:26]:26} {str(p['lv_in']) + '->' + str(p['lv_out']):>7} "
          f"{len(p['quests']):>3} {p['xp']:>8,} {round(p['secs'] / 60):>5} {p['rate']:>7,}")
kinds = {k: sum(p["secs"] for p in plan if p["kind"] == k) / 3600 for k in ("zone", "dungeon", "grind")}
print(f"\nLevel 60 in {clock / 3600:.1f} h played: questing {kinds['zone']:.1f} h, dungeons {kinds['dungeon']:.1f} h "
      f"({sum(1 for p in plan if p['kind'] == 'dungeon')} runs), grinding {kinds['grind']:.1f} h. "
      f"{sum(len(p['quests']) for p in plan)} quests, {sum(1 for p in plan if p['kind'] == 'zone')} zone visits.")
