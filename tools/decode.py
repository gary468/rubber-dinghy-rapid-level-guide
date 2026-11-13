"""Step 1 of rebuilding Data.lua: decode QuestieDB (Forever) quests, zone names and the quest blacklist
into data.json. Reads only installed addon files (QuestieDB + Questie), never anyone's saved data.

Usage:  python -I tools/decode.py "<WoW>/_forever_" tools/data.json
"""
import base64, json, re, struct, sys

WOW, OUT = sys.argv[1], sys.argv[2]
TOC = WOW + r"\Interface\AddOns\QuestieDB\QuestieDB_Forever.toc"
ZONES = WOW + r"\Interface\AddOns\Questie\Localization\lookups\lookupZones.lua"
BLACK = WOW + r"\Interface\AddOns\Questie\Database\Corrections\QuestieQuestBlacklist.lua"


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
    else: raise ValueError(f"ai {ai}")
    if mt == 0: return val, i
    if mt == 1: return -1 - val, i
    if mt in (2, 3): s = b[i:i+val]; return s.decode("utf-8", "replace"), i + val
    if mt == 4:
        arr = []
        for _ in range(val): v, i = cbor(b, i); arr.append(v)
        return arr, i
    if mt == 5:
        d = {}
        for _ in range(val):
            k, i = cbor(b, i); v, i = cbor(b, i); d[k] = v
        return d, i
    if mt == 7:
        if ai == 20: return False, i
        if ai == 21: return True, i
        return None, i
    raise ValueError(f"mt {mt}")


def dec(s):
    return cbor(base64.b64decode(s))[0]


meta = {}
with open(TOC, encoding="utf-8", errors="replace") as fh:
    for line in fh:
        if line.startswith("## X-Quest-"):
            k, _, v = line[3:].rstrip("\n").partition(": ")
            meta[k] = v


def get(k):
    v = meta.get(k)
    if v is None: return None
    m = re.fullmatch(r"~(\d+)~", v)
    if m: v = "".join(meta[f"{k}-{n}"] for n in range(1, int(m.group(1)) + 1))
    return v


TABLE_FIELDS = {2: "startedBy", 12: "preQuestGroup", 13: "preQuestSingle", 14: "childQuests", 16: "exclusiveTo",
                18: "requiredSkill", 19: "requiredMinRep", 28: "breadcrumbs"}
SCALAR = {1: "name", 4: "requiredLevel", 5: "questLevel", 6: "requiredRaces", 7: "requiredClasses", 17: "zoneOrSort",
          22: "nextQuestInChain", 23: "questFlags", 24: "specialFlags", 27: "breadcrumbForQuestId",
          32: "requiredMaxLevel", 25: "parentQuest", 34: "availableStartingWith"}
quests = {}
for k in meta:
    m = re.fullmatch(r"X-Quest-(\d+)-S", k)
    if not m: continue
    qid = int(m.group(1))
    row = dec(get(k))
    if isinstance(row, list): row = {i + 1: v for i, v in enumerate(row)}
    q = {"id": qid}
    for idx, nm in SCALAR.items():
        if idx in row: q[nm] = row[idx]
    for idx, nm in TABLE_FIELDS.items():
        v = get(f"X-Quest-{qid}-{idx}")
        if v:
            try: q[nm] = dec(v)
            except Exception as e: q[nm] = f"ERR {e}"
    quests[qid] = q

zones = {}
with open(ZONES, encoding="utf-8", errors="replace") as fh:
    for m in re.finditer(r'\[(-?\d+)\]\s*=\s*"([^"]+)"', fh.read()):
        zones.setdefault(int(m.group(1)), m.group(2))

black = set()
with open(BLACK, encoding="utf-8", errors="replace") as fh:
    for m in re.finditer(r"\[(\d+)\]\s*=\s*true", fh.read()):
        black.add(int(m.group(1)))

json.dump({"quests": quests, "zones": zones, "blacklist": sorted(black)}, open(OUT, "w", encoding="utf-8"))
print(len(quests), "quests;", len(zones), "zones;", len(black), "blacklisted")
