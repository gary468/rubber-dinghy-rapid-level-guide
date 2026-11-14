"""Step 2 of rebuilding Data.lua: the Rubber Dinghy route (levels 40-60, Alliance) from QuestieDB (Forever).

Usage:  python -I tools/gen_route.py tools "<WoW>/_forever_" Data.lua
Needs data.json from decode.py in the tools dir (quest fields + zone names + blacklist).
Character progress is NOT baked in: the addon checks completion, race and class live in game.
To change the route (zones, order, levels), edit STEPS below and re-run both steps.
"""
import base64, json, math, re, struct, sys

HERE, WOW, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
TOC = WOW + r"\Interface\AddOns\QuestieDB\QuestieDB_Forever.toc"
UIMAP = WOW + r"\Interface\AddOns\QuestieDB\support\Forever\Zones\areaIdToUiMapId.lua"
DUNG = WOW + r"\Interface\AddOns\QuestieDB\support\Forever\Zones\dungeons.lua"

# Ordered route. zones = area IDs whose quest givers belong to the step; extra = quest IDs added by hand.
# Continent hops: EK 40-43 -> boat from Booty Bay -> Kalimdor 43-48 -> EK 48-52 -> Kalimdor 52-55
# -> EK 55-57 -> Kalimdor 57-60.
STEPS = [
    dict(name="Riverglades", lv=(40, 42), zones=[16591], extra=[],
         note="Forever's own zone (Eastern Kingdoms) - the biggest 38-46 quest hub on the server."),
    dict(name="Arathi Highlands", lv=(41, 41), zones=[45, 267, 36], extra=[],
         note="Refuge Pointe, plus the Hillsbrad and Alterac quests next door. Fly from Ironforge/Menethil."),
    dict(name="Badlands", lv=(41, 42), zones=[3], extra=[],
         note="Fly to Thelsamar, then ride east. Uldaman quests start here."),
    dict(name="Zephras Isle", lv=(42, 42), zones=[8, 16593], extra=[],
         note="Forever's reworked Swamp of Sorrows (Eastern Kingdoms)."),
    dict(name="Stranglethorn Vale", lv=(42, 43), zones=[33], extra=[],
         note="Booty Bay. When done, take the Booty Bay boat to Ratchet for Kalimdor."),
    dict(name="Desolace", lv=(43, 43), zones=[405, 17], extra=[],
         note="From Ratchet (Barrens quests on the way) to Nijel's Point. Shen'dralas and Feralas are next door."),
    dict(name="Shen'dralas", lv=(43, 44), zones=[16651], extra=[],
         note="Forever's own zone (Kalimdor)."),
    dict(name="Feralas", lv=(44, 46), zones=[357], extra=[2766],
         note="Feathermoon + the coast. Lord Shalzaru is in the cave on the Isle of Dread (28,70)."),
    dict(name="Tanaris", lv=(46, 48), zones=[440, 400], extra=[351],
         note="Gadgetzan, plus the Shimmering Flats quests in Thousand Needles. Fly in from Feathermoon or Thalanaar."),
    dict(name="The Hinterlands", lv=(48, 49), zones=[47], extra=[485, 3661],
         note="Aerie Peak. Fly from Ironforge. The Wildkin Feathers for Favored of Elune? are on the ground here (hand in at Rut'theran)."),
    dict(name="Blasted Lands", lv=(49, 50), zones=[4], extra=[],
         note="Nethergarde Keep. The Bloodmage quests (51,14) share one set of mobs - do them together."),
    dict(name="Searing Gorge", lv=(50, 51), zones=[51], extra=[4449],
         note="Thorium Point (39,28). Fly from Ironforge."),
    dict(name="Burning Steppes", lv=(51, 52), zones=[46], extra=[],
         note="Morgan's Vigil (85,69). Walk south from Searing Gorge through Blackrock Mountain."),
    dict(name="Un'Goro Crater", lv=(52, 53), zones=[490], extra=[3764, 3789, 3790, 3763],
         note="Marshal's Refuge (44,8). Teleport Darnassus or fly via Gadgetzan."),
    dict(name="Felwood", lv=(53, 54), zones=[361, 493], extra=[7066],
         note="Emerald Sanctuary (51,82). Moonglade is next door - hand in Seed of Life to Keeper Remulos."),
    dict(name="Azshara", lv=(54, 55), zones=[16], extra=[8250, 8251],
         note="Talrendis Point (12,78) - mostly Forever's own quests. Mages: Magecraft (Stormwind) -> Magic Dust."),
    dict(name="Western Plaguelands", lv=(55, 56), zones=[28], extra=[5066, 5090, 5091],
         note="Chillwind Camp. Start with A Call to Arms: The Plaguelands! from a capital."),
    dict(name="Eastern Plaguelands", lv=(56, 57), zones=[139], extra=[],
         note="Light's Hope Chapel."),
    dict(name="Silithus", lv=(57, 58), zones=[1377], extra=[1015, 1019, 1047, 8275],
         note="Cenarion Hold. The New Frontier / Taking Back Silithus lead here."),
    dict(name="Winterspring", lv=(58, 58), zones=[618], extra=[8460, 8461],
         note="Everlook. The Timbermaw tunnel from Felwood is the way in."),
    dict(name="Mount Hyjal", lv=(58, 60), zones=[616], extra=[],
         note="Forever's own zone - 50+ quests at 56-60. Finish here."),
    # 30-40 (the planner decides the order; these only group quests by zone)
    dict(name="Duskwood", lv=(30, 32), zones=[10], extra=[], note="Darkshire."),
    dict(name="Wetlands", lv=(30, 33), zones=[11, 16732], extra=[], note="Menethil Harbor, plus Forever's Excavation Site."),
    dict(name="Dustwallow Marsh", lv=(35, 40), zones=[15], extra=[], note="Theramore Isle."),
    dict(name="Ashenvale", lv=(30, 32), zones=[331], extra=[], note="Astranaar."),
    dict(name="Stonetalon Mountains", lv=(30, 32), zones=[406], extra=[], note="Stonetalon Peak."),
    dict(name="Loch Modan", lv=(30, 30), zones=[38], extra=[], note="Thelsamar."),
    dict(name="Darkshore", lv=(30, 30), zones=[148], extra=[], note="Auberdine."),
    # 20-30
    dict(name="Redridge Mountains", lv=(20, 24), zones=[44], extra=[], note="Lakeshire."),
    dict(name="Westfall", lv=(20, 20), zones=[40], extra=[], note="Sentinel Hill."),
    # 10-20 (starting zones' later quests included)
    dict(name="Elwynn Forest", lv=(10, 12), zones=[12], extra=[], note="Goldshire."),
    dict(name="Dun Morogh", lv=(10, 12), zones=[1], extra=[], note="Kharanos."),
    dict(name="Teldrassil", lv=(10, 12), zones=[141], extra=[], note="Dolanaar."),
]
RAIDS = {2717, 2159, 2677, 1977, 3428, 3429, 3456, 19}
ALLIANCE_RACES = 1 | 4 | 8 | 64


