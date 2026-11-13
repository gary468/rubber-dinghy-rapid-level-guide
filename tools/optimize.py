"""Find the fastest 40-60 route (minutes played) by local search over the order of zones and dungeons.

Usage:  python tools/optimize.py Data.lua "<WoW>/_forever_" tools/qmeta.json OUT.json SEED.json [SEED.json ...] [--minutes N]

A route is an ordered list of stops: a zone visit or a dungeon run. simulate() plays it with the time
model in routelib.py:
  * zone visit: travel there, then every quest open on that map that beats grinding (as they unlock),
    plus riding between their spots; dungeon quests whose giver is here are picked up on the way;
  * dungeon run: group + run time, kill XP inside, and every dungeon quest you can take (fetching
    givers elsewhere costs extra unless you picked them up earlier);
  * whatever XP is still missing at the end is ground at the solo rate.
The search starts from the seed routes and keeps any change that saves time: drop a stop, move a
stop, add a zone or dungeon run anywhere. It writes the best route as a plan for gen_route.py.
"""
import json, random, sys, time
import routelib as R

args = [a for i, a in enumerate(sys.argv[1:], 1) if not a.startswith("--") and sys.argv[i - 1] not in ("--minutes", "--force", "--objective")]
# --objective travel (default): XP against location only - least riding/flying/boating to reach 60 on
#   quest XP; how long quests and kills take is ignored (every quest that isn't grey is done).
# --objective time: the full time model (quest objectives, kill times, dungeon runs, grinding).
OBJECTIVE = sys.argv[sys.argv.index("--objective") + 1] if "--objective" in sys.argv else "travel"
TRAVEL = OBJECTIVE == "travel"
DATA, WOW, QMETA, OUT = args[:4]
SEEDS = args[4:]
MINUTES = float(sys.argv[sys.argv.index("--minutes") + 1]) if "--minutes" in sys.argv else 8
# --force "Sunken Temple,Maraudon": dungeons the route must include (any level in their range).
FORCE = set(n.strip() for n in sys.argv[sys.argv.index("--force") + 1].split(",")) if "--force" in sys.argv else set()
steps, quests, track, base = R.load(DATA, WOW)
meta = {int(k): v for k, v in json.load(open(QMETA)).items()}
import os as _os
_learned = R.apply_learned(meta, _os.path.join(_os.path.dirname(_os.path.abspath(QMETA)), "learned.json"))
if _learned: print(f"using {_learned} real objective counts learned in game", flush=True)
dungeons = {d["name"]: d for d in R.load_dungeons(WOW)}
WORTH_LEVELS = 9
ALL_ALLIANCE = 1 | 4 | 8 | 64

names = R.map_names(WOW, steps)
dq = {q for d in dungeons.values() for q in d["quests"] if q in quests}
home, points = {}, {}
for qid, q in quests.items():
    if q.get("rep") or q.get("cl") or qid in dq or q.get("d"): continue
    if q.get("ra") and (q["ra"] & ALL_ALLIANCE) != ALL_ALLIANCE: continue
    if qid not in base or base[qid][1] <= 0: continue
    g, o, t = R.loc(q.get("g")), R.loc(q.get("o")), R.loc(q.get("t"))
    if not g: continue
    h = (o or t or g)[0]
    if R.continent(h) == "?": continue
    home[qid] = h
    points[qid] = [p for p in (g, o, t) if p and p[0] == h]
by_map = {}
for qid, m in home.items(): by_map.setdefault(m, []).append(qid)
for m in by_map: by_map[m].sort(key=lambda i: (quests[i].get("l") or 0, i))
dpick = {}
for qid in dq:
    g = R.loc(quests[qid].get("g"))
    if g: dpick.setdefault(g[0], []).append(qid)
ZONES = sorted(by_map)
GRIND = {lv: R.grind_xph(lv) for lv in range(1, 61)}

# Quest chains. A quest given on one map but done on another (breadcrumbs, capital lead-ins) can
# only be done once you've been to its giver: it's picked up there ("held") on an earlier stop.
gmap = {}
for qid in home:
    g = R.loc(quests[qid].get("g"))
    gmap[qid] = g[0] if g else home[qid]
opick = {}
for qid, m in home.items():
    if gmap[qid] != m: opick.setdefault(gmap[qid], []).append(qid)
# Follow-ups: a quest is worth its own XP plus the chain it opens (follow-ups, their follow-ups...).
followers = {}
for qid, q in quests.items():
    if qid not in home and qid not in dq: continue
    for p in (q.get("pg") or []) + (q.get("ps") or []):
        if isinstance(p, int) and p > 0: followers.setdefault(p, []).append(qid)
_chain = {}


