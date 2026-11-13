"""Shared route maths for tools/sim.py and tools/plan_route.py: reads Data.lua (via lupa), Questie's
quest XP, the Classic XP table, approximate zone sizes and quest availability rules."""
import math, re
from lupa import lua51

RACE, CLASS = 64, 128          # gnome mage: only used for race/class-locked quests
MOB_FACTOR = 0.45              # kill XP while questing, as a share of quest XP (calibrated: 40->60 ends ~60)

# Continents (uiMapIDs), for travel cost between zones.
KALIMDOR = {1444, 1446, 1449, 1448, 1447, 1452, 1451, 1443, 1441, 1450, 1413, 1438, 1457, 2482, 2652, 1442, 1439, 1440}
EASTERN = {1434, 1417, 1418, 1419, 1427, 1428, 1425, 1422, 1423, 1435, 1424, 1416, 1453, 1455, 2548, 2521, 1431,
           1436, 1433, 1432, 1437, 1420, 1421, 1426, 1429, 1430, 1458}

SIZE = {
    1444: (6950, 4633), 1446: (6900, 4600), 1449: (3700, 2467), 1448: (5750, 3833), 1447: (5070, 3381),
    1452: (7100, 4733), 1451: (3483, 2323), 1443: (4496, 2998), 1434: (6381, 4254), 1417: (3600, 2400),
    1418: (2488, 1658), 1419: (3350, 2233), 1427: (2231, 1488), 1428: (2929, 1952), 1425: (3850, 2567),
    1422: (4300, 2867), 1423: (4031, 2687), 1441: (4400, 2933), 1450: (2308, 1540), 1435: (2294, 1529),
    1424: (3200, 2133), 1416: (2800, 1867), 1413: (10133, 6756), 1438: (5092, 3395), 1453: (1737, 1158),
    1455: (790, 527), 1457: (1058, 706),
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


def available(q, done, lv, allow_class=True):
    if q.get("ra") and not (q["ra"] & RACE): return False
    if q.get("cl") and not (allow_class and (q["cl"] & CLASS)): return False
    if q.get("rep") or q.get("d"): return False
    if (q.get("r") or 0) > lv: return False
    if (q.get("l") or 0) > lv + MAX_ABOVE: return False
    for p in q.get("pg") or []:
        if p > 0 and p not in done: return False
    ps = q.get("ps") or []
    if ps and not any(p in done for p in ps): return False
    if any(p in done for p in (q.get("ex") or [])): return False
    return True


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