def cbor(b, i=0):
    ib = b[i]; mt = ib >> 5; ai = ib & 31; i += 1
    if ai < 24: val = ai
    elif ai == 24: val = b[i]; i += 1
    elif ai == 25:
        # Half-precision float (coordinates like 27.5 are stored this way) or a 16-bit int.
        if mt == 7: return struct.unpack(">e", b[i:i+2])[0], i + 2
        val = struct.unpack(">H", b[i:i+2])[0]; i += 2
    elif ai == 26:
        if mt == 7: return struct.unpack(">f", b[i:i+4])[0], i + 4
        val = struct.unpack(">I", b[i:i+4])[0]; i += 4
    elif ai == 27:
        if mt == 7: return struct.unpack(">d", b[i:i+8])[0], i + 8
        val = struct.unpack(">Q", b[i:i+8])[0]; i += 8
    else: raise ValueError(ai)
    if mt == 0: return val, i
    if mt == 1: return -1 - val, i
    if mt in (2, 3): return b[i:i+val].decode("utf-8", "replace"), i + val
    if mt == 4:
        a = []
        for _ in range(val): v, i = cbor(b, i); a.append(v)
        return a, i
    if mt == 5:
        dd = {}
        for _ in range(val): k, i = cbor(b, i); v, i = cbor(b, i); dd[k] = v
        return dd, i
    if mt == 7: return {20: False, 21: True}.get(ai), i
    raise ValueError(mt)


meta = {}
with open(TOC, encoding="utf-8", errors="replace") as fh:
    for line in fh:
        if line.startswith("## X-"):
            k, _, v = line[3:].rstrip("\n").partition(": ")
            meta[k] = v


def get(k):
    v = meta.get(k)
    if v is None: return None
    m = re.fullmatch(r"~(\d+)~", v)
    if m: v = "".join(meta[f"{k}-{n}"] for n in range(1, int(m.group(1)) + 1))
    return cbor(base64.b64decode(v))[0]


def pos(v, k):
    """Positional group k (1-based) of a CBOR array-or-sparse-map."""
    if isinstance(v, dict): return v.get(k, v.get(str(k)))
    if isinstance(v, list) and len(v) >= k: return v[k - 1]
    return None


uimap = {}
CANON = {}   # uiMap -> its own zone name ("1435 = Swamp of Sorrows"), from the file's comments
for m in re.finditer(r"\[(\d+)\]\s*=\s*(\d+),?[ \t]*(?:--[ \t]*([^\n]+))?", open(UIMAP, encoding="utf-8").read()):
    uimap.setdefault(int(m.group(1)), int(m.group(2)))
    if m.group(3) and "->" not in m.group(3):   # "Longshore -> Westfall" is a subzone line
        CANON.setdefault(int(m.group(2)), m.group(3).strip())
