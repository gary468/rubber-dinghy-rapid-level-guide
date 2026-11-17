"""Route v2: plan every action - accept, objectives, hand-in - in the order that reaches level 60 in
the least time played, with real travel (tools/travel.py: the game's geography, flights, boats).

Usage:  python tools/plan_v2.py Data.lua "<WoW>/_forever_" tools/qmeta.json tools/plan.json OUT.json [--minutes N]

The route is one list of actions. simulate() plays it: travel to each place, the time each action
takes (kills x kill time, objects, accept/hand-in), quest XP and kill XP, levelling, quest chains,
level requirements and the 40-quest log. Actions that can't be done at their point (too low, log full,
prerequisite missing) are skipped, and so is the rest of that quest. Whatever XP is missing at the end
is ground at the solo rate.

Start: the current zone order (plan.json), every quest's actions laid out zone by zone, with
pick-ups and hand-ins in other zones put where they cost the least extra travel. Then a local search
keeps any change that saves time: move an action (a pick-up to where you pass anyway), drop a quest
that's slower than grinding, add a quest from anywhere at its cheapest spots.
"""
import json, math, os, random, sys, time
import routelib as R
import travel as T

args = [a for i, a in enumerate(sys.argv[1:], 1) if not a.startswith("--") and sys.argv[i - 1] not in ("--minutes", "--from")]
DATA, WOW, QMETA, PLAN, OUT = args[:5]
MINUTES = float(sys.argv[sys.argv.index("--minutes") + 1]) if "--minutes" in sys.argv else 10
START_LEVEL = int(os.environ.get("START_LEVEL", 10))
# A starting zone's route (level 1 to UNTIL_LEVEL): RACE = that race's bit, MAPS = the only maps whose
# quests it may use (the starting zone and its capital). The main route: MAPS_EXCLUDE = the starting
# zones, so nobody is sent to another race's start.
TARGET = int(os.environ.get("UNTIL_LEVEL", 60))
MAPS = {int(m) for m in os.environ.get("MAPS", "").split(",") if m.strip()}
MAPS_EXCLUDE = {int(m) for m in os.environ.get("MAPS_EXCLUDE", "").split(",") if m.strip()}
if os.environ.get("RACE"): R.RACE = int(os.environ["RACE"])
NO_CLASS = bool(os.environ.get("NO_CLASS"))   # starting zones: leave class quests to the player
LOG_MAX = 40   # Forever's quest log holds 40 (the game shows 26/40); Classic's 20 left good quests out
ACC_S, RET_S = 12, 12                    # talking to the NPC (the walk there is travel)
WINDOW = 60                              # how far an action may move in one step of the search
GRIND_GAP = 2                            # grind at most this many levels to reach a quest
ZONE_SWITCH_S = float(os.environ.get("ZONE_SWITCH_S", 240))   # a new step to read and follow: keeps zones together

steps, quests, track, base = R.load(DATA, WOW)
meta = {int(k): v for k, v in json.load(open(QMETA)).items()}
R.apply_learned(meta, os.path.join(os.path.dirname(os.path.abspath(QMETA)), "learned.json"))
T.load()
old_plan = json.load(open(PLAN))
GRIND = {lv: R.grind_xph(lv) for lv in range(1, 61)}
ALL_ALLIANCE = 1 | 4 | 8 | 64


def place(v):
    if not v or len(v) < 4 or v[1] in (None, 0) or v[2] is None or v[3] is None or v[2] < 0: return None
    return (int(v[1]), float(v[2]), float(v[3]))


# Quests the planner may use: Alliance (any race), not a dungeon's, worth XP, with a giver it can find.
G, O, E = {}, {}, {}
for qid, q in quests.items():
    if q.get("rep") or q.get("d") or qid not in base or base[qid][1] <= 0: continue
    if q.get("ra") and not (q["ra"] & R.RACE): continue
    if q.get("cl") and (NO_CLASS or not (q["cl"] & R.CLASS)): continue
    g, t = place(q.get("g")), place(q.get("t"))
    if not g or not t: continue
    _maps = {g[0], t[0]} | ({place(q.get("o"))[0]} if place(q.get("o")) else set())
    if MAPS and not _maps <= MAPS: continue
    if MAPS_EXCLUDE and _maps & MAPS_EXCLUDE: continue
    if MAPS and (q.get("l") or 0) > TARGET + 2: continue
    G[qid], E[qid] = g, t
    o = place(q.get("o"))
    if o: O[qid] = o
