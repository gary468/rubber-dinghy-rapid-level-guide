"""Read-only access to the installed QuestieDB (Forever) for the build scripts: quests, NPCs, objects,
items and the Forever zone tables. QuestieDB stores each record in its TOC as base64 CBOR.

    from questiedb import QDB
    db = QDB(r"C:\\...\\World of Warcraft\\_forever_")
    db.quest(168)["name"], db.npc(644)["spawns"]
"""
import base64, re, struct

# QuestieDB quest fields (questKeys): position -> name
QUEST_KEYS = {1: "name", 2: "startedBy", 3: "finishedBy", 4: "requiredLevel", 5: "questLevel",
              6: "requiredRaces", 7: "requiredClasses", 8: "objectivesText", 10: "objectives",
              11: "sourceItemId", 12: "preQuestGroup", 13: "preQuestSingle", 14: "childQuests",
              16: "exclusiveTo", 17: "zoneOrSort", 21: "requiredSourceItems", 22: "nextQuestInChain",
              23: "questFlags", 24: "specialFlags", 25: "parentQuest", 27: "breadcrumbForQuestId",
              28: "breadcrumbs"}
ALLIANCE_RACES = 1 | 4 | 8 | 64          # Human, Dwarf, Night Elf, Gnome
HORDE_RACES = 2 | 16 | 32 | 128          # Orc, Undead, Tauren, Troll
QUEST_FLAG_SHARABLE = 8


def _cbor(b, i=0):
    ib = b[i]; mt = ib >> 5; ai = ib & 31; i += 1
    if ai < 24: val = ai
    elif ai == 24: val = b[i]; i += 1
    elif ai == 25:
        if mt == 7: return struct.unpack(">e", b[i:i + 2])[0], i + 2
        val = struct.unpack(">H", b[i:i + 2])[0]; i += 2
    elif ai == 26:
        if mt == 7: return struct.unpack(">f", b[i:i + 4])[0], i + 4
        val = struct.unpack(">I", b[i:i + 4])[0]; i += 4
    elif ai == 27:
        if mt == 7: return struct.unpack(">d", b[i:i + 8])[0], i + 8
        val = struct.unpack(">Q", b[i:i + 8])[0]; i += 8
    else: raise ValueError(f"ai {ai}")
    if mt == 0: return val, i
    if mt == 1: return -1 - val, i
    if mt in (2, 3): return b[i:i + val].decode("utf-8", "replace"), i + val
    if mt == 4:
        arr = []
        for _ in range(val):
            v, i = _cbor(b, i); arr.append(v)
        return arr, i
    if mt == 5:
        d = {}
        for _ in range(val):
            k, i = _cbor(b, i); v, i = _cbor(b, i); d[k] = v
        return d, i
    if mt == 7:
        if ai == 20: return False, i
        if ai == 21: return True, i
        return None, i
    raise ValueError(f"mt {mt}")


def pos(v, k):
    """Positional field k (1-based) of a CBOR array or sparse map."""
    if isinstance(v, dict): return v.get(k, v.get(str(k)))
    if isinstance(v, list) and len(v) >= k: return v[k - 1]
    return None


class QDB:
    def __init__(self, wow):
        self.wow = wow
        base = wow + r"\Interface\AddOns\QuestieDB"
        self.meta = {}
        with open(base + r"\QuestieDB_Forever.toc", encoding="utf-8", errors="replace") as fh:
            for line in fh:
                if line.startswith("## X-"):
                    k, _, v = line[3:].rstrip("\n").partition(": ")
                    self.meta[k] = v
        z = base + r"\support\Forever\Zones"
        self.uimap = {}
        for m in re.finditer(r"\[(\d+)\]\s*=\s*(\d+)", open(z + r"\areaIdToUiMapId.lua", encoding="utf-8").read()):
            self.uimap.setdefault(int(m.group(1)), int(m.group(2)))
        self.instance_area = {}
        for m in re.finditer(r"\[(\d+)\]\s*=\s*(\d+)", open(z + r"\instanceIdToAreaId.lua", encoding="utf-8").read()):
            self.instance_area[int(m.group(1))] = int(m.group(2))
        # dungeons.lua: [area] = {"Name", {alt areas}|nil, parentArea, {{area, x, y}, ...}}
        self.dungeons = {}
        src = open(z + r"\dungeons.lua", encoding="utf-8").read()
        for m in re.finditer(r'\[(\d+)\]\s*=\s*\{"([^"]+)",(nil|\{[\d,]*\}),(\d+),\{(.*?)\}\},?', src):
            alts = [int(a) for a in re.findall(r"\d+", m.group(3))] if m.group(3) != "nil" else []
            ents = [(int(a), float(x), float(y)) for a, x, y in
                    re.findall(r"\{(\d+),\s*([\d.]+),\s*([\d.]+)", "{" + m.group(5))]
            self.dungeons[int(m.group(1))] = dict(name=m.group(2), alts=alts, parent=int(m.group(4)), entrances=ents)
        self._cache = {}

    def raw(self, k):
        v = self.meta.get(k)
        if v is None: return None
        m = re.fullmatch(r"~(\d+)~", v)
        if m: v = "".join(self.meta[f"{k}-{n}"] for n in range(1, int(m.group(1)) + 1))
        return _cbor(base64.b64decode(v))[0]

    def ids(self, kind):
        rx = re.compile(rf"X-{kind}-(\d+)-S$")
        return sorted(int(m.group(1)) for k in self.meta for m in [rx.match(k)] if m)

    def quest(self, qid):
        key = ("q", qid)
        if key in self._cache: return self._cache[key]
        row = self.raw(f"X-Quest-{qid}-S")
        if row is None:
            self._cache[key] = None; return None
        if isinstance(row, list): row = {i + 1: v for i, v in enumerate(row)}
        q = {"id": qid}
        for idx, nm in QUEST_KEYS.items():
            v = row.get(idx, row.get(str(idx))) if isinstance(row, dict) else None
            if v is None:
                v = self.raw(f"X-Quest-{qid}-{idx}")
            if v not in (None, [], {}): q[nm] = v
        self._cache[key] = q
        return q

    def npc(self, i):
        key = ("n", i)
        if key in self._cache: return self._cache[key]
        row = self.raw(f"X-Npc-{i}-S")
        if row is None:
            self._cache[key] = None; return None
        sp = self.raw(f"X-Npc-{i}-7") or {}
        e = dict(id=i, name=pos(row, 1), lo=pos(row, 4) or 0, hi=pos(row, 5) or 0, rank=pos(row, 6) or 0,
                 zone=pos(row, 9), spawns={int(a): c for a, c in sp.items()} if isinstance(sp, dict) else {})
        self._cache[key] = e
        return e

    def obj(self, i):
        key = ("o", i)
        if key in self._cache: return self._cache[key]
        row = self.raw(f"X-Object-{i}-S")
        if row is None:
            self._cache[key] = None; return None
        sp = self.raw(f"X-Object-{i}-4") or {}
        e = dict(id=i, name=pos(row, 1), zone=pos(row, 5),
                 spawns={int(a): c for a, c in sp.items()} if isinstance(sp, dict) else {})
        self._cache[key] = e
        return e

    def item(self, i):
        key = ("i", i)
        if key in self._cache: return self._cache[key]
        row = self.raw(f"X-Item-{i}-S")
        if row is None:
            self._cache[key] = None; return None
        e = dict(id=i, name=pos(row, 1), npcs=self.raw(f"X-Item-{i}-2") or [], objects=self.raw(f"X-Item-{i}-3") or [])
        self._cache[key] = e
        return e
