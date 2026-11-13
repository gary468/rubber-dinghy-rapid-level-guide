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
    dict(name="Arathi Highlands", lv=(41, 41), zones=[45], extra=[],
         note="Refuge Pointe. Fly from Ironforge/Menethil."),
    dict(name="Badlands", lv=(41, 42), zones=[3], extra=[],
         note="Fly to Thelsamar, then ride east. Uldaman quests start here."),
    dict(name="Stranglethorn Vale", lv=(42, 43), zones=[33], extra=[],
         note="Booty Bay. When done, take the Booty Bay boat to Ratchet for Kalimdor."),
    dict(name="Shen'dralas", lv=(43, 44), zones=[16651], extra=[],
         note="Forever's own zone (Kalimdor)."),
    dict(name="Feralas", lv=(44, 46), zones=[357], extra=[2766],
         note="Feathermoon + the coast. Lord Shalzaru is in the cave on the Isle of Dread (28,70)."),
    dict(name="Tanaris", lv=(46, 48), zones=[440], extra=[351],
         note="Gadgetzan. Fly in from Feathermoon or Thalanaar."),
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
    dict(name="Felwood", lv=(53, 54), zones=[361], extra=[7066],
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
for m in re.finditer(r"\[(\d+)\]\s*=\s*(\d+)", open(UIMAP, encoding="utf-8").read()):
    uimap.setdefault(int(m.group(1)), int(m.group(2)))
dungeons = {int(m.group(1)) for m in re.finditer(r'\[(\d+)\]\s*=\s*\{\s*"', open(DUNG, encoding="utf-8").read())}

_cache = {}
def ent(kind, i):
    """name, faction, spawns {area: [[x,y],...]} for an NPC or object."""
    if (kind, i) in _cache: return _cache[(kind, i)]
    if kind == "npc":
        row = get(f"X-Npc-{i}-S") or {}; sp = get(f"X-Npc-{i}-7") or {}
        e = dict(name=pos(row, 1), zone=pos(row, 9), fac=pos(row, 13), spawns=sp if isinstance(sp, dict) else {})
    else:
        row = get(f"X-Object-{i}-S") or {}; sp = get(f"X-Object-{i}-4") or {}
        e = dict(name=pos(row, 1), zone=pos(row, 5), fac=None, spawns=sp if isinstance(sp, dict) else {})
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
            if p: return dict(name=e["name"], area=p[0][0], x=p[0][1], y=p[0][2], fac=e["fac"])
            return dict(name=e["name"], area=e["zone"], x=None, y=None, fac=e["fac"])
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
    return dict(name=", ".join(names[:2]), area=a, x=cx, y=cy, r=rad)


d = json.load(open(HERE + r"\data.json", encoding="utf-8"))
Q = {int(k): v for k, v in d["quests"].items()}
black = set(d["blacklist"])


def eligible(qid, q):
    if qid in black: return False
    r = (q.get("requiredRaces") or 0) & 0xFFFF
    if r and not (r & ALLIANCE_RACES): return False
    if (q.get("specialFlags") or 0) & 1: return False
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
        if not (lo - 6 <= lvl <= max(hi + 6, 62 if hi >= 58 else 0)): continue
        g = givers.get(qid)
        if not g or g["area"] not in st["zones"]: continue
        if g.get("fac") and "A" not in str(g["fac"]): continue
        ids.append(qid)
    for qid in st["extra"]:
        if qid in Q and qid not in ids and qid not in used and eligible(qid, Q[qid]): ids.append(qid)
    for qid in ids: used[qid] = st
    steps_out.append((st, sorted(ids, key=lambda i: (Q[i].get("questLevel") or 0, i))))


def lstr(s):
    return '"' + str(s).replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ") + '"'

def lloc(e, with_r=False):
    if not e: return "nil"
    m = uimap.get(e["area"] or 0, 0)
    x = "nil" if e.get("x") is None else f"{e['x']:.1f}"
    y = "nil" if e.get("y") is None else f"{e['y']:.1f}"
    extra = f",{e['r']:.1f}" if with_r and e.get("r") else ""
    return "{" + f"{lstr(e['name'])},{m},{x},{y}{extra}" + "}"

def larr(v):
    v = [int(x) for x in (v or []) if isinstance(x, int)]
    return "{" + ",".join(map(str, v)) + "}" if v else "nil"

out = ["-- GENERATED by gen_route.py from QuestieDB (Forever). Do not edit by hand.",
       "-- Quest location fields: {name, uiMapID, x, y[, radius]}",
       "local _, ns = ...", "ns.steps = {"]
for st, ids in steps_out:
    m = uimap.get(st["zones"][0], 0)
    out.append(f"  {{name={lstr(st['name'])}, from={st['lv'][0]}, to={st['lv'][1]}, map={m}, note={lstr(st['note'])}, quests={{{','.join(map(str, ids))}}}}},")
out.append("}")
out.append("ns.quests = {")
n_obj = 0
for qid in sorted(used):
    q = Q[qid]; st = used[qid]
    fb = get(f"X-Quest-{qid}-3")
    t = loc_of(fb) if fb else None
    o = objective_area(q, qid, set(st["zones"]))
    if o: n_obj += 1
    parts = [f"n={lstr(q.get('name'))}", f"l={q.get('questLevel') or 0}", f"r={q.get('requiredLevel') or 0}",
             f"g={lloc(givers.get(qid))}", f"t={lloc(t)}"]
    if o: parts.append(f"o={lloc(o, True)}")
    if has_objectives(qid): parts.append("ob=true")
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
    for key, fld in (("pg", "preQuestGroup"), ("ps", "preQuestSingle"), ("ex", "exclusiveTo")):
        a = larr(q.get(fld))
        if a != "nil": parts.append(f"{key}={a}")
    if (q.get("zoneOrSort") or 0) in dungeons: parts.append("d=true")
    out.append(f"  [{qid}]={{{', '.join(parts)}}},")
out.append("}")
open(OUT, "w", encoding="utf-8").write("\n".join(out) + "\n")
print("steps:", [(st["name"], len(ids)) for st, ids in steps_out])
print("quests:", len(used), "with objective areas:", n_obj)
