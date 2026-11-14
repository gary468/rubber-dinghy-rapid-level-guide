"""Shared route maths for tools/sim.py and tools/plan_route.py: reads Data.lua (via lupa), Questie's
quest XP, the Classic XP table, approximate zone sizes and quest availability rules."""
import math, re
from lupa import lua51

RACE, CLASS = 64, 128          # gnome mage: only used for race/class-locked quests
MOB_FACTOR = 0.45              # kill XP while questing, as a share of quest XP (calibrated: 40->60 ends ~60)

# Continents (uiMapIDs), for travel cost between zones.
KALIMDOR = {1444, 1446, 1449, 1448, 1447, 1452, 1451, 1443, 1441, 1450, 1413, 1438, 1457, 2482, 2652, 1442, 1439, 1440, 1445}
EASTERN = {1434, 1417, 1418, 1419, 1427, 1428, 1425, 1422, 1423, 1435, 1424, 1416, 1453, 1455, 2548, 2521, 1431,
           1436, 1433, 1432, 1437, 1420, 1421, 1426, 1429, 1430, 1458}

SIZE = {
    1444: (6950, 4633), 1446: (6900, 4600), 1449: (3700, 2467), 1448: (5750, 3833), 1447: (5070, 3381),
    1452: (7100, 4733), 1451: (3483, 2323), 1443: (4496, 2998), 1434: (6381, 4254), 1417: (3600, 2400),
    1418: (2488, 1658), 1419: (3350, 2233), 1427: (2231, 1488), 1428: (2929, 1952), 1425: (3850, 2567),
    1422: (4300, 2867), 1423: (4031, 2687), 1441: (4400, 2933), 1450: (2308, 1540), 1435: (2294, 1529),
    1424: (3200, 2133), 1416: (2800, 1867), 1413: (10133, 6756), 1438: (5092, 3395), 1453: (1737, 1158),
    1455: (790, 527), 1457: (1058, 706),
    # 30-40 zones
    1431: (2700, 1800), 1437: (4135, 2757), 1445: (5250, 3500), 1440: (5766, 3844), 1442: (4883, 3255),
    1432: (2758, 1839), 1439: (6550, 4367), 1433: (2170, 1447),
    # 10-20 zones
    1429: (3470, 2314), 1426: (4925, 3283), 1438: (5092, 3395),
    # 20-30 zones
    1436: (3500, 2333), 1413: (10133, 6756), 1416: (2800, 1867), 1424: (3200, 2133),
}
DEFAULT_SIZE = (4000, 2667)