dungeons = {int(m.group(1)) for m in re.finditer(r'\[(\d+)\]\s*=\s*\{\s*"', open(DUNG, encoding="utf-8").read())}

_cache = {}
# Spawns QuestieDB doesn't have yet (mobs and objects new in Forever), read from Wowhead's Forever
# database into tools/wowhead_spawns.json: {"npc"|"object": {id: {"name", "spawns": {area: [[x,y]]}}}}.
# Only used when QuestieDB has no spawns for that NPC/object.
WH_SPAWNS = {"npc": {}, "object": {}}
try:
    _wh = json.load(open(HERE + r"\wowhead_spawns.json", encoding="utf-8"))
    for _k in ("npc", "object"):
        for _i, _v in (_wh.get(_k) or {}).items():
            WH_SPAWNS[_k][int(_i)] = {"name": _v.get("name"),
                                      "spawns": {int(a): c for a, c in (_v.get("spawns") or {}).items()}}
except FileNotFoundError:
    pass

def ent(kind, i):
    """name, faction, spawns {area: [[x,y],...]} for an NPC or object."""
    if (kind, i) in _cache: return _cache[(kind, i)]
    if kind == "npc":
        row = get(f"X-Npc-{i}-S") or {}; sp = get(f"X-Npc-{i}-7") or {}
        e = dict(name=pos(row, 1), zone=pos(row, 9), fac=pos(row, 13), spawns=sp if isinstance(sp, dict) else {})
    else:
        row = get(f"X-Object-{i}-S") or {}; sp = get(f"X-Object-{i}-4") or {}
        e = dict(name=pos(row, 1), zone=pos(row, 5), fac=None, spawns=sp if isinstance(sp, dict) else {})
    # Spawns QuestieDB doesn't have yet (new in Forever), from Wowhead's Forever database.
    wh = WH_SPAWNS["npc" if kind == "npc" else "object"].get(i)
    if wh and not e["spawns"]:
        e["spawns"] = wh["spawns"]
        e["name"] = e["name"] or wh["name"]
    _cache[(kind, i)] = e
    return e


def pts(e, area=None):
    out = []
    for a, lst in e["spawns"].items():
        if area is not None and a not in area: continue
        for c in lst or []:
            if isinstance(c, list) and len(c) >= 2 and c[0] is not None and c[1] is not None and c[0] >= 0 and c[1] >= 0:
                out.append((a, c[0], c[1]))
    return out


def loc_of(qgivers):
    """First NPC/object of a startedBy/finishedBy field -> dict(name, area, x, y, fac)."""
    for k, kind in ((1, "npc"), (2, "obj")):
        for i in pos(qgivers, k) or []:
            e = ent(kind, i)
            if not e["name"]: continue
            p = pts(e)
            if p: return dict(name=e["name"], area=p[0][0], x=p[0][1], y=p[0][2], fac=e["fac"], id=i if kind == "npc" else None)
            return dict(name=e["name"], area=e["zone"], x=None, y=None, fac=e["fac"], id=i if kind == "npc" else None)
    if pos(qgivers, 3): return dict(name="(item drop)", area=None, x=None, y=None, fac=None)
    return None


def has_objectives(qid):
    obj = get(f"X-Quest-{qid}-10")
    return bool(obj) and any(pos(obj, k) for k in (1, 2, 3, 5))


def objective_area(q, qid, areas):
    """Densest cluster of the quest's mobs/objects/drop sources: inside the step's areas if any are
    there, otherwise wherever they are (the addon then shows the zone name)."""
    return _objective_area(qid, areas) or _objective_area(qid, None)