def chain_value(qid, lv, depth=0):
    """(xp, seconds) for doing this quest and the chain of follow-ups it opens, at level lv."""
    key = (qid, lv)
    if key in _chain: return _chain[key]
    if qid in dq:
        xp, secs = R.quest_xp(base, qid, lv), R.TURNIN_S        # done inside a dungeon run
    else:
        secs, kxp = R.quest_cost(meta.get(qid), lv)
        xp = R.quest_xp(base, qid, lv) + kxp
    if depth < 6:
        for f in followers.get(qid, ()):
            fx, fs = chain_value(f, lv, depth + 1)
            if fx * 3600 >= GRIND[lv] * fs:                        # only follow-ups worth doing count
                xp, secs = xp + fx, secs + fs
    _chain[key] = (xp, secs)
    return xp, secs


# Stops the search can add: zones with quests, plus places that only hand out quests (capitals).
ZONES = sorted(m for m in set(by_map) | set(opick) | set(dpick) if R.continent(m) != "?")


def worth(qid, lv):
    x, s = chain_value(qid, lv)
    return x * 3600 >= GRIND[lv] * s


def level_up(lv, xp):
    while lv < 60 and xp >= R.level_xp(lv):
        xp -= R.level_xp(lv); lv += 1
    return lv, xp


def simulate(route, record=False):
    """route: [("zone", map) | ("dungeon", name)] -> (hours, plan entries if record)."""
    lv, xp, done, held, ran, cur, secs_total = 40, 0, set(), set(), set(), None, 0.0
    plan = []
    for kind, key in route:
        if lv >= 60: break
        if kind == "zone":
            m = key
            secs, did, pts, lv_in, gain = R.hop_s(cur, m) + R.VISIT_S, [], [], lv, 0
            progressed = True
            while progressed:
                progressed = False
                for qid in by_map.get(m, ()):
                    if qid in done: continue
                    if gmap[qid] != m and qid not in held: continue   # its giver is elsewhere: not picked up
                    q = quests[qid]
                    if (q.get("l") or 0) < lv - WORTH_LEVELS or not R.available(q, done, lv, allow_class=False): continue
                    if not TRAVEL and not worth(qid, lv): continue      # grinding beats this quest and its chain
                    s, kxp = R.quest_cost(meta.get(qid), lv)
                    if TRAVEL: s = 0                                     # only getting there counts
                    g = R.quest_xp(base, qid, lv) + kxp
                    done.add(qid); did.append(qid); secs += s; gain += g; xp += g; progressed = True
                    pts += points[qid]
                    lv, xp = level_up(lv, xp)
            # Pick up here what's done elsewhere: dungeon quests, and quests (breadcrumbs, lead-ins)
            # whose giver is here but whose work is on another map - if they or their chain are worth it.
            pick = [q for q in dpick.get(m, ()) if q not in held and q not in done
                    and R.available(quests[q], done, lv, allow_class=False, dungeon=True)]
            pick += [q for q in opick.get(m, ()) if q not in held and q not in done
                     and R.available(quests[q], done, lv, allow_class=False) and (TRAVEL or worth(q, lv))]
            if not did and not pick: continue                       # nothing to do: the stop is skipped
            held.update(pick)
            secs += R.tour(pts) / R.SPEED + 30 * len(pick)
            if record:
                plan.append(dict(kind="zone", map=m, name=names.get(m, f"map {m}"), lv_in=lv_in, lv_out=lv,
                                 quests=did, pick=pick, xp=gain, secs=round(secs)))
            cur = m
        else:
            d = dungeons[key]
            lo_ok = (d["lo"] <= lv <= d["hi"]) if key in FORCE else (d["lo"] + 2 <= lv <= d["hi"] - 1)
            if key in ran or not lo_ok: continue
            qs, fetch = [], set()
            for qid in d["quests"]:
                q = quests.get(qid)
                if not q or qid in done or qid not in base: continue
                if q.get("ra") and (q["ra"] & ALL_ALLIANCE) != ALL_ALLIANCE: continue
                if not R.available(q, done | set(qs), lv, allow_class=False, dungeon=True): continue
                if R.quest_xp(base, qid, lv) <= 0: continue
                qs.append(qid)
                g = R.loc(q.get("g"))
                if qid not in held and g and g[0] != d["entrance"][1]: fetch.add(g[0])
            run_s = d["run_s"]
            secs = R.hop_s(cur, d["entrance"][1]) + R.GROUP_S + run_s + len(fetch) * R.CITY_PICKUP_S + len(qs) * R.TURNIN_S
            gain = sum(R.quest_xp(base, q, lv) for q in qs) + int(GRIND[lv] * d["kill_rate"] * run_s / 3600)
            lv_in = lv
            xp += gain; done.update(qs); ran.add(key)
            lv, xp = level_up(lv, xp)
            if record:
                plan.append(dict(kind="dungeon", map=d["entrance"][1], name=key, dj=d["dj"], entrance=list(d["entrance"]),
                                 lv_in=lv_in, lv_out=lv, quests=qs, xp=gain, secs=round(secs),
                                 all=[q for q in d["quests"] if q in quests]))
            cur = d["entrance"][1]
        secs_total += secs
    if FORCE - ran: secs_total += 100 * 3600 * len(FORCE - ran)     # a required dungeon was missed
    while lv < 60:
        s = (R.level_xp(lv) - xp) / GRIND[lv] * 3600
        if record:
            plan.append(dict(kind="grind", map=cur, name=names.get(cur, "here"), lv_in=lv, lv_out=lv + 1, quests=[],
                             xp=R.level_xp(lv) - xp, secs=round(s)))
        secs_total += s; xp = 0; lv += 1
    if record:   # keep only pick-ups a later stop actually does (no quests left sitting in the log)
        did_all = {q for v in plan for q in v["quests"]}
        for v in plan:
            if v.get("pick"): v["pick"] = [q for q in v["pick"] if q in did_all]
    return secs_total / 3600, plan