def load(data_path, wow):
    L = lua51.LuaRuntime(unpack_returned_tuples=True)
    ns = L.table()
    L.execute("return function(src, ns) return assert(loadstring(src))('x', ns) end")(
        open(data_path, encoding="utf-8").read(), ns)
    ltype = L.eval("type")

    def py(v):
        if ltype(v) != "table": return v
        keys = list(v.keys())
        if keys and all(isinstance(k, int) for k in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
            return [py(v[k]) for k in sorted(keys)]
        return {k: py(v[k]) for k in keys}

    steps = py(ns.steps)
    quests = {int(k): v for k, v in py(ns.quests).items()}
    track = set(py(ns.track) or [])
    base = {}
    for fn in ("xpDB-classic.lua", "xpDB-traces.lua"):
        p = wow + r"\Interface\AddOns\QuestieDB\support\Forever\QuestXP" + "\\" + fn
        for m in re.finditer(r"\[(\d+)\]\s*=\s*\{\s*(-?\d+)\s*,\s*(\d+)", open(p, encoding="utf-8").read()):
            base.setdefault(int(m.group(1)), (int(m.group(2)), int(m.group(3))))
    return steps, quests, track, base


def map_names(wow, steps):
    """uiMapID -> zone name: route step names, then Questie's zone table."""
    names = {s["map"]: s["name"] for s in steps}
    zone_names, area_map = {}, {}
    for m in re.finditer(r'\[(-?\d+)\]\s*=\s*"([^"]+)"', open(wow + r"\Interface\AddOns\Questie\Localization\lookups\lookupZones.lua", encoding="utf-8", errors="replace").read()):
        zone_names.setdefault(int(m.group(1)), m.group(2))
    for m in re.finditer(r"\[(\d+)\]\s*=\s*(\d+)", open(wow + r"\Interface\AddOns\QuestieDB\support\Forever\Zones\areaIdToUiMapId.lua", encoding="utf-8").read()):
        area_map.setdefault(int(m.group(1)), int(m.group(2)))
    for area, m in area_map.items():
        if m not in names and area in zone_names: names[m] = zone_names[area]
    return names


def level_xp(lv):
    """Classic XP to go from lv to lv+1 (matches 209,800 at 59)."""
    diff = 0 if lv <= 28 else {29: 1, 30: 3, 31: 6}.get(lv, 5 * (lv - 30))
    return int(round((8 * lv + diff) * (45 + 5 * lv) / 100.0)) * 100


def quest_xp(base, qid, char_level):
    """Questie's QuestXP rule (cmangos): full XP up to 5 levels below, falling to 10%."""
    if qid not in base: return 0
    qlv, xp = base[qid]
    if qlv <= 0 or xp <= 0: return 0
    mult = min(10, max(1, 2 * (qlv - char_level) + 20))
    xp = xp * mult / 10
    if xp <= 100: xp = 5 * math.floor((xp + 2) / 5)
    elif xp <= 500: xp = 10 * math.floor((xp + 5) / 10)
    elif xp <= 1000: xp = 25 * math.floor((xp + 12) / 25)
    else: xp = 50 * math.floor((xp + 25) / 50)
    return int(xp)


def yards(m, a, b):
    w, h = SIZE.get(m, DEFAULT_SIZE)
    return math.hypot((a[0] - b[0]) / 100 * w, (a[1] - b[1]) / 100 * h)


def loc(v):
    """{name, map, x, y, ...} -> (map, (x, y)) or None"""
    if not v or len(v) < 4 or v[2] is None or v[3] is None or v[2] < 0 or not v[1]: return None
    return v[1], (v[2], v[3])


def continent(m):
    if m in KALIMDOR: return "K"
    if m in EASTERN: return "E"
    return "?"


MAX_ABOVE = 3                  # don't take on quests more than 3 levels above you (red = too dangerous)


def available(q, done, lv, allow_class=True, dungeon=False):
    if q.get("ra") and not (q["ra"] & RACE): return False
    if q.get("cl") and not (allow_class and (q["cl"] & CLASS)): return False
    if q.get("rep"): return False
    if q.get("d") and not dungeon: return False
    if (q.get("r") or 0) > lv: return False
    if (q.get("l") or 0) > lv + MAX_ABOVE: return False
    for p in q.get("pg") or []:
        if p > 0 and p not in done: return False
    ps = q.get("ps") or []
    if ps and not any(p in done for p in ps): return False
    if any(p in done for p in (q.get("ex") or [])): return False
    return True


###########################################################################
# Time model: everything in seconds, one goal - the fewest minutes from 40 to 60.
# Travel counts only as the time it takes (flight/boat fees don't matter).
###########################################################################
SPEED = 11.0              # yd/s mounted
KILL_S = 25               # seconds per kill incl. eating/drinking, solo at level
QUEST_BASE_S = 45         # accept + hand in + reading, per quest
KILLS = {"creature": 8, "item_drop": 12, "killcredit": 4}   # QuestieDB has no counts: Classic averages
OBJECTS, OBJECT_S = 6, 20 # clicky objectives: how many, seconds each
HOP_SAME_S, HOP_OTHER_S, HOP_UNKNOWN_S = 300, 900, 600      # zone change: flights / boat + flights (incl. waiting)
VISIT_S = 60              # settling into a zone (flight master, hub)
# Dungeons, assuming a good group. Calibrated from the dungeon journal's Run Log (every kill's XP
# and time, per run) where you have one: your logged runs count as below average, and a good group
# gets GOOD_GROUP x their kill XP per hour and finishes in GOOD_GROUP_TIME x their run time.
# Without a log: run time from the boss count, kill XP at DUNGEON_KILL_RATE x solo grinding.
import os as _os
GROUP_S = float(_os.environ.get("GROUP_S", 300))
RUN_BASE_S, BOSS_S, MAX_BOSSES = 900, 300, 12
GOOD_GROUP = float(_os.environ.get("GOOD_GROUP", 1.5))
GOOD_GROUP_TIME = 0.85
DUNGEON_KILL_RATE = float(_os.environ.get("DUNGEON_KILL_RATE", 1.2))   # dungeon kill XP/h vs solo grinding
CITY_PICKUP_S = 240       # fetching dungeon quests from a giver in another zone (often a capital)
TURNIN_S = 60


def mob_xp(lv):
    """Classic XP for killing a same-level normal mob."""
    return 45 + 5 * lv


def grind_xph(lv):
    return 3600.0 / KILL_S * mob_xp(lv)


ITEM_KILLS = 1.5          # kills per quest item that drops (Classic drop rates are ~50-80%)


def quest_cost(meta, lv):
    """(seconds, kill XP) to do one quest's objectives at level lv. Uses the real counts learned in
    game ("cnt": kills, items, objects) when there are some, else Classic averages per objective type."""
    m = meta or {}
    cnt = m.get("cnt")
    if cnt:
        drops = bool(m.get("i"))                     # QuestieDB: the items drop from mobs
        kills = cnt.get("m", 0) + (cnt.get("i", 0) * ITEM_KILLS if drops else 0)
        objs = cnt.get("o", 0) + (0 if drops else cnt.get("i", 0))   # items not from mobs: picked up
    else:
        kills = (m.get("c", 0) * KILLS["creature"] + m.get("i", 0) * KILLS["item_drop"]
                 + m.get("k", 0) * KILLS["killcredit"])
        objs = m.get("o", 0) * OBJECTS
    return QUEST_BASE_S + kills * KILL_S + objs * OBJECT_S, kills * mob_xp(lv)


def apply_learned(meta, path):
    """Fold tools/learned.json (from tools/learn.py) into the model: real objective counts per quest,
    and real flight times. Never the player's own pace."""
    import json, os
    global HOP_SAME_S
    if not os.path.exists(path): return 0
    data = json.load(open(path))
    n = 0
    for qid, c in data.get("counts", {}).items():
        meta.setdefault(int(qid), {})["cnt"] = c
        n += 1
    if data.get("flight_s"):
        HOP_SAME_S = float(data["flight_s"]) + 90   # + getting to and from the flight master
    return n


def hop_s(a, b):
    if a is None or a == b: return 0
    ca, cb = continent(a), continent(b)
    if "?" in (ca, cb): return HOP_UNKNOWN_S
    return HOP_SAME_S if ca == cb else HOP_OTHER_S


# Dungeon journal shortcuts (/dj <key>) for the journal addon, by dungeon name.
DJ_KEY = {"Ragefire Chasm": "rfc", "The Hall of Thanes": "hall", "Hall of Thanes": "hall", "The Deadmines": "dm", "Wailing Caverns": "wc", "Shadowfang Keep": "sfk", "Ruins of Lordaeron": "rol",
          "Blackfathom Deeps": "bfd", "The Stockade": "stocks", "Gnomeregan": "gnomer", "Razorfen Kraul": "rfk",
          "City of Dalaran": "dala", "Excavation Site: Wetlands": "exca", "Scarlet Monastery: Graveyard": "smgy",
          "Uldaman": "ulda", "Zul'Farrak": "zf", "Maraudon": "mara", "Sunken Temple": "st",
          "Blackrock Depths": "brd", "Lower Blackrock Spire": "lbrs", "Upper Blackrock Spire": "ubrs",
          "Dire Maul: East": "dme", "Dire Maul: West": "dmw", "Dire Maul: North": "dmn",
          "Stratholme: Living": "stratliving", "Stratholme: Undead": "stratundead", "Scholomance": "scholo",
          "Alcaz Prison": "alcaz", "Blackmaw Hold": "blackmaw", "Krol'dok Stronghold": "kroldok",
          "The Drowned City": "drowned", "Razorfen Downs": "rfd", "Scarlet Monastery: Cathedral": "cath",
          "Scarlet Monastery: Armory": "arm", "Scarlet Monastery: Library": "lib", "Shaper's Terrace": "shaper"}
RAID_LIKE = {"Upper Blackrock Spire"}   # 10-man in Classic: not a leveling run


def load_dungeons(wow, lo=10, hi=60):
    """Dungeons from our own journal data (Data_Dungeons.lua, built by tools/gen_dungeons.py from
    QuestieDB and public facts): name, levels, bosses, entrance, Alliance quest IDs."""
    import os
    path = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Data_Dungeons.lua")
    if not os.path.isfile(path): return []
    L = lua51.LuaRuntime(unpack_returned_tuples=True)
    ns = L.eval("{}")
    L.eval("function(src, ns) return assert(loadstring(src, 'Data_Dungeons.lua'))('RubberDinghy', ns) end")(
        open(path, encoding="utf-8").read(), ns)
    DQ = ns.dungeonQuests
    out = []
    for i in range(1, len(ns.dungeonDB) + 1):
        d = ns.dungeonDB[i]
        name = str(d.name)
        if d.raidlike or d.horde or name in RAID_LIKE: continue
        dlo, dhi = int(d.lo), int(d.hi)
        if dhi < lo or dlo > hi: continue
        e = d.ent
        if not e: continue
        qs = []
        if d.quests:
            for j in range(1, len(d.quests) + 1):
                qid = int(d.quests[j])
                q = DQ[qid]
                if q is not None and q.fa != "H": qs.append(qid)
        bosses = len(d.bosses) if d.bosses else 6
        out.append(dict(name=name, lo=dlo, hi=dhi, bosses=bosses,
                        entrance=(name + " Entrance", int(e[1]), round(float(e[2]), 1), round(float(e[3]), 1)),
                        quests=qs, dj=str(d.key),
                        run_s=RUN_BASE_S + BOSS_S * min(bosses, MAX_BOSSES), kill_rate=DUNGEON_KILL_RATE, logged=0))
    # Calibrate from logged runs: each dungeon's own run time; one kill-XP rate for all of them.
    runs = load_run_log(wow)
    ratios = []
    for d in out:
        mine = [r for r in runs if r["dungeon"] == d["name"]]
        if not mine: continue
        d["run_s"] = sum(r["secs"] for r in mine) / len(mine) * GOOD_GROUP_TIME
        d["logged"] = len(mine)
        mid = (d["lo"] + d["hi"]) / 2.0          # the log has no level: assume mid-range
        ratios += [r["kill_xp"] / max(r["kill_secs"], 60) * 3600 / grind_xph(mid) for r in mine]
    if ratios and "DUNGEON_KILL_RATE" not in _os.environ:
        rate = sum(ratios) / len(ratios) * GOOD_GROUP
        for d in out: d["kill_rate"] = rate
    return sorted(out, key=lambda d: d["lo"])


def load_run_log(wow):
    """Every logged dungeon run, all characters: dungeon, secs, kill_xp, kill_secs.
    Our own Run Log (RunLog.lua, in RubberDinghyDB.runs), plus runs the old DungeonJournal addon logged
    before ours existed (read as history only)."""
    import glob
    out = []
    for path in glob.glob(wow + r"\WTF\Account\*\*\*\SavedVariables\RubberDinghyRapidLevelGuide.lua"):
        try:
            L = lua51.LuaRuntime(unpack_returned_tuples=True)
            L.execute(open(path, encoding="utf-8", errors="replace").read())
            db = L.globals().RubberDinghyDB
            runs = db and db.runs
            if not runs: continue
            for i in range(1, len(runs) + 1):
                r = runs[i]
                if (r.kills or 0) < 20 or not r.k0 or not r.k1: continue      # too short to say anything
                xp = max(0, (r.xp or 0) - (r.qxp or 0))
                out.append(dict(dungeon=str(r.d), secs=r.k1 - r.k0, kill_xp=xp, kill_secs=r.k1 - r.k0))
        except Exception:
            continue
    for path in glob.glob(wow + r"\WTF\Account\*\*\*\SavedVariables\ForeverDungeonJournal.lua"):
        try:
            L = lua51.LuaRuntime(unpack_returned_tuples=True)
            L.execute(open(path, encoding="utf-8", errors="replace").read())
            db = L.globals().ForeverDungeonJournalCharacterDB
            runs = db and db.runLog and db.runLog.runs
            if not runs: continue
            for i in range(1, len(runs) + 1):
                r = runs[i]
                ks = r.kills
                if not ks or len(ks) < 20: continue
                ts = [ks[j].t for j in range(1, len(ks) + 1)]
                xp = sum(ks[j].x or 0 for j in range(1, len(ks) + 1))
                start = r.created or min(ts)
                end = r.lastSeen or max(ts)
                out.append(dict(dungeon=str(r.dungeon or r.instanceName), secs=end - start, kill_xp=xp,
                                kill_secs=max(ts) - min(ts)))
        except Exception:
            continue
    return out


def tour(points, start=None):
    """Nearest-neighbour tour length (yards) over (map, (x, y)) points on one map."""
    left = list(points)
    if not left: return 0.0
    cur = start or left.pop(0)
    total = 0.0
    while left:
        i = min(range(len(left)), key=lambda k: yards(cur[0], cur[1], left[k][1]))
        total += yards(cur[0], cur[1], left[i][1])
        cur = left.pop(i)
    return total