POOL = set(G)

# ---- Objectives split into spawn groups, as the addon does (Core.lua SplitLoc). Gary 17 Nov: The
# Bounty of Nature's stags and tubers are all round Ketharas, but the objective's one spot was the
# centre of every stag on the map, in the north-west - so the planner thought it was a long trip.
# Each objective group's spawns are split where there's open ground between them; the group nearest
# the giver and hand-in is the one you'd use. Several groups close together: their middle.
SPLIT_GAP, SPLIT_MIN, SPLIT_FAR = 8.0, 3, 15.0


def _groups(pts):
    n = len(pts) // 2
    if n < 2 * SPLIT_MIN: return [(sum(pts[0::2]) / max(n, 1), sum(pts[1::2]) / max(n, 1), n)] if n else []
    parent = list(range(n))
    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]; i = parent[i]
        return i
    for i in range(n):
        for j in range(i + 1, n):
            if (pts[2 * i] - pts[2 * j]) ** 2 + (pts[2 * i + 1] - pts[2 * j + 1]) ** 2 <= SPLIT_GAP ** 2:
                parent[find(i)] = find(j)
    by = {}
    for i in range(n): by.setdefault(find(i), []).append(i)
    big = [ix for ix in by.values() if len(ix) >= SPLIT_MIN] or list(by.values())
    return [(sum(pts[2 * i] for i in ix) / len(ix), sum(pts[2 * i + 1] for i in ix) / len(ix), len(ix)) for ix in big]


def _obj_place(q, o):
    Q = quests[q]
    gs = [g[1] for g in (Q.get("om") or []) if isinstance(g, (list, tuple)) and len(g) > 1 and g[1]]
    if not gs:
        raw = Q.get("o")
        if raw and len(raw) > 5 and raw[5]: gs = [raw[5]]
    if not gs: return o
    g0, e0 = G[q], E[q]
    picks = []
    for pts in gs:
        cs = _groups(list(pts))
        if not cs: continue
        def cost(c):
            d = 0.0
            for p in (g0, e0):
                d += math.hypot(c[0] - p[1], c[1] - p[2]) if p[0] == o[0] else 50.0
            return d
        picks.append(min(cs, key=cost))
    if not picks: return o
    if max(math.hypot(a[0] - b[0], a[1] - b[1]) for a in picks for b in picks) > SPLIT_FAR: return o
    w = sum(c[2] for c in picks)
    return (o[0], sum(c[0] * c[2] for c in picks) / w, sum(c[1] * c[2] for c in picks) / w)


for _q, _o in list(O.items()):
    O[_q] = _obj_place(_q, _o)

# ---- Quests the route keeps (tools/overrides.json quests {id: {"keep": true}}): the search never
# drops them, and a chain's earlier quests are kept with them. Gary 16-17 Nov: "STILL dont have
# furbolg quests PLEASE" - every re-plan dropped the Barkskin furbolg chain.
KEEP = set()
try:
    _ov = json.load(open(os.path.join(os.path.dirname(os.path.abspath(QMETA)), "overrides.json"), encoding="utf-8"))
    KEEP = {int(k) for k, v in (_ov.get("quests") or {}).items() if isinstance(v, dict) and v.get("keep")}
except FileNotFoundError:
    pass
_todo = list(KEEP)
while _todo:
    _q = _todo.pop()
    _Q = quests.get(_q) or {}
    for _p in [p for p in (_Q.get("pg") or []) if p > 0] + [p for p in (_Q.get("ps") or []) if p > 0][:1]:
        if _p not in KEEP and _p in POOL:
            KEEP.add(_p); _todo.append(_p)
KEEP &= POOL