def _objective_area(qid, areas):
    obj = get(f"X-Quest-{qid}-10")
    if not obj: return None
    sources = []  # (kind, id)
    for c in pos(obj, 1) or []:
        if isinstance(c, list) and c: sources.append(("npc", c[0]))
    for o in pos(obj, 2) or []:
        if isinstance(o, list) and o: sources.append(("obj", o[0]))
    for it in pos(obj, 3) or []:
        if not (isinstance(it, list) and it): continue
        for n in get(f"X-Item-{it[0]}-2") or []: sources.append(("npc", n))
        for o in get(f"X-Item-{it[0]}-3") or []: sources.append(("obj", o))
    for kc in pos(obj, 5) or []:
        if isinstance(kc, list) and kc and isinstance(kc[0], list):
            for n in kc[0]: sources.append(("npc", n))
    best_pts, names = [], []
    for kind, i in sources[:40]:
        e = ent(kind, i)
        p = pts(e, areas)
        if p:
            best_pts += p
            if e["name"] and e["name"] not in names: names.append(e["name"])
    if not best_pts: return None
    all_pts = best_pts
    best_pts = best_pts[:600]
    R = 6.0
    best, bestn = None, -1
    for a, x, y in best_pts:
        n = sum(1 for b, u, v in best_pts if b == a and (u - x) ** 2 + (v - y) ** 2 <= R * R)
        if n > bestn: best, bestn = (a, x, y), n
    a, x, y = best
    near = [(u, v) for b, u, v in best_pts if b == a and (u - x) ** 2 + (v - y) ** 2 <= R * R]
    cx = sum(u for u, _ in near) / len(near); cy = sum(v for _, v in near) / len(near)
    rad = max(2.0, min(10.0, max(math.hypot(u - cx, v - cy) for u, v in near)))
    # The spread: where the mobs/objects actually are across this map, thinned to one point per
    # 2.5% grid cell (max 40). The addon routes to the nearest of these, so a long coastline of
    # elementals counts as "here" wherever you are on it, not only at its centre.
    cells, spread = set(), []
    for b, u, v in all_pts:
        if b != a: continue
        key = (round(u / 2.5), round(v / 2.5))
        if key in cells: continue
        cells.add(key)
        spread.append((u, v))
    if len(spread) > 40:
        step = len(spread) / 40.0
        spread = [spread[int(i * step)] for i in range(40)]
    return dict(name=", ".join(names[:2]), area=a, x=cx, y=cy, r=rad, pts=spread)


d = json.load(open(HERE + r"\data.json", encoding="utf-8"))
Q = {int(k): v for k, v in d["quests"].items()}
black = set(d["blacklist"])


def eligible(qid, q):
    if qid in black: return False
    r = (q.get("requiredRaces") or 0) & 0xFFFF
    if r and not (r & ALLIANCE_RACES): return False
    # Repeatable quests stay in (flagged rep=true): the addon only routes them once they're in your log.
    if q.get("requiredSkill"): return False
    if (q.get("requiredLevel") or 0) > 60: return False
    if (q.get("zoneOrSort") or 0) in RAIDS: return False
    return True


givers = {}
for qid, q in Q.items():
    sb = get(f"X-Quest-{qid}-2")
    givers[qid] = loc_of(sb) if sb else None

steps_out, used = [], {}
for st in STEPS:
    lo, hi = st["lv"]
    ids = []
    for qid, q in Q.items():
        if qid in used or not eligible(qid, q): continue
        lvl = q.get("questLevel") or 0
        # Any quest from this zone's NPCs up to 62 belongs to the step (follow-ups like Zorbin's 55s
        # included); ones far above you just show as "later" in game.
        if not (min(lo - 6, 8) <= lvl <= 62): continue   # the route runs 10-60
        g = givers.get(qid)
        if not g or g["area"] not in st["zones"]: continue
        if g.get("fac") and "A" not in str(g["fac"]): continue
        ids.append(qid)
    for qid in st["extra"]:
        if qid in Q and qid not in ids and qid not in used and eligible(qid, Q[qid]): ids.append(qid)
    for qid in ids: used[qid] = st
    steps_out.append((st, sorted(ids, key=lambda i: (Q[i].get("questLevel") or 0, i))))

# Second pass - quests given out somewhere that isn't a route zone (capitals, neighbouring zones):
# attach each to the step whose zone it sends you to (its mobs/objects, else its hand-in), so
# lead-ins like "The New Frontier" become "pick up in Ironforge" stops of the right step.
# Everything else (item-started quests, no known giver, dungeon quests elsewhere, one-offs) goes in
# the track pool: never suggested, but routed like any other quest once it's in your log.
zone_step = {}
for st, ids in steps_out:
    for z in st["zones"]: zone_step[z] = (st, ids)
track = {}
for qid, q in Q.items():
    if qid in used or not eligible(qid, q): continue
    lvl = q.get("questLevel") or 0
    if not (8 <= lvl <= 62): continue
    g = givers.get(qid)
    if g and g.get("fac") and "A" not in str(g["fac"]): continue
    o = _objective_area(qid, None)
    fb = get(f"X-Quest-{qid}-3")
    t = loc_of(fb) if fb else None
    dest = (o and o["area"]) or (t and t.get("area"))
    target = zone_step.get(dest)
    real_giver = g and g.get("area") and g["name"] != "(item drop)"
    if target and real_giver and lvl >= target[0]["lv"][0] - 6:
        target[1].append(qid)
        used[qid] = target[0]
    else:
        track[qid] = dest

