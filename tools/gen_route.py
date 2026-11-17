"""Step 2 of rebuilding Data.lua: the Rubber Dinghy route (levels 40-60, Alliance) from QuestieDB (Forever).

Usage:  python -I tools/gen_route.py tools "<WoW>/_forever_" Data.lua
Needs data.json from decode.py in the tools dir (quest fields + zone names + blacklist).
Character progress is NOT baked in: the addon checks completion, race and class live in game.
To change the route (zones, order, levels), edit STEPS below and re-run both steps.
"""
import base64, json, math, os, re, struct, sys

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
    # Starting zones, level 1 up (each race's own route to 12 comes from tools/plan_start_*.json)
    dict(name="Elwynn Forest", lv=(1, 12), zones=[12], extra=[], note="Goldshire."),
    dict(name="Dun Morogh", lv=(1, 12), zones=[1], extra=[], note="Kharanos."),
    dict(name="Teldrassil", lv=(1, 12), zones=[141], extra=[], note="Dolanaar."),
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


# Objective objects QuestieDB has wrong (tools/overrides.json quests {qid: {"objObject": {"from": to}}}):
# Fetid Corruption (96296) lists the quest-start Corrupted Growth (651409, one spot) as its objective;
# Wowhead Forever has the real one, 651430, at 14 spots around it.
OBJ_SWAP = {}
try:
    for _k, _v in (json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "overrides.json"),
                                encoding="utf-8")).get("quests") or {}).items():
        if _v.get("objObject"): OBJ_SWAP[int(_k)] = {int(a): int(b) for a, b in _v["objObject"].items()}
except FileNotFoundError:
    pass