_tc = {}
def travel(a, b, lv):
    if a is None or a == b: return 0.0
    k = (a, b, lv >= T.MOUNT_LEVEL)
    v = _tc.get(k)
    if v is None:
        v = _tc[k] = T.travel_s(a, b, lv)
    return v


_cost = {}
def obj_cost(q, lv):
    k = (q, lv)
    v = _cost.get(k)
    if v is None:
        s, kxp = R.quest_cost(meta.get(q), lv)
        v = _cost[k] = (max(0.0, s - R.QUEST_BASE_S), kxp)
    return v


def where(a):
    kind, q = a
    return G[q] if kind == "acc" else O[q] if kind == "obj" else E[q]


def simulate(seq, record=False):
    """-> (hours to 60, records). A record per action actually done: (index, level, time, travel)."""
    t, lv, xp, pos = 0.0, START_LEVEL, 0, None
    done, log, objd = set(), set(), set()
    recs, gained, ground = [], 0, 0.0
    for i, a in enumerate(seq):
        if lv >= TARGET: break
        kind, q = a
        Q = quests[q]
        if kind == "acc":
            if q in log or q in done or len(log) >= LOG_MAX: continue
            if not R.available(Q, done, lv):
                # Only a level or two short (chain done, not excluded)? Grind those levels here, as a
                # player would, instead of dropping the rest of the route.
                need = max(Q.get("r") or 0, (Q.get("l") or 0) - R.MAX_ABOVE)
                if need <= lv or need - lv > GRIND_GAP or not prereqs_met(q, done) \
                        or any(p in done for p in (Q.get("ex") or [])):
                    continue
                while lv < need:
                    g = (R.level_xp(lv) - xp) / GRIND[lv] * 3600
                    t += g; ground += g; gained += R.level_xp(lv) - xp; xp = 0; lv += 1
                if not R.available(Q, done, lv): continue
            p = G[q]; tr = travel(pos, p, lv); t += tr + ACC_S; log.add(q)
        elif kind == "obj":
            if q not in log or q in objd: continue
            p = O[q]; tr = travel(pos, p, lv)
            s, kxp = obj_cost(q, lv)
            t += tr + s; xp += kxp; gained += kxp; objd.add(q)
        else:
            if q not in log or (q in O and q not in objd): continue
            p = E[q]; tr = travel(pos, p, lv); t += tr + RET_S
            qx = R.quest_xp(base, q, lv); xp += qx; gained += qx; log.discard(q); done.add(q)
        if pos is not None and p[0] != pos[0]: t += ZONE_SWITCH_S
        pos = p
        while lv < TARGET and xp >= R.level_xp(lv):
            xp -= R.level_xp(lv); lv += 1
        if record: recs.append((i, lv, t, tr, gained, ground))
    while lv < TARGET:
        t += (R.level_xp(lv) - xp) / GRIND[lv] * 3600; xp = 0; lv += 1
    if MAPS:   # a starting zone: every quest gets done, so one left undone costs an hour (never pays)
        t += 3600 * len({a[1] for a in seq} - done)
    return t / 3600, recs


# --------------------------------------------------------------------------------------------
# First route: the current zone order, quest actions laid out zone by zone
# --------------------------------------------------------------------------------------------
def prereqs_met(q, done):
    """Its chain: every quest in pg handed in, and one of ps (Questie's preQuestGroup/Single)."""
    Q = quests[q]
    if any(p > 0 and p not in done for p in (Q.get("pg") or [])): return False
    ps = [p for p in (Q.get("ps") or []) if p > 0]
    return not ps or any(p in done for p in ps)


def nearest_order(actions, start, done):
    """Order a zone's actions nearest-first from start, keeping accept < objective < hand-in and
    quest chains (a follow-up's accept only after the quests it needs are handed in). done: quests
    handed in before this zone; extended as this zone's hand-ins are placed."""
    out, pos, left = [], start, list(actions)
    while left:
        ready = [a for a in left if not (a[0] == "obj" and ("acc", a[1]) in left)
                 and not (a[0] == "ret" and (("acc", a[1]) in left or ("obj", a[1]) in left))
                 and not (a[0] == "acc" and not prereqs_met(a[1], done))]
        if not ready: ready = left
        a = min(ready, key=lambda a: travel(pos, where(a), 60))
        out.append(a); left.remove(a); pos = where(a)
        if a[0] == "ret": done.add(a[1])
    return out