# Plan mode: tools/plan_route.py decided the visit order (zones can be visited more than once).
# Each visit becomes a step with its own quest list; every other quest goes to the track pool.
PLAN = sys.argv[4] if len(sys.argv) > 4 else None
if PLAN:
    import collections
    plan = json.load(open(PLAN, encoding="utf-8"))
    map_areas = collections.defaultdict(set)
    for a, m in uimap.items(): map_areas[m].add(a)
    zone_note = {}
    for st in STEPS:
        # a note belongs to the map whose own name matches the STEPS entry (an entry listing a
        # neighbour's area, e.g. Zephras Isle + Swamp of Sorrows, must not lend its note to it)
        for zid in st["zones"]:
            um = uimap.get(zid)
            if um and CANON.get(um) == st["name"]: zone_note.setdefault(um, st["note"])
    pool = set(used) | set(track)
    seen = collections.Counter()
    new_steps, new_used = [], {}
    zone_name = {int(k): v for k, v in (d.get("zones") or {}).items() if isinstance(v, str)}
    for v in plan:
        if v["name"].startswith("map ") or v["name"] == "here":
            for a in sorted(map_areas.get(v["map"], [])):
                if zone_name.get(a): v["name"] = zone_name[a]; break
        ids = [q for q in v["quests"] if q in Q]
        if v.get("kind") == "dungeon":
            # Every quest for this dungeon: the addon shows the ones you hold or can get, live.
            ids += [q for q in v.get("all", []) if q in Q and q not in ids and eligible(q, Q[q])]
        pick = [q for q in v.get("pick", []) if q in Q]
        turn = [q for q in v.get("turn", []) if q in Q]      # route v2: hand-ins placed here
        m = v["map"]
        if v.get("kind") != "dungeon" and CANON.get(m):
            v["name"] = CANON[m]   # the map's own name (plan names could come from a neighbour)
        lv = (v["lv_in"], max(v["lv_in"], v["lv_out"]))
        if v.get("kind") == "dungeon":
            e = v["entrance"]
            dj = v.get("dj")
            note = (f"Dungeon run: find a group (LFG) and head to the entrance. Hand in what you finish."
                    + (f" Quest pick-ups and maps: Dungeon Journal (/dj {dj})." if dj else ""))
            st = dict(name="Dungeon: " + v["name"], lv=lv, zones=sorted(map_areas.get(m, [])) or [0], map_id=m,
                      note=note, extra=[], dungeon=v["name"], dj=dj, ent=e, optional=bool(v.get("optional")), cost=v.get("cost_min"))
        elif v.get("kind") == "grind":
            # Grinding beats the quests left at this point: a step with no quests, just the advice.
            st = dict(name=f"Grind: {v['name']}", lv=lv, zones=sorted(map_areas.get(m, [])) or [0], map_id=m,
                      note=f"Nothing left here beats killing mobs: grind to level {v['lv_out']} "
                           f"(about {round(v.get('secs', 0) / 60)} min), ideally in a dungeon group.", extra=[], grind=True)
        else:
            if not ids and not pick and not turn: continue
            seen[m] += 1
            note = zone_note.get(m, f"Go to {v['name']}.")
            if not ids and (pick or turn):
                note = "On the way: " + " and ".join(x for x in (
                    "pick up quests for later" if pick else "", "hand in finished quests" if turn else "") if x) + "."
            elif seen[m] > 1: note = "Back for the quests that have opened up at your level. " + note
            if pick and ids: note += " Pick up quests here for later in the route."
            st = dict(name=v["name"] + ("" if seen[m] == 1 else " (return visit)"), lv=lv,
                      zones=sorted(map_areas.get(m, [])) or [0], map_id=m, note=note, extra=[], pick=pick,
                      turn=turn, ord=v.get("order"))
        st["xp"], st["secs"] = int(v.get("xp") or 0), int(v.get("secs") or 0)
        for q in ids: new_used[q] = st
        new_steps.append((st, ids))
    dungeon_quests = {q for st, ids in new_steps if st.get("dungeon") for q in ids}
    old_used = used
    steps_out = new_steps
    track = {q: (track.get(q) if q in track else old_used[q]["zones"][0]) for q in pool if q not in new_used}
    used = new_used
    print("plan mode:", len(steps_out), "visits")
else:
    dungeon_quests = set()


def lstr(s):
    return '"' + str(s).replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ") + '"'

def lloc(e, with_r=False):
    if not e: return "nil"
    m = uimap.get(e["area"] or 0, 0)
    x = "nil" if e.get("x") is None else f"{e['x']:.1f}"
    y = "nil" if e.get("y") is None else f"{e['y']:.1f}"
    extra = f",{e['r']:.1f}" if with_r and e.get("r") else ""
    if with_r and e.get("pts"):
        extra += ",{" + ",".join(f"{u:.0f},{v:.0f}" for u, v in e["pts"]) + "}"
    return "{" + f"{lstr(e['name'])},{m},{x},{y}{extra}" + "}"

def larr(v):
    v = [int(x) for x in (v or []) if isinstance(x, int)]
    return "{" + ",".join(map(str, v)) + "}" if v else "nil"