def route_of(plan):
    out = []
    for v in plan:
        if v.get("kind") == "grind" or not v.get("map"): continue
        if v.get("kind") == "dungeon": out.append(("dungeon", v["name"]))
        else: out.append(("zone", v["map"]))
    return out


def compact(route):
    """Drop stops that do nothing, keeping the time the same."""
    _, plan = simulate(route, record=True)
    return route_of(plan)


def search(route, deadline, rng):
    best = simulate(route)[0]
    # travel objective: no dungeons in the route unless asked for (--force); they're optional steps
    stops = [("zone", m) for m in ZONES] + [("dungeon", n) for n in dungeons if not TRAVEL or n in FORCE]
    improved = True
    while improved and time.time() < deadline:
        improved = False
        moves = []
        n = len(route)
        moves += [("del", i) for i in range(n)]
        moves += [("mv", i, j) for i in range(n) for j in range(n + 1) if j not in (i, i + 1) and abs(i - j) <= 12]
        moves += [("ins", s, j) for s in stops for j in range(n + 1)]
        rng.shuffle(moves)
        for mv in moves:
            if time.time() > deadline: break
            r = list(route)
            if mv[0] == "del": del r[mv[1]]
            elif mv[0] == "mv":
                x = r.pop(mv[1]); r.insert(mv[2] if mv[2] < mv[1] else mv[2] - 1, x)
            else: r.insert(mv[2], mv[1])
            h = simulate(r)[0]
            if h < best - 1e-6:
                best, route, improved = h, compact(r), True
                print(f"  {best:.2f} h  ({mv[0]}, {len(route)} stops)", flush=True)
                break
    return best, route


rng = random.Random(7)
results = []
for sp in SEEDS:
    seed = route_of(json.load(open(sp)))
    if TRAVEL: seed = [x for x in seed if x[0] != "dungeon" or x[1] in FORCE]
    seed = compact(seed)
    for name in FORCE:                       # put each required dungeon where it costs least
        if ("dungeon", name) in seed: continue
        seed = min((seed[:j] + [("dungeon", name)] + seed[j:] for j in range(len(seed) + 1)), key=lambda r: simulate(r)[0])
    h0 = simulate(seed)[0]
    print(f"seed {sp.split(chr(92))[-1]}: {h0:.2f} h, {len(seed)} stops", flush=True)
    h, r = search(seed, time.time() + MINUTES * 60 / len(SEEDS), rng)
    results.append((h, r, sp))
h, route, sp = min(results)
hours, plan = simulate(route, record=True)
# Every other dungeon becomes an optional step (off until the player ticks it), at the point in this
# route where adding it costs least time.
for name, d in dungeons.items():
    if ("dungeon", name) in route or d["hi"] < 42 or not d["quests"]: continue
    FORCE.add(name)
    tries = [route[:j] + [("dungeon", name)] + route[j:] for j in range(len(route) + 1)]
    best_r = min(tries, key=lambda r: simulate(r)[0])
    h2, p2 = simulate(best_r, record=True)
    FORCE.discard(name)
    entry = next((v for v in p2 if v["kind"] == "dungeon" and v["name"] == name), None)
    if not entry: continue
    entry["optional"] = True
    entry["cost_min"] = max(0, round((h2 - hours) * 60))
    at = len(plan)
    for i, v in enumerate(plan):
        if v["lv_in"] > entry["lv_in"]: at = i; break
    plan.insert(at, entry)
    print(f"  optional: {name} at {entry['lv_in']} ({h2 - hours:+.2f} h if added)", flush=True)
json.dump(plan, open(OUT, "w"), indent=1)
core = [p for p in plan if not p.get("optional")]
kinds = {k: sum(p["secs"] for p in core if p["kind"] == k) / 3600 for k in ("zone", "dungeon", "grind")}
print(f"\nBEST {hours:.2f} h (from {sp.split(chr(92))[-1]}): questing {kinds['zone']:.1f} h, "
      f"dungeons {kinds['dungeon']:.1f} h ({sum(1 for p in core if p['kind'] == 'dungeon')} runs: "
      f"{', '.join(p['name'] for p in core if p['kind'] == 'dungeon')}), grinding {kinds['grind']:.1f} h; "
      f"{sum(len(p['quests']) for p in plan)} quests, {sum(1 for p in plan if p['kind'] == 'zone')} zone visits")