def build_seed():
    seq, pos, placed, rets = [], None, set(), set()
    late = []          # (action) whose place is in another zone: inserted afterwards
    for v in old_plan:
        if v.get("kind") != "zone" or v.get("optional"): continue
        m = v["map"]
        local = []
        for q in v.get("quests", []) + v.get("pick", []):
            if q not in POOL or q in placed: continue
            placed.add(q)
            acts = [("acc", q)] + ([("obj", q)] if q in O else []) + [("ret", q)]
            for a in acts:
                (local if where(a)[0] == m else late).append(a)
        local = nearest_order(local, pos, rets)
        seq += local
        if local: pos = where(local[-1])
    # Pick-ups and hand-ins in other zones: where they cost the least extra travel, keeping order.
    for a in late:
        insert_cheapest(seq, a)
    return seq


def positions_of(seq, q):
    return {a[0]: i for i, a in enumerate(seq) if a[1] == q}


def insert_cheapest(seq, a, lo=None, hi=None):
    kind, q = a
    idx = positions_of(seq, q)
    if lo is None:
        lo = 0
        if kind == "acc":   # after the hand-ins of the quests it needs
            Q = quests[q]
            need = [p for p in (Q.get("pg") or []) if p > 0]
            ps = [p for p in (Q.get("ps") or []) if p > 0]
            rpos = {b[1]: i for i, b in enumerate(seq) if b[0] == "ret"}
            if need: lo = max([rpos.get(p, len(seq)) + 1 for p in need] + [0])
            if ps: lo = max(lo, min(rpos.get(p, len(seq)) + 1 for p in ps))
            lo = min(lo, len(seq))
        if kind == "obj" and "acc" in idx: lo = idx["acc"] + 1
        if kind == "ret": lo = max(idx.get("acc", -1), idx.get("obj", -1)) + 1
    if hi is None:
        hi = len(seq)
        if kind == "acc": hi = min(idx.get("obj", len(seq)), idx.get("ret", len(seq)))
        if kind == "obj" and "ret" in idx: hi = idx["ret"]
    p = where(a)
    best, bj = float("inf"), hi
    for j in range(lo, hi + 1):
        prev = where(seq[j - 1]) if j > 0 else None
        nxt = where(seq[j]) if j < len(seq) else None
        d = travel(prev, p, 60) + (travel(p, nxt, 60) - travel(prev, nxt, 60) if nxt else 0)
        if d < best: best, bj = d, j
    seq.insert(bj, a)
    return bj


# --------------------------------------------------------------------------------------------
# Local search
# --------------------------------------------------------------------------------------------
def valid_order(seq, q):
    idx = positions_of(seq, q)
    a, o, r = idx.get("acc"), idx.get("obj"), idx.get("ret")
    if a is None or r is None: return False
    if o is not None and not (a < o < r): return False
    return a < r