out = ["-- GENERATED by gen_route.py from QuestieDB (Forever). Do not edit by hand.",
       "-- Quest location fields: {name, uiMapID, x, y[, radius[, {spawn x1,y1, x2,y2, ...}]]}",
       "local _, ns = ...", "ns.steps = {"]
for st, ids in steps_out:
    m = st.get("map_id") or uimap.get(st["zones"][0], 0)
    extra = ""
    if st.get("pick"): extra += f", pick={{{','.join(map(str, st['pick']))}}}"
    if st.get("turn"): extra += f", turn={{{','.join(map(str, st['turn']))}}}"
    if st.get("ord"):   # the planned order of every action: a=accept, o=objectives, r=hand in
        extra += ', ord="' + ",".join({"acc": "a", "obj": "o", "ret": "r"}[k] + str(q) for k, q in st["ord"]) + '"'
    if st.get("dungeon"):
        e = st["ent"]
        extra += f", dungeon={lstr(st['dungeon'])}, ent={{{lstr(e[0])},{e[1]},{e[2]},{e[3]}}}"
        if st.get("dj"): extra += f", dj={lstr(st['dj'])}"
        if st.get("optional"): extra += ", optional=true"
        if st.get("cost") is not None: extra += f", cost={int(st['cost'])}"
    if st.get("grind"): extra += ", grind=true"
    if st.get("xp"): extra += f", xp={st['xp']}, secs={st['secs']}"
    out.append(f"  {{name={lstr(st['name'])}, from={st['lv'][0]}, to={st['lv'][1]}, map={m}, note={lstr(st['note'])}, quests={{{','.join(map(str, ids))}}}{extra}}},")
out.append("}")
out.append("-- Quests only routed once they're in your log (never suggested for pick-up).")
out.append("ns.track = {" + ",".join(map(str, sorted(track))) + "}")
out.append("ns.quests = {")
n_obj = 0
qmeta = {}
# Patrol paths: {npcId: (uiMap, [x1, y1, x2, y2, ...])}, first path only, thinned to <= 40 points.
paths = {}
def npc_path(i):
    if i in paths: return paths[i]
    w = get(f"X-Npc-{i}-8")
    res = None
    if isinstance(w, dict):
        for area, plist in w.items():
            m = uimap.get(int(area))
            if not m or not plist or not isinstance(plist, list): continue
            pts = [p for p in plist[0] if isinstance(p, list) and len(p) >= 2 and p[0] is not None and p[1] is not None]
            if len(pts) < 2: continue
            if len(pts) > 40:
                step = len(pts) / 40.0
                pts = [pts[int(k * step)] for k in range(40)]
            res = (m, pts); break
    paths[i] = res
    return res
obj_npcs = {}   # creature NPC id -> quests that need it killed
# Where objectives are for quests no database places, recorded in game (tools/learn.py ->
# learned.json "spots": {qid: [[uiMap, x, y], ...]}).
try:
    LEARNED_SPOTS = {int(k): v for k, v in (json.load(open(HERE + r"\learned.json", encoding="utf-8")).get("spots") or {}).items()}
except (FileNotFoundError, ValueError):
    LEARNED_SPOTS = {}

def spots_loc(spots, name):
    from collections import Counter
    m = Counter(p[0] for p in spots).most_common(1)[0][0]
    pts = [(p[1], p[2]) for p in spots if p[0] == m]
    cx = sum(x for x, _ in pts) / len(pts); cy = sum(y for _, y in pts) / len(pts)
    rad = max(2.0, min(10.0, max(math.hypot(x - cx, y - cy) for x, y in pts)))
    flat = ",".join(f"{x:.0f},{y:.0f}" for x, y in pts[:40])
    return "{" + f"{lstr(name)},{m},{cx:.1f},{cy:.1f},{rad:.1f}" + (",{" + flat + "}" if len(pts) > 1 else "") + "}"