def get(k):
    v = meta.get(k)
    if v is None: return None
    m = re.fullmatch(r"~(\d+)~", v)
    if m: v = "".join(meta[f"{k}-{n}"] for n in range(1, int(m.group(1)) + 1))
    v = cbor(base64.b64decode(v))[0]
    m = re.fullmatch(r"X-Quest-(\d+)-10", k)
    if m and int(m.group(1)) in OBJ_SWAP and isinstance(v, (list, dict)):
        swap = OBJ_SWAP[int(m.group(1))]
        objs = pos(v, 2)
        if isinstance(objs, list):
            for o in objs:
                if isinstance(o, list) and o and o[0] in swap: o[0] = swap[o[0]]
    return v


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
            WH_SPAWNS[_k][int(_i)] = {"name": _v.get("name"), "replace": bool(_v.get("replace")),
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
    # "replace": QuestieDB has spawns but they're wrong (Celastrus the Bitter: 31 spots across the
    # foothills where he stands in one place, Gary 17 Nov); Wowhead's win.
    if wh and (not e["spawns"] or wh.get("replace")):
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
    return (_objective_area(qid, areas) or _objective_area(qid, None)
            or _objective_area(qid, areas, False) or _objective_area(qid, None, False))


def relevant_npcs(qid, npcs, item_name=None):
    """Of the mobs an objective comes from, the ones the quest is about: when the quest names its
    target in the item ("Gor'tesh's Lopped Off Head") or its objective text, and that target is a real
    named mob (1-3 known spawns), only that mob. Forever lists a level-60 Grubbub as dropping Gor'tesh's
    head too, and his two spawns outvoted Gor'tesh's one. Otherwise every mob that drops it."""
    npcs = [n for n in npcs if isinstance(n, int)]
    if len(npcs) <= 1: return npcs
    text = " ".join(str(x) for x in (get(f"X-Quest-{qid}-8") or []) if isinstance(x, str))
    if item_name: text += " " + item_name
    def spawn_count(n):
        return sum(len(v or []) for v in ent("npc", n)["spawns"].values())
    # only a real named mob (1-3 spawns, with known spawns): ordinary mobs share names with their
    # kin ("Goretusk" vs "Young Goretusk"), and those all drop the item
    named = [n for n in npcs if (ent("npc", n)["name"] or "\0") in text and 0 < spawn_count(n) <= 3]
    if named: return named
    return npcs



# Objectives of quests QuestieDB can't place, from ForeverChanges' quest pages (tools/fetch_objectives.py):
# {qid: {"need": [[kind, id, name]], "desc": "..."}}. Used only when QuestieDB has no objective sources.
try:
    FC_OBJ = json.load(open(HERE + r"\forever_objectives.json", encoding="utf-8"))
except (FileNotFoundError, ValueError):
    FC_OBJ = {}
_HOSTILE = None
def hostile_by_name():
    """Hostile NPCs (no faction to talk to) with a name of 2+ words and known spawns, by name - for
    spotting the mob a quest's description names."""
    global _HOSTILE
    if _HOSTILE is None:
        _HOSTILE = {}
        for k in list(meta):
            m = re.match(r"X-Npc-(\d+)-S$", k)
            if not m: continue
            row = get(k) or {}
            nm = pos(row, 1)
            if not nm or " " not in nm or len(nm) < 8 or pos(row, 13): continue
            _HOSTILE.setdefault(nm, []).append(int(m.group(1)))
    return _HOSTILE

def fc_groups(qid, focus=True):
    """[(label, [(kind, id)])] for a quest from ForeverChanges: each item, mob or object it asks for and
    where it comes from. An item nothing is known to drop comes from the named mobs the description
    mentions (Slithering Looters: 'A naga called Lady Sesspira leads the pillaging')."""
    rec = FC_OBJ.get(str(qid))
    if not rec: return []
    desc = rec.get("desc") or ""
    # the quest giver's zone: a mob the description names counts only if it lives there
    gl = loc_of(get(f"X-Quest-{qid}-2")) if get(f"X-Quest-{qid}-2") else None
    gmap = uimap.get((gl or {}).get("area") or 0)
    told = []
    for nm, ids in hostile_by_name().items():
        if nm not in desc: continue
        for i in ids:
            if any(uimap.get(a) == gmap for a, _, _ in pts(ent("npc", i)) or []): told.append(("npc", i))
    groups = []
    for kind, i, name in rec.get("need") or []:
        if kind == "goal":   # "Spitelash Battlemaster slain": that mob, where it lives in the giver's zone
            mob = re.sub(r"\s+slain$", "", name)
            src = [("npc", n) for n in hostile_by_name().get(mob, [])
                   if any(uimap.get(a) == gmap for a, _, _ in pts(ent("npc", n)) or [])]
            groups.append((mob, src))
            continue
        if kind == "npc": src = [("npc", i)]
        elif kind == "object": src = [("obj", i)]
        else:
            drops = [n for n in (get(f"X-Item-{i}-2") or []) if isinstance(n, int)]
            src = [("npc", n) for n in (relevant_npcs(qid, drops, name) if focus else drops)]
            src += [("obj", o) for o in (get(f"X-Item-{i}-3") or []) if isinstance(o, int)]
        groups.append((name, src or list(told)))
    if not groups and told: groups.append(("", told))
    return [g for g in groups if g[1]]

def _objective_area(qid, areas, focus=True):
    obj = get(f"X-Quest-{qid}-10") or {}
    sources = []  # (kind, id)
    for c in pos(obj, 1) or []:
        if isinstance(c, list) and c: sources.append(("npc", c[0]))
    for o in pos(obj, 2) or []:
        if isinstance(o, list) and o: sources.append(("obj", o[0]))
    for it in pos(obj, 3) or []:
        if not (isinstance(it, list) and it): continue
        iname = pos(get(f"X-Item-{it[0]}-S") or {}, 1)
        drops = get(f"X-Item-{it[0]}-2") or []
        for n in (relevant_npcs(qid, drops, iname) if focus else drops): sources.append(("npc", n))
        for o in get(f"X-Item-{it[0]}-3") or []: sources.append(("obj", o))
    for kc in pos(obj, 5) or []:
        if isinstance(kc, list) and kc and isinstance(kc[0], list):
            for n in kc[0]: sources.append(("npc", n))
    def collect(srcs):
        bp, nm = [], []
        for kind, i in srcs[:40]:
            e = ent(kind, i)
            p = pts(e, areas)
            if p:
                bp += p
                if e["name"] and e["name"] not in nm: nm.append(e["name"])
        return bp, nm
    best_pts, names = collect(sources)
    if not best_pts:   # QuestieDB has nothing we can place: ForeverChanges' objectives
        best_pts, names = collect([x for _, src in fc_groups(qid, focus) for x in src])
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


def objective_groups(qid, area):
    """Each objective's own spawns on the objective area's map: [(label, [(x, y), ...])], in the quest's
    objective order. label = what the quest log calls it (mob name for kills, item name for items).
    The addon uses them to drop finished objectives from a stop's area (Gary 14 Nov, Beware of
    Pterrordax: 15/15 Frenzied done, yet every dot was still a Frenzied Pterrordax). [] when the
    quest has fewer than two objectives with spawns there."""
    obj = get(f"X-Quest-{qid}-10")
    if area is None: return []
    groups = []
    def spots(sources):
        cells, out = set(), []
        for kind, i in sources[:40]:
            for b, u, v in pts(ent(kind, i)) or []:
                if b != area: continue
                key = (round(u / 2.5), round(v / 2.5))
                if key in cells: continue
                cells.add(key); out.append((u, v))
        if len(out) > 30:
            step = len(out) / 30.0
            out = [out[int(i * step)] for i in range(30)]
        return out
    for c in pos(obj, 1) or []:
        if isinstance(c, list) and c:
            nm = ent("npc", c[0])["name"]
            if nm: groups.append((nm, spots([("npc", c[0])])))
    for o in pos(obj, 2) or []:
        if isinstance(o, list) and o:
            nm = ent("obj", o[0])["name"]
            if nm: groups.append((nm, spots([("obj", o[0])])))
    for it in pos(obj, 3) or []:
        if not (isinstance(it, list) and it): continue
        iname = pos(get(f"X-Item-{it[0]}-S") or {}, 1)
        if not iname: continue
        drops = get(f"X-Item-{it[0]}-2") or []
        src = [("npc", n) for n in relevant_npcs(qid, drops, iname)]
        src += [("obj", o) for o in get(f"X-Item-{it[0]}-3") or [] if isinstance(o, int)]
        groups.append((iname, spots(src)))
    if not [g for g in groups if g[1]]:   # nothing placeable from QuestieDB: ForeverChanges' objectives
        groups = [(lbl, spots(src)) for lbl, src in fc_groups(qid) if lbl]
    groups = [g for g in groups if g[1]]
    return groups if len(groups) >= 2 else []


d = json.load(open(HERE + r"\data.json", encoding="utf-8"))
Q = {int(k): v for k, v in d["quests"].items()}
black = set(d["blacklist"])
# Corrections from what players see in Forever (tools/overrides.json): quests that aren't in the game,
# and chain links QuestieDB is missing.
NO_ACCEPT = {}
TIPS = {}      # quest -> a line of how-to shown under its stop (overrides.json "tip")
try:
    for _k, _v in (json.load(open(HERE + r"\overrides.json", encoding="utf-8")).get("quests") or {}).items():
        _q = Q.get(int(_k))
        if _v.get("drop"): black.add(int(_k))
        if _v.get("noAccept"): NO_ACCEPT[int(_k)] = _v["noAccept"]
        if _v.get("tip"): TIPS[int(_k)] = _v["tip"]
        if _q is not None:
            for _f in ("preQuestGroup", "preQuestSingle", "requiredLevel", "requiredClasses"):
                if _f in _v: _q[_f] = _v[_f]
except FileNotFoundError:
    pass
# Class quests QuestieDB doesn't mark (Forever-only): ForeverChanges files them under the class
# ("level 45 quest in Shaman"), read by tools/fetch_categories.py. Classic class bits.
CLASS_BITS = {"Warrior": 1, "Paladin": 2, "Hunter": 4, "Rogue": 8, "Priest": 16, "Shaman": 64,
              "Mage": 128, "Warlock": 256, "Druid": 1024}
try:
    for _k, _v in json.load(open(HERE + r"\forever_categories.json", encoding="utf-8")).items():
        _q = Q.get(int(_k))
        if _q is not None and _v in CLASS_BITS and not _q.get("requiredClasses"): _q["requiredClasses"] = CLASS_BITS[_v]
except FileNotFoundError:
    pass
# Minimum levels QuestieDB lacks (mostly Forever-only quests), read from ForeverChanges' quest pages
# by tools/fetch_reqlevels.py ("requires level N", from what players see in game).
try:
    for _k, _v in json.load(open(HERE + r"\forever_reqlevels.json", encoding="utf-8")).items():
        _q = Q.get(int(_k))
        if _q is not None and _v and not _q.get("requiredLevel"): _q["requiredLevel"] = int(_v)
except FileNotFoundError:
    pass


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
        if not (min(lo - 6, 8) <= lvl <= 62): continue   # starting zones from level 1, the rest 8+
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
    if not (1 <= lvl <= 62): continue   # capitals' level 1-7 quests too (the starting routes use them)
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
    # Each race's own route from level 1 (tools/plan_start_*.json, planned in its starting zone and
    # capital): steps the addon only shows to that race, before the shared route.
    starts = []
    for fn, mask in (("plan_start_human.json", 1), ("plan_start_dwarf.json", 4 | 64), ("plan_start_nelf.json", 8)):
        try:
            for v in json.load(open(HERE + "\\" + fn, encoding="utf-8")):
                if v.get("kind") == "zone": starts.append(dict(v, _race=mask))
        except FileNotFoundError:
            pass
    # A race whose starting zone couldn't be planned (Dun Morogh: Questie's Forever data has no NPC
    # positions there yet): its quests in level order as a plain step, until players' learned spots
    # let tools/plan_v2.py plan it.
    for mask, zname in ((4 | 64, "Dun Morogh"), (1, "Elwynn Forest"), (8, "Teldrassil")):
        if any(v.get("_race") == mask for v in starts): continue
        zst = next((ids for st, ids in steps_out if st["name"] == zname), [])
        qs = [q for q in zst if (Q[q].get("questLevel") or 0) <= 14]
        m = next((uimap.get(z) for st, _ in steps_out if st["name"] == zname for z in st["zones"]), None)
        if qs and m:
            starts.append(dict(kind="zone", map=m, name=zname, lv_in=1, lv_out=12, quests=qs, pick=[], turn=[], _race=mask))
    plan = starts + [v for v in plan if v.get("lv_out", 99) > 12 or v.get("kind") != "zone" or not starts]
    for v in plan:
        if v["name"].startswith("map ") or v["name"] == "here":
            for a in sorted(map_areas.get(v["map"], [])):
                if zone_name.get(a): v["name"] = zone_name[a]; break
        ids = [q for q in v["quests"] if q in Q and q not in black]
        if v.get("kind") == "dungeon":
            # Every quest for this dungeon: the addon shows the ones you hold or can get, live.
            ids += [q for q in v.get("all", []) if q in Q and q not in ids and eligible(q, Q[q])]
        pick = [q for q in v.get("pick", []) if q in Q and q not in black]
        turn = [q for q in v.get("turn", []) if q in Q and q not in black]      # route v2: hand-ins placed here
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
            seen[(v.get("_race"), m)] += 1
            note = zone_note.get(m, f"Go to {v['name']}.")
            if not ids and (pick or turn):
                note = "On the way: " + " and ".join(x for x in (
                    "pick up quests for later" if pick else "", "hand in finished quests" if turn else "") if x) + "."
            elif seen[(v.get("_race"), m)] > 1: note = "Back for the quests that have opened up at your level. " + note
            if pick and ids: note += " Pick up quests here for later in the route."
            if (v.get("grind_s") or 0) >= 300:   # route v2: levels ground here to unlock this zone's quests
                note += f" Includes about {round(v['grind_s'] / 60)} min of grinding: some quests here need a level or two more."
            st = dict(name=v["name"] + ("" if seen[(v.get("_race"), m)] == 1 else " (return visit)"), lv=lv,
                      zones=sorted(map_areas.get(m, [])) or [0], map_id=m, note=note, extra=[], pick=pick,
                      turn=turn, ord=v.get("order"))
        st["xp"], st["secs"] = int(v.get("xp") or 0), int(v.get("secs") or 0)
        if v.get("_race"): st["race"] = v["_race"]
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

# Spots Questie files on a whole continent's map (Into The Maw of Madness: Mistress Natalia Mar'alith
# on "Kalimdor") become the zone they fall in, using the game's map rectangles (tools/geo.json), so
# the route never gets a step named after a continent.
try:
    _GEO = json.load(open(HERE + r"\geo.json", encoding="utf-8"))["maps"]
except (FileNotFoundError, ValueError, KeyError):
    _GEO = {}
def world_of(m, x, y):
    """(continent, world X, world Y) in yards for a spot on a map, from the game's map rectangles."""
    g = _GEO.get(str(m))
    if not g or x is None or y is None: return None
    return g.get("cont"), g["x1"] + (g["x2"] - g["x1"]) * y / 100.0, g["y1"] + (g["y2"] - g["y1"]) * x / 100.0

def zone_of(m, x, y):
    g = _GEO.get(str(m))
    if not g or g.get("type") != 2 or x is None or y is None: return m, x, y
    wy = g["y1"] + (g["y2"] - g["y1"]) * x / 100.0          # map x (left-right) = world Y
    wx = g["x1"] + (g["x2"] - g["x1"]) * y / 100.0          # map y (top-bottom) = world X
    best = None
    for k, z in _GEO.items():
        if z.get("type") != 3 or z.get("cont") != g.get("cont"): continue
        u = (wy - z["y1"]) / (z["y2"] - z["y1"]) * 100.0
        v = (wx - z["x1"]) / (z["x2"] - z["x1"]) * 100.0
        off = max(0.0, -u, u - 100.0) + max(0.0, -v, v - 100.0)   # 0 = inside the zone
        if best is None or off < best[0]: best = (off, int(k), min(100.0, max(0.0, u)), min(100.0, max(0.0, v)))
    if best and best[0] < 10: return best[1], best[2], best[3]
    return m, x, y

def lloc(e, with_r=False):
    if not e: return "nil"
    m = uimap.get(e["area"] or 0, 0)
    if str(m) in _GEO and _GEO[str(m)].get("type") == 2 and e.get("x") is not None:
        m2, x2, y2 = zone_of(m, e["x"], e["y"])
        if m2 != m:
            pts = [zone_of(m, u, v)[1:] for u, v in (e.get("pts") or [])]
            e = dict(e, x=x2, y=y2, pts=pts or e.get("pts"))
            m = m2
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
    if st.get("race"): extra += f", race={st['race']}"   # a starting zone's step: only for these races
    if st.get("xp"): extra += f", xp={st['xp']}, secs={st['secs']}"
    out.append(f"  {{name={lstr(st['name'])}, from={st['lv'][0]}, to={st['lv'][1]}, map={m}, note={lstr(st['note'])}, quests={{{','.join(map(str, ids))}}}{extra}}},")
out.append("}")
out.append("-- Quests only routed once they're in your log (never suggested for pick-up).")
out.append("ns.track = {" + ",".join(map(str, sorted(track))) + "}")
out.append("-- Quests the auto-accept leaves alone (tools/overrides.json noAccept): why, shown in chat.")
out.append("ns.noAccept = {" + ", ".join(f"[{k}]={lstr(v)}" for k, v in sorted(NO_ACCEPT.items())) + "}")
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
    LEARNED_NPCS = json.load(open(HERE + r"\learned.json", encoding="utf-8")).get("npcs") or {}
except (FileNotFoundError, ValueError):
    LEARNED_SPOTS = {}
    LEARNED_NPCS = {}
_AREA_OF_MAP = {}
for _a, _m in uimap.items(): _AREA_OF_MAP.setdefault(_m, _a)
try:
    FC_LOCS = json.load(open(HERE + r"\forever_locs.json", encoding="utf-8"))
except (FileNotFoundError, ValueError):
    FC_LOCS = {}
# every NPC ForeverChanges pins anywhere: name -> (uiMap, x, y), for givers and hand-ins with no position
FC_NPC_POS = {}
for _r in FC_LOCS.values():
    for _k in ("start", "end"):
        _p = _r.get(_k)
        if _p and _r.get("map") and _p[0] not in FC_NPC_POS: FC_NPC_POS[_p[0]] = (_r["map"], _p[1], _p[2])
try:
    NPC_FIX = {k: v for k, v in (json.load(open(HERE + r"\overrides.json", encoding="utf-8")).get("npcs") or {}).items()
               if isinstance(v, dict)}
except FileNotFoundError:
    NPC_FIX = {}
def with_learned(qid, kind, loc):
    """A giver / hand-in with no position in the data: where players stood when its quest window
    opened (Learn.lua), if any. NPCs the data has in the wrong place (overrides.json "npcs") first."""
    fix = loc and NPC_FIX.get(loc.get("name"))
    if fix and loc.get("x") is not None and uimap.get(loc.get("area") or 0) == fix["from"][0] \
            and abs(loc["x"] - fix["from"][1]) < 0.15 and abs(loc["y"] - fix["from"][2]) < 0.15:
        to = fix["to"]
        loc = dict(loc, area=_AREA_OF_MAP.get(to[0], loc.get("area")), x=to[1], y=to[2])
    # ForeverChanges' start / end pin for this quest (tools/fetch_fc_locs.py), when it's the same NPC
    # and our data has no position, another zone, or a spot more than 5% of the map away
    pin = (FC_LOCS.get(str(qid)) or {})
    fcp = pin.get("start" if kind == "g" else "end")
    if loc and fcp and pin.get("map") in _AREA_OF_MAP and fcp[0] == loc.get("name") and fcp[0] not in ("Chicken",):
        m0 = uimap.get(loc.get("area") or 0)
        # compared in the world, not map %: an Ironforge NPC is the same spot on ForeverChanges' Dun
        # Morogh map. Only a missing position, another continent or 200+ yards apart counts.
        wa = world_of(m0, loc.get("x"), loc.get("y"))
        wb = world_of(pin["map"], fcp[1], fcp[2])
        if loc.get("x") is None or (wa and wb and (wa[0] != wb[0] or math.hypot(wa[1] - wb[1], wa[2] - wb[2]) > 200)):
            loc = dict(loc, area=_AREA_OF_MAP[pin["map"]], x=fcp[1], y=fcp[2])
    # still no position: the same NPC pinned on any other ForeverChanges quest page
    if loc and loc.get("x") is None and loc.get("name") in FC_NPC_POS:
        m2, x2, y2 = FC_NPC_POS[loc["name"]]
        if m2 in _AREA_OF_MAP: loc = dict(loc, area=_AREA_OF_MAP[m2], x=x2, y=y2)
    v = LEARNED_NPCS.get(f"{kind}{qid}")
    if not loc or loc.get("x") is not None or not v or v[0] not in _AREA_OF_MAP: return loc
    return dict(loc, area=_AREA_OF_MAP[v[0]], x=v[1], y=v[2])
# Spots players told us about (tools/overrides.json "spots"), for objectives no database places.
# "groups": {"objective name": [[x, y], ...]} - which spots are which quest-log line, so a finished
# one drops off its stop (Gary 17 Nov, Kits and Cats: Brie's stop stayed after he found her).
SPOT_GROUPS = {}
try:
    for _k, _v in (json.load(open(HERE + r"\overrides.json", encoding="utf-8")).get("quests") or {}).items():
        if _v.get("spots") and int(_k) not in LEARNED_SPOTS: LEARNED_SPOTS[int(_k)] = _v["spots"]
        if _v.get("groups"): SPOT_GROUPS[int(_k)] = _v["groups"]
except FileNotFoundError:
    pass

def spots_loc(spots, name):
    from collections import Counter
    m = Counter(p[0] for p in spots).most_common(1)[0][0]
    pts = [(p[1], p[2]) for p in spots if p[0] == m]
    cx = sum(x for x, _ in pts) / len(pts); cy = sum(y for _, y in pts) / len(pts)
    rad = max(2.0, min(10.0, max(math.hypot(x - cx, y - cy) for x, y in pts)))
    flat = ",".join(f"{x:.0f},{y:.0f}" for x, y in pts[:40])
    return "{" + f"{lstr(name)},{m},{cx:.1f},{cy:.1f},{rad:.1f}" + (",{" + flat + "}" if len(pts) > 1 else "") + "}"
def start_item(qid):
    """A quest started by an item (looted or picked up): where the item comes from, as Lua
    {itemId, itemName, kind, source, uiMap, x, y} plus the NPC IDs that drop it. kind: "mob" = one named
    mob (or a few, all with 1-3 spawns) - worth hunting; "obj" = an object on the ground; "drop" = a
    random drop from ordinary mobs - keep an eye out. None if nothing in the open world gives it."""
    from collections import Counter
    g = get(f"X-Quest-{qid}-2")
    items = pos(g, 3) if g else None
    if not items: return None, []
    iid = items[0]
    iname = pos(get(f"X-Item-{iid}-S") or {}, 1) or "an item"
    npcs = [n for n in (get(f"X-Item-{iid}-2") or []) if isinstance(n, int)]
    objs = [o for o in (get(f"X-Item-{iid}-3") or []) if isinstance(o, int)]
    count, where, spawns = Counter(), {}, {}
    for kind, lst in (("npc", npcs), ("obj", objs)):
        for i in lst[:80]:
            e = ent(kind, i)
            for a, x, y in pts(e) or []:
                m = uimap.get(a)
                if not m or a in dungeons: continue
                count[m] += 1
                where.setdefault(m, []).append((x, y))
                spawns[(kind, i)] = spawns.get((kind, i), 0) + 1
    if not count: return None, []
    m = count.most_common(1)[0][0]
    x, y = where[m][0]
    names = [ent("npc", n)["name"] for n in npcs if ent("npc", n)["name"]]
    onames = [ent("obj", o)["name"] for o in objs if ent("obj", o)["name"]]
    if npcs and not objs and len(npcs) <= 3 and all(0 < spawns.get(("npc", n), 0) <= 3 for n in npcs):
        kind, src = "mob", " / ".join(names[:3])
    elif objs and not npcs:
        kind, src = "obj", onames[0] if onames else iname
        if len(where[m]) > 1:      # the middle of where it lies
            x = sum(u for u, _ in where[m]) / len(where[m]); y = sum(v for _, v in where[m]) / len(where[m])
    else:
        kind = "drop"
        src = ", ".join(names[:2]) + (", ..." if len(names) > 2 else "")
    lua = "{" + f"{iid},{lstr(iname)},{lstr(kind)},{lstr(src)},{m},{x:.1f},{y:.1f}" + "}"
    return lua, (npcs if kind != "obj" else [])

tip_mob, tip_start, tip_end = {}, {}, {}
tip_drop = {}
for qid in sorted(set(used) | set(track)):
    q = Q[qid]; st = used.get(qid)
    fb = get(f"X-Quest-{qid}-3")
    t = loc_of(fb) if fb else None
    if st: areas = set(st["zones"])
    elif track.get(qid): areas = {track[qid]}
    else: areas = set()
    o = objective_area(q, qid, areas)
    if o: n_obj += 1
    # Minimum level: QuestieDB has none for many Forever-only quests, which made them look available at
    # any level (Gary at 52: Hol'anyee Marshal doesn't offer her level-55 quest, which needs 55). Looked
    # up from ForeverChanges where possible (above); still unknown -> 2 below the quest's level.
    ql_ = q.get("questLevel") or 0
    rl_ = q.get("requiredLevel") or (max(1, ql_ - 2) if ql_ >= 10 else 0)
    parts = [f"n={lstr(q.get('name'))}", f"l={ql_}", f"r={rl_}",
             f"g={lloc(with_learned(qid, 'g', givers.get(qid)))}", f"t={lloc(with_learned(qid, 't', t))}"]
    if (givers.get(qid) or {}).get("name") == "(item drop)":
        si, si_npcs = start_item(qid)
        if si:
            parts.append("si=" + si)
            for n in si_npcs: tip_drop.setdefault(n, set()).add(qid)
    if o: parts.append(f"o={lloc(o, True)}")
    if o and o.get("area") is not None:
        om = objective_groups(qid, o["area"])
        if om:
            parts.append("om={" + ",".join("{" + lstr(lbl) + ",{" + ",".join(f"{u:.0f},{v:.0f}" for u, v in sp) + "}}" for lbl, sp in om) + "}")
    elif LEARNED_SPOTS.get(qid):
        # no location in any database, but players' recorded where its progress went up (Learn.lua)
        parts.append("o=" + spots_loc(LEARNED_SPOTS[qid], q.get("name") or "Objective"))
        if SPOT_GROUPS.get(qid):
            parts.append("om={" + ",".join("{" + lstr(lbl) + ",{" + ",".join(f"{x:.0f},{y:.0f}" for x, y in pts) + "}}"
                                           for lbl, pts in SPOT_GROUPS[qid].items()) + "}")
    elif (FC_OBJ.get(str(qid)) or {}).get("dots") and FC_OBJ[str(qid)].get("map"):
        # ForeverChanges' quest map: dots where the objectives are (Forever-only objects no database has)
        rec = FC_OBJ[str(qid)]
        parts.append("o=" + spots_loc([[rec["map"], x, y] for x, y in rec["dots"]], q.get("name") or "Objective"))
    else:
        # no spot for its objectives: keep the quest's own objective text ("...in Wildhammer Keep")
        ot = get(f"X-Quest-{qid}-8")
        if isinstance(ot, list) and ot and isinstance(ot[0], str) and has_objectives(qid):
            parts.append(f"ot={lstr(ot[0][:160])}")
    if has_objectives(qid) or (FC_OBJ.get(str(qid)) or {}).get("need"): parts.append("ob=true")
    if (q.get("specialFlags") or 0) & 1: parts.append("rep=true")
    if (q.get("questFlags") or 0) & 2: parts.append("esc=true")   # escort / group event: starts for the party
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
        for npc in relevant_npcs(qid, get(f"X-Item-{it[0]}-2") or [], iname):
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
    if TIPS.get(qid): parts.append("tip=" + lstr(TIPS[qid]))
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
# Grinding camps per zone, for catching up when you're behind the route: hostile, non-elite mobs in
# a dense spot (8+ spawns within 6% of the map), with their levels. {uiMap = {{name, lo, hi, x, y, n}}}
camps = {}
for k in list(meta):
    mm = re.match(r"X-Npc-(\d+)-S$", k)
    if not mm: continue
    row = get(k) or {}
    nm, lo, hi, rank, fac = pos(row, 1), pos(row, 4) or 0, pos(row, 5) or 0, pos(row, 6) or 0, pos(row, 13)
    if not nm or fac or rank or not (5 <= (hi or lo) <= 62): continue
    e = ent("npc", int(mm.group(1)))
    by_map = {}
    for a, x, y in pts(e) or []:
        m = uimap.get(a)
        if m and a not in dungeons: by_map.setdefault(m, []).append((x, y))
    for m, ps in by_map.items():
        if len(ps) < 8: continue
        best, bn = None, 0
        for x, y in ps[:300]:
            n = sum(1 for u, v in ps if (u - x) ** 2 + (v - y) ** 2 <= 36)
            if n > bn: best, bn = (x, y), n
        if bn < 8: continue
        near = [(u, v) for u, v in ps if (u - best[0]) ** 2 + (v - best[1]) ** 2 <= 36]
        cx = sum(u for u, _ in near) / len(near); cy = sum(v for _, v in near) / len(near)
        camps.setdefault(m, []).append((nm, lo or hi, hi or lo, cx, cy, bn))
out.append("-- Grinding camps per zone (catch-up when you're behind): [uiMap] = {{name, lo, hi, x, y, spawns}}")
out.append("ns.grindCamps = {")
for m in sorted(camps):
    best = {}
    for c in sorted(camps[m], key=lambda c: -c[5]):
        best.setdefault(c[0], c)            # one camp per mob name
    top = sorted(best.values(), key=lambda c: -c[5])[:14]
    out.append(f"  [{m}]={{" + ",".join("{" + f"{lstr(c[0])},{c[1]},{c[2]},{c[3]:.0f},{c[4]:.0f},{c[5]}" + "}" for c in top) + "},")
out.append("}")
print("grind camps:", sum(min(14, len(v)) for v in camps.values()), "in", len(camps), "zones")
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
out.append('ns.tipDrops = "' + tipmap(tip_drop) + '"')   # mobs that can drop an item that starts a quest
print("tooltip npcs: mobs", len(tip_mob), "givers", len(tip_start), "enders", len(tip_end))
out.append("-- NPCs whose single gossip option is a service (vendor, flights, trainer, bank...).")
out.append('ns.serviceNpcs = "' + ",".join(map(str, sorted(service))) + '"')
print("service npcs:", len(service))
print("patrol paths:", sum(1 for v in paths.values() if v), "| rares:", len(rares), "| named quest targets:", len(named))
open(OUT, "w", encoding="utf-8").write("\n".join(out) + "\n")
json.dump(qmeta, open(HERE + r"\qmeta.json", "w"))
print("steps:", [(st["name"], len(ids)) for st, ids in steps_out])
print("routed quests:", len(used), "track-once-accepted:", len(track), "with objective areas:", n_obj)