def search(seq, minutes, rng):
    best, _ = simulate(seq)
    print(f"seed: {best:.2f} h, {len(seq)} actions", flush=True)
    deadline = time.time() + minutes * 60
    tried = 0
    in_seq = {a[1] for a in seq}
    while time.time() < deadline:
        tried += 1
        r = rng.random()
        cand = list(seq)
        if r < 0.35 and cand:                                   # an action to its cheapest valid spot
            i = rng.randrange(len(cand))
            a = cand.pop(i)
            insert_cheapest(cand, a)
            if not valid_order(cand, a[1]): continue
        elif r < 0.70 and cand:                                 # move one action
            i = rng.randrange(len(cand))
            a = cand.pop(i)
            j = max(0, min(len(cand), i + rng.randint(-WINDOW, WINDOW)))
            cand.insert(j, a)
            if not valid_order(cand, a[1]): continue
        elif r < 0.85 and cand and not MAPS:                    # drop a quest (never in a starting zone:
            # you do its quests - nothing else on the route would - so only their order is planned)
            q = rng.choice(cand)[1]
            if q in KEEP: continue                              # overrides.json "keep"
            cand = [a for a in cand if a[1] != q]
        else:                                                   # add a quest at its cheapest spots
            near = [q for q in POOL - in_seq]
            if not near: continue
            q = rng.choice(near)
            for a in [("acc", q)] + ([("obj", q)] if q in O else []) + [("ret", q)]:
                insert_cheapest(cand, a)
        h, _ = simulate(cand)
        if h < best - 1e-6:
            best, seq = h, cand
            in_seq = {a[1] for a in seq}
            print(f"  {best:.2f} h  ({len(seq)} actions, {tried} tried)", flush=True)
    # clean-up: drop actions the simulation skips (quests that never complete)
    _, recs = simulate(seq, record=True)
    done_idx = {r[0] for r in recs}
    kept = [a for i, a in enumerate(seq) if i in done_idx]
    finished = {a[1] for a in kept if a[0] == "ret"}
    seq = [a for a in kept if a[1] in finished]
    return simulate(seq)[0], seq


# --------------------------------------------------------------------------------------------
# Output: zone visits for gen_route.py (consecutive actions on one map), each with its action order
# --------------------------------------------------------------------------------------------
def polish(seq):
    """The walk inside each zone visit, untangled (Gary 15 Nov, Mount Hyjal: the planned path was 18%
    longer than plain nearest-first). For every run of actions on one map: nearest-first from where
    the route enters it (pick-up < objective < hand-in, chains respected), then single moves that
    shorten the walk. A visit's new order is kept only if the whole route gets faster in simulate()."""
    best, _ = simulate(seq)
    i = 0
    while i < len(seq):
        m = where(seq[i])[0]
        j = i
        while j < len(seq) and where(seq[j])[0] == m: j += 1
        if j - i >= 4:
            start = where(seq[i - 1]) if i > 0 else where(seq[i])
            done = {a[1] for a in seq[:i] if a[0] == "ret"}
            seg = nearest_order(seq[i:j], start, set(done))
            segset = set(seg)
            def ok(order):
                seen, dn = set(), set(done)
                for k, q in order:
                    if k == "acc" and not prereqs_met(q, dn): return False
                    if k == "obj" and ("acc", q) in segset and ("acc", q) not in seen: return False
                    if k == "ret" and any((x, q) in segset and (x, q) not in seen for x in ("acc", "obj")): return False
                    seen.add((k, q))
                    if k == "ret": dn.add(q)
                return True
            def walk(order):
                L, pos = 0.0, start
                for a in order:
                    L += travel(pos, where(a), 60); pos = where(a)
                return L
            cur = walk(seg)
            improved, rounds = True, 0
            while improved and rounds < 6:
                improved, rounds = False, rounds + 1
                for k in range(len(seg)):
                    a = seg[k]
                    rest = seg[:k] + seg[k + 1:]
                    for t in range(len(rest) + 1):
                        if t == k: continue
                        cand = rest[:t] + [a] + rest[t:]
                        w = walk(cand)
                        if w < cur - 1e-6 and ok(cand):
                            seg, cur, improved = cand, w, True
                            break
            trial = seq[:i] + seg + seq[j:]
            h, _ = simulate(trial)
            if h < best - 1e-6:
                print(f"  polish map {m}: {best:.3f} -> {h:.3f} h", flush=True)
                best, seq = h, trial
        i = j
    return best, seq