tip_mob, tip_start, tip_end = {}, {}, {}
for qid in sorted(set(used) | set(track)):
    q = Q[qid]; st = used.get(qid)
    fb = get(f"X-Quest-{qid}-3")
    t = loc_of(fb) if fb else None
    if st: areas = set(st["zones"])
    elif track.get(qid): areas = {track[qid]}
    else: areas = set()
    o = objective_area(q, qid, areas)
    if o: n_obj += 1
    parts = [f"n={lstr(q.get('name'))}", f"l={q.get('questLevel') or 0}", f"r={q.get('requiredLevel') or 0}",
             f"g={lloc(givers.get(qid))}", f"t={lloc(t)}"]
    if o: parts.append(f"o={lloc(o, True)}")
    elif LEARNED_SPOTS.get(qid):
        # no location in any database, but players' recorded where its progress went up (Learn.lua)
        parts.append("o=" + spots_loc(LEARNED_SPOTS[qid], q.get("name") or "Objective"))
    else:
        # no spot for its objectives: keep the quest's own objective text ("...in Wildhammer Keep")
        ot = get(f"X-Quest-{qid}-8")
        if isinstance(ot, list) and ot and isinstance(ot[0], str) and has_objectives(qid):
            parts.append(f"ot={lstr(ot[0][:160])}")
    if has_objectives(qid): parts.append("ob=true")
    if (q.get("specialFlags") or 0) & 1: parts.append("rep=true")
    # Candidate quest items for the tracker's item button (Questie's rule): the item the quest gives
    # you, items it requires, and objective items. The addon shows one only if it's in your bags and
    # has a "Use:" effect.
    items = []
    srow = get(f"X-Quest-{qid}-S") or {}
    src = pos(srow, 11)
    if isinstance(src, int) and src > 0: items.append(src)
    for it in get(f"X-Quest-{qid}-21") or []:
        if isinstance(it, int) and it not in items: items.append(it)
    for it in pos(get(f"X-Quest-{qid}-10") or {}, 3) or []:
        if isinstance(it, list) and it and isinstance(it[0], int) and it[0] not in items: items.append(it[0])
    if items: parts.append("it={" + ",".join(map(str, items)) + "}")
    ra = (q.get("requiredRaces") or 0) & 0xFFFF
    cl = (q.get("requiredClasses") or 0) & 0xFFFF
    if ra: parts.append(f"ra={ra}")
    if cl: parts.append(f"cl={cl}")
    if isinstance(q.get("breadcrumbForQuestId"), int) and q["breadcrumbForQuestId"] > 0:
        parts.append(f"bc={q['breadcrumbForQuestId']}")   # a lead-in: gone once its target is taken
    for key, fld in (("pg", "preQuestGroup"), ("ps", "preQuestSingle"), ("ex", "exclusiveTo")):
        a = larr(q.get(fld))
        if a != "nil": parts.append(f"{key}={a}")
    if (q.get("zoneOrSort") or 0) in dungeons or qid in dungeon_quests: parts.append("d=true")
    # NPCs that walk a patrol: giver, hand-in, and the quest's mobs (keys into ns.paths)
    gid = (givers.get(qid) or {}).get("id"); tid = (t or {}).get("id")
    if gid and npc_path(gid): parts.append(f"gp={gid}")
    if tid and npc_path(tid): parts.append(f"tp={tid}")
    objp = [c[0] for c in (pos(get(f"X-Quest-{qid}-10") or {}, 1) or []) if isinstance(c, list) and c and npc_path(c[0])]
    if objp: parts.append("op={" + ",".join(map(str, objp[:6])) + "}")
    for c in (pos(get(f"X-Quest-{qid}-10") or {}, 1) or []):
        if isinstance(c, list) and c and isinstance(c[0], int): obj_npcs.setdefault(c[0], []).append(qid)
    # For unit tooltips (by NPC ID - Forever hides unit names): mobs to kill or loot, givers, enders.
    for c in (pos(get(f"X-Quest-{qid}-10") or {}, 1) or []):
        if isinstance(c, list) and c and isinstance(c[0], int): tip_mob.setdefault(c[0], set()).add(qid)
    for it in (pos(get(f"X-Quest-{qid}-10") or {}, 3) or []):
        if isinstance(it, list) and it and isinstance(it[0], int):
            for npc in (get(f"X-Item-{it[0]}-2") or [])[:40]:
                if isinstance(npc, int): tip_mob.setdefault(npc, set()).add(qid)
    if gid: tip_start.setdefault(gid, set()).add(qid)
    # Where each objective item comes from (Gary: progress should say what to kill for it):
    # dr={{"Item","Mob A, Mob B, Mob C"}, ...} - up to 3 mobs, else the objects it's picked from.
    drops = []
    for it in (pos(get(f"X-Quest-{qid}-10") or {}, 3) or []):
        if not (isinstance(it, list) and it and isinstance(it[0], int)): continue
        iname = pos(get(f"X-Item-{it[0]}-S") or {}, 1)
        if not iname: continue
        names, objs = [], []
        for npc in (get(f"X-Item-{it[0]}-2") or []):
            nm = isinstance(npc, int) and ent("npc", npc)["name"]
            if nm and nm not in names: names.append(nm)
        for ob in (get(f"X-Item-{it[0]}-3") or []):
            nm = isinstance(ob, int) and ent("object", ob)["name"]
            if nm and nm not in objs: objs.append(nm)
        if names:
            src = "drops from " + ", ".join(names[:3]) + (", ..." if len(names) > 3 else "")
        elif objs:
            src = "on the ground" if objs == [iname] else "from " + ", ".join(objs[:3]) + (", ..." if len(objs) > 3 else "")
        else:
            src = None
        if src: drops.append("{" + lstr(iname) + "," + lstr(src) + "}")
    if drops: parts.append("dr={" + ",".join(drops) + "}")
    if tid: tip_end.setdefault(tid, set()).add(qid)
    out.append(f"  [{qid}]={{{', '.join(parts)}}},")
    # Objective types for the planner's time model (QuestieDB has no counts, only what kind).
    obj = get(f"X-Quest-{qid}-10") or {}
    mt = {"c": 0, "i": 0, "o": 0, "k": 0}
    mt["c"] = len([c for c in pos(obj, 1) or [] if isinstance(c, list) and c])
    mt["o"] = len([c for c in pos(obj, 2) or [] if isinstance(c, list) and c])
    for it in pos(obj, 3) or []:
        if not (isinstance(it, list) and it): continue
        mt["i" if get(f"X-Item-{it[0]}-2") else "o"] += 1
    mt["k"] = len([c for c in pos(obj, 5) or [] if isinstance(c, list) and c])
    qmeta[qid] = {k: v for k, v in mt.items() if v}
