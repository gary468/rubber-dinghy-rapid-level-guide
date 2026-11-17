"""Travel times between any two places, from the game's real geography (tools/geo.json, saved in game
by Geo.lua) - the route planner's map of the world.

A place is (uiMapID, x, y) with x, y in 0-100. travel_s(a, b, level) returns the fastest of:
  * going straight there (running before level 40, mounted from 40);
  * flying: to the nearest Alliance/neutral flight master, fly, and on from the landing one;
  * for another continent: the boats and the tram, with flights either side.
Flight time between two flight masters: what players' recorded flights say (learned.json "legs"),
else the straight distance at gryphon speed times a detour factor.
"""
import json, math, os

HERE = os.path.dirname(os.path.abspath(__file__))
RUN_YDS, MOUNT_YDS = 7.0, 11.2          # yd/s: run speed, 60% mount
MOUNT_LEVEL = 40
FLY_YDS, FLY_DETOUR = 30.0, 1.25        # gryphon speed; flight paths aren't straight
FM_OVERHEAD_S = 25                      # talk to the flight master, take off, land
WALK_DETOUR = 1.3                       # ground travel isn't a straight line (hills, roads, mobs)
BOAT_WAIT_S, BOAT_RIDE_S, TRAM_S = 150, 150, 120
ALLIANCE = {0, 2}                       # Enum.FlightPathFaction: 0 neutral, 1 Horde, 2 Alliance

# Boats and the tram, Alliance side. Dock positions are zone %, from the game's maps; verify in game
# (Learn.lua could record them). (from place, to place, seconds incl. waiting)
LINKS = [
    ((1437, 4.6, 57.1), (1439, 32.4, 43.8), BOAT_WAIT_S + BOAT_RIDE_S),   # Menethil <-> Auberdine
    ((1437, 5.0, 63.4), (1445, 71.6, 56.4), BOAT_WAIT_S + BOAT_RIDE_S),   # Menethil <-> Theramore
    ((1434, 25.9, 73.1), (1413, 63.7, 38.6), BOAT_WAIT_S + BOAT_RIDE_S),  # Booty Bay <-> Ratchet
    ((1439, 33.2, 40.2), (1438, 54.9, 96.8), 90 + 60),                    # Auberdine <-> Rut'theran
    ((1453, 63.3, 8.4), (1455, 76.6, 51.2), TRAM_S),                      # Stormwind <-> Ironforge tram
]

_geo = None
_legs = {}


def load(geo_path=None, learned_path=None):
    global _geo, _legs, FM
    _geo = json.load(open(geo_path or os.path.join(HERE, "geo.json"), encoding="utf-8"))
    _geo["maps"] = {int(k): v for k, v in _geo["maps"].items()}
    lp = learned_path or os.path.join(HERE, "learned.json")
    if os.path.exists(lp):
        _legs = json.load(open(lp)).get("legs") or {}
    FM = []
    for n in _geo["taxi"]:
        if n.get("faction") not in ALLIANCE: continue
        cont_map = n["map"]
        r = _geo["maps"].get(cont_map)
        if not r: continue
        # the game's world X runs along the map's vertical axis, world Y along its horizontal one
        wx = r["x1"] + (r["x2"] - r["x1"]) * n["y"]
        wy = r["y1"] + (r["y2"] - r["y1"]) * n["x"]
        FM.append({"name": n["name"], "cont": r["cont"], "w": (wx, wy)})
    return _geo


FM = []


def world(p):
    """(map, x, y) -> (continent, wx, wy) or None when the map isn't on a continent we know."""
    r = _geo["maps"].get(p[0])
    if not r or r.get("cont") is None: return None
    # world X follows the map's vertical axis (y), world Y its horizontal one (x)
    return r["cont"], r["x1"] + (r["x2"] - r["x1"]) * p[2] / 100.0, r["y1"] + (r["y2"] - r["y1"]) * p[1] / 100.0