def to_plan(seq):
    h, recs = simulate(seq, record=True)
    by_i = {r[0]: r[1:] for r in recs}
    names = R.map_names(WOW, steps)
    for m, r in T._geo["maps"].items():
        if r.get("name"): names[m] = r["name"]
    out, cur, lv_prev, t_prev, x_prev, g_prev = [], None, START_LEVEL, 0.0, 0, 0.0
    for i, a in enumerate(seq):
        if i not in by_i: continue
        lv, t, tr, gained, ground = by_i[i]
        m = where(a)[0]
        if not cur or cur["map"] != m:
            cur = dict(kind="zone", map=m, name=names.get(m, f"map {m}"), lv_in=lv_prev, lv_out=lv,
                       quests=[], pick=[], turn=[], order=[], xp=0, secs=0)
            out.append(cur)
        kind, q = a
        if kind == "obj" or (kind == "ret" and q not in O and where(("acc", q))[0] == m):
            if q not in cur["quests"]: cur["quests"].append(q)
        if kind == "acc" and (q in O and O[q][0] != m or q not in O and E[q][0] != m):
            cur["pick"].append(q)
        if kind == "ret" and q not in cur["quests"]:
            cur["turn"].append(q)
        if kind == "acc" and q not in cur["pick"] and q not in cur["quests"]:
            cur["quests"].append(q)
        cur["order"].append([kind, q])
        cur["lv_out"] = lv
        cur["secs"] += round(t - t_prev)
        cur["xp"] += int(gained - x_prev)
        cur["grind_s"] = cur.get("grind_s", 0) + round(ground - g_prev)   # levels ground here to unlock quests
        lv_prev, t_prev, x_prev, g_prev = lv, t, gained, ground
    # optional dungeons from the old plan, placed by level (not on a starting zone's route)
    for v in ([] if MAPS else old_plan):
        if not v.get("optional"): continue
        at = len(out)
        for k, z in enumerate(out):
            if z["lv_in"] > v["lv_in"]: at = k; break
        out.insert(at, v)
    return h, out


if __name__ == "__main__":
    rng = random.Random(11)
    if "--from" in sys.argv:   # carry on from an earlier v2 plan's action order
        prev = json.load(open(sys.argv[sys.argv.index("--from") + 1]))
        seed = [tuple(a) for v in prev if v.get("kind") == "zone" for a in v.get("order", [])]
        seed = [a for a in seed if a[1] in POOL]
    elif MAPS:
        qs = sorted(POOL, key=lambda q: (quests[q].get("l") or 0, q))
        acts = [a for q in qs for a in ([("acc", q)] + ([("obj", q)] if q in O else []) + [("ret", q)])]
        seed = nearest_order(acts, G[qs[0]] if qs else None, set())
    else:
        seed = build_seed()
    # quests that have gained an objective place since the starting route was made (Bear Berries,
    # 16 Nov): their objective goes in between pick-up and hand-in, or the hand-in never counts and
    # the whole chain after it falls out (Sweetpaw Jam took the Barkskin furbolg chain with it).
    acts = {}
    for a in seed: acts.setdefault(a[1], set()).add(a[0])
    for q, ks in acts.items():
        if q in O and "obj" not in ks and "acc" in ks and "ret" in ks:
            insert_cheapest(seed, ("obj", q))
    # quests to keep that the starting route doesn't have: in at their cheapest spots, chain order
    have = {a[1] for a in seed}
    for q in sorted(KEEP - have, key=lambda q: (quests[q].get("l") or 0, q)):
        for a in [("acc", q)] + ([("obj", q)] if q in O else []) + [("ret", q)]:
            insert_cheapest(seed, a)
    if KEEP: print(f"keep: {len(KEEP)} quests ({len(KEEP - have)} added to the start)", flush=True)
    h0, _ = simulate(seed)
    best, seq = search(seed, MINUTES, rng)
    best, seq = polish(seq)
    h, plan = to_plan(seq)
    json.dump(plan, open(OUT, "w"), indent=1)
    zones = [p for p in plan if p["kind"] == "zone"]
    print(f"\nBEST {h:.2f} h played to {TARGET} from {START_LEVEL} (seed {h0:.2f} h): {sum(1 for a in seq if a[0] == 'ret')} quests, "
          f"{len(zones)} zone visits, {sum(len(p.get('pick', [])) for p in zones)} pick-ups on the way, "
          f"{sum(len(p.get('turn', [])) for p in zones)} hand-ins on the way")