out.append("}")
out.append("-- Patrol paths of NPCs that walk: [npcId] = {uiMapID, {x1,y1, x2,y2, ...}}")
out.append("ns.paths = {")
for i, pth in sorted((k, v) for k, v in paths.items() if v):
    out.append(f"  [{i}]={{{pth[0]},{{" + ",".join(f"{x:.1f},{y:.1f}" for x, y in pth[1]) + "}},")
out.append("}")
# Rares and named quest targets by NPC ID: the game can hide a unit's name and classification from
# addons (secret values), but the NPC ID in its GUID is always readable.
rares, named = {}, {}
for k in list(meta):
    mm = re.match(r"X-Npc-(\d+)-S$", k)
    if not mm: continue
    i = int(mm.group(1))
    row = get(k) or {}
    rank, lo, hi, nm = pos(row, 6), pos(row, 4) or 0, pos(row, 5) or 0, pos(row, 1)
    if not nm or not (8 <= (hi or lo) <= 63): continue
    if rank == 4 or rank == 2:
        sp = ent("npc", i)["spawns"]
        if any(int(a) in uimap and int(a) not in dungeons for a in sp): rares[i] = nm
for i, qs in obj_npcs.items():
    e = ent("npc", i)
    if not e["name"] or i in rares: continue
    n_sp = sum(len(v or []) for v in e["spawns"].values())
    if 0 < n_sp <= 3: named[i] = (e["name"], sorted(set(qs))[:4])
out.append("-- Rare mobs (open world), [npcId] = name")
out.append("ns.rareNpcs = {" + ", ".join(f"[{i}]={lstr(n)}" for i, n in sorted(rares.items())) + "}")
out.append("-- Named quest targets (a mob with 1-3 spawns that a quest needs killed): [npcId] = {name, {questIds}}")
out.append("ns.namedNpcs = {" + ", ".join(f"[{i}]={{{lstr(n)},{{{','.join(map(str, qs))}}}}}" for i, (n, qs) in sorted(named.items())) + "}")
# Service NPCs (vendor, flight master, trainer, banker, battlemaster, auctioneer, stable master,
# repair; QuestieDB's Classic npcFlags), for skipping their one-option gossip. Innkeepers are left
# out on purpose: their gossip binds your hearthstone.
SERVICE, INNKEEPER = 4 | 8 | 16 | 256 | 2048 | 4096 | 8192 | 16384, 128
service = []
for k in list(meta):
    mm = re.match(r"X-Npc-(\d+)-S$", k)
    if not mm: continue
    fl = pos(get(k) or {}, 15)
    if isinstance(fl, int) and fl & SERVICE and not fl & INNKEEPER: service.append(int(mm.group(1)))
def tipmap(d):
    return ";".join(f"{n}:" + ",".join(map(str, sorted(qs))) for n, qs in sorted(d.items()))
out.append("-- Unit tooltips by NPC ID, \"npc:quest,quest;...\": mobs to kill or loot, quest givers, quest enders.")
out.append('ns.tipMobs = "' + tipmap(tip_mob) + '"')
out.append('ns.tipStarts = "' + tipmap(tip_start) + '"')
out.append('ns.tipEnds = "' + tipmap(tip_end) + '"')
print("tooltip npcs: mobs", len(tip_mob), "givers", len(tip_start), "enders", len(tip_end))
out.append("-- NPCs whose single gossip option is a service (vendor, flights, trainer, bank...).")
out.append('ns.serviceNpcs = "' + ",".join(map(str, sorted(service))) + '"')
print("service npcs:", len(service))
print("patrol paths:", sum(1 for v in paths.values() if v), "| rares:", len(rares), "| named quest targets:", len(named))
open(OUT, "w", encoding="utf-8").write("\n".join(out) + "\n")
json.dump(qmeta, open(HERE + r"\qmeta.json", "w"))
print("steps:", [(st["name"], len(ids)) for st, ids in steps_out])
print("routed quests:", len(used), "track-once-accepted:", len(track), "with objective areas:", n_obj)