def _dist(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


def ground_s(wa, wb, level):
    speed = MOUNT_YDS if level >= MOUNT_LEVEL else RUN_YDS
    return _dist(wa, wb) * WALK_DETOUR / speed


def _nearest_fm(cont, w, k=2):
    c = [f for f in FM if f["cont"] == cont]
    c.sort(key=lambda f: _dist(f["w"], w))
    return c[:k]


def flight_s(fa, fb):
    if fa is fb or fa["name"] == fb["name"]: return 0.0
    learned = _legs.get(f"{fa['name']}|{fb['name']}") or _legs.get(f"{fb['name']}|{fa['name']}")
    if learned: return float(learned)
    return _dist(fa["w"], fb["w"]) * FLY_DETOUR / FLY_YDS


def same_continent_s(ca, wa, wb, level):
    """Fastest within one continent: straight there, or via flight masters. Returns (secs, via)."""
    best, via = ground_s(wa, wb, level), None
    for fa in _nearest_fm(ca, wa):
        for fb in _nearest_fm(ca, wb):
            if fa["name"] == fb["name"]: continue
            t = ground_s(wa, fa["w"], level) + FM_OVERHEAD_S + flight_s(fa, fb) + ground_s(fb["w"], wb, level)
            if t < best: best, via = t, (fa["name"], fb["name"])
    return best, via


UNKNOWN_HOP_S = 600     # a place not on either continent's map (e.g. an island zone): a flat guess

# ---- Mountains (TerrainData.lua, as the addon uses them): walking inside a zone with a grid follows
# the valley floor round ridges; valleys the grid doesn't join cost the straight line plus CROSS_PCT
# of the map (the same rule as Terrain.lua), so a flight can win. Gary 17 Nov, Mount Hyjal: "the
# mountains block the quests".
TERRAIN_DETOUR = 1.1    # the grid already walks round the ridges; a little for the rest
CROSS_PCT = 30
_grids = {}


def _load_terrain():
    import re
    p = os.path.join(HERE, "..", "TerrainData.lua")
    if not os.path.exists(p): return
    src = open(p, encoding="utf-8").read()
    for m in re.finditer(r"\[(\d+)\]\s*=\s*\{\s*n\s*=\s*(\d+),\s*rows\s*=\s*\{([^}]*)\}", src):
        rows = re.findall(r'"([01]+)"', m.group(3))
        n = int(m.group(2))
        walk = {(i, j) for j, r in enumerate(rows) for i, c in enumerate(r) if c == "1"}
        comp = {}
        cid = 0
        for c0 in walk:
            if c0 in comp: continue
            cid += 1
            comp[c0] = cid
            st = [c0]
            while st:
                i, j = st.pop()
                for di in (-1, 0, 1):
                    for dj in (-1, 0, 1):
                        k = (i + di, j + dj)
                        if k in walk and k not in comp:
                            comp[k] = cid
                            st.append(k)
        _grids[int(m.group(1))] = {"n": n, "walk": walk, "comp": comp, "paths": {}}


def _snap(g, x, y):
    n = g["n"]
    ci, cj = min(n - 1, max(0, int(x / 100 * n))), min(n - 1, max(0, int(y / 100 * n)))
    for r in range(0, 5):
        best = None
        for j in range(cj - r, cj + r + 1):
            for i in range(ci - r, ci + r + 1):
                if (i, j) in g["walk"]:
                    d = (i - ci) ** 2 + (j - cj) ** 2
                    if best is None or d < best[0]: best = (d, (i, j))
        if best: return best[1]


def _paths(g, src):
    hit = g["paths"].get(src)
    if hit is not None: return hit
    import heapq
    dist, pq = {src: 0.0}, [(0.0, src)]
    while pq:
        d, (i, j) = heapq.heappop(pq)
        if d > dist[(i, j)]: continue
        for di in (-1, 0, 1):
            for dj in (-1, 0, 1):
                if not di and not dj: continue
                k = (i + di, j + dj)
                if k in g["walk"]:
                    nd = d + (1.4142135623730951 if di and dj else 1.0)
                    if nd < dist.get(k, 1e18):
                        dist[k] = nd
                        heapq.heappush(pq, (nd, k))
    g["paths"][src] = dist
    return dist


def terrain_pct(m, a, b):
    """Map-% walking distance between (x, y) points a and b on map m, or None without a grid."""
    g = _grids.get(m)
    if not g: return None
    straight = math.hypot(a[0] - b[0], a[1] - b[1])
    sa, sb = _snap(g, *a), _snap(g, *b)
    if not sa or not sb: return straight
    if g["comp"][sa] != g["comp"][sb]: return straight + CROSS_PCT
    d = _paths(g, sa).get(sb)
    if d is None: return straight + CROSS_PCT
    return max(straight, d * 100.0 / g["n"])


def _terrain_walk_s(m, a, b, level):
    import routelib as R
    speed = MOUNT_YDS if level >= MOUNT_LEVEL else RUN_YDS
    straight_pct = math.hypot(a[0] - b[0], a[1] - b[1])
    if straight_pct < 1e-9: return 0.0
    yd = R.yards(m, a, b) * terrain_pct(m, a, b) / straight_pct
    return yd * TERRAIN_DETOUR / speed


def _zone_pct(m, w):
    """World (wx, wy) -> (x, y) map % on map m, or None when outside it."""
    r = _geo["maps"].get(m)
    if not r or r["x2"] == r["x1"] or r["y2"] == r["y1"]: return None
    y = (w[0] - r["x1"]) / (r["x2"] - r["x1"]) * 100.0
    x = (w[1] - r["y1"]) / (r["y2"] - r["y1"]) * 100.0
    if 0 <= x <= 100 and 0 <= y <= 100: return x, y


def travel_s(a, b, level=60):
    """Seconds from place a to place b (each (map, x, y))."""
    if a is None or b is None: return 0.0
    if a[0] == b[0] and abs(a[1] - b[1]) < 1e-9 and abs(a[2] - b[2]) < 1e-9: return 0.0
    if not _grids and _geo is not None: _load_terrain()
    if a[0] == b[0] and a[0] in _grids:
        # inside a zone with mountains: the valley-floor walk, or fly between its flight masters
        m = a[0]
        best = _terrain_walk_s(m, a[1:], b[1:], level)
        A, B = world(a), world(b)
        if A and B:
            def leg(p, fm):
                fp = _zone_pct(m, fm["w"])
                if fp: return _terrain_walk_s(m, p[1:], fp, level)
                return ground_s(world(p)[1:], fm["w"], level)
            for fa in _nearest_fm(A[0], A[1:], 3):
                for fb in _nearest_fm(B[0], B[1:], 3):
                    if fa["name"] == fb["name"]: continue
                    best = min(best, leg(a, fa) + FM_OVERHEAD_S + flight_s(fa, fb) + leg(b, fb))
        return best
    A, B = world(a), world(b)
    if not A or not B:
        # a zone not on either continent's map (an island like Zephras Isle): inside it, straight
        # distance from its size; in or out of it, a flat guess (boat or flight + waiting)
        if a[0] == b[0]:
            import routelib as R
            speed = MOUNT_YDS if level >= MOUNT_LEVEL else RUN_YDS
            return R.yards(a[0], (a[1], a[2]), (b[1], b[2])) * WALK_DETOUR / speed
        return UNKNOWN_HOP_S
    if A[0] == B[0]:
        return same_continent_s(A[0], A[1:], B[1:], level)[0]
    best = float("inf")
    for la, lb, secs in LINKS:
        for x, y in ((la, lb), (lb, la)):
            X, Y = world(x), world(y)
            if not X or not Y or X[0] != A[0] or Y[0] != B[0]: continue
            t = same_continent_s(A[0], A[1:], X[1:], level)[0] + secs + same_continent_s(B[0], Y[1:], B[1:], level)[0]
            best = min(best, t)
    return best if best < float("inf") else UNKNOWN_HOP_S * 2


if __name__ == "__main__":
    load()
    tests = [("Aerie Peak -> Booty Bay", (1425, 14.8, 44.6), (1434, 27.1, 77.4)),
             ("Aerie Peak -> Skulk Rock", (1425, 14.8, 44.6), (1425, 58.3, 41.3)),
             ("Ironforge -> Tanaris", (1455, 55, 47), (1446, 51, 27)),
             ("Darnassus -> Hinterlands", (1457, 40, 50), (1425, 14.8, 44.6))]
    for name, a, b in tests:
        print(f"{name}: {travel_s(a, b, 51) / 60:.1f} min")
