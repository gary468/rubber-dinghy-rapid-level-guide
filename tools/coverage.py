"""Coverage report: every Alliance-available quest at levels 40-60 in QuestieDB vs. what Data.lua routes.
Usage:  python -I tools/coverage.py tools "<WoW>/_forever_" Data.lua
"""
import collections, re, sys

HERE, WOW, DATA = sys.argv[1], sys.argv[2], sys.argv[3]
sys.argv = [None, HERE, WOW, "unused"]
src = open(HERE + r"\gen_route.py", encoding="utf-8").read()
exec(src.split("givers = {}")[0])  # decoder, Q, eligible(), loc_of(), uimap, dungeons

data_text = open(DATA, encoding="utf-8").read()
in_data = {int(m.group(1)) for m in re.finditer(r"^\s+\[(\d+)\]=\{", data_text, re.M)}
tm = re.search(r"^ns\.track = \{([^}]*)\}", data_text, re.M)
tracked = {int(x) for x in tm.group(1).split(",") if x.strip()} if tm else set()
routed = in_data - tracked
zone_names = {int(k): v for k, v in json.load(open(HERE + r"\data.json", encoding="utf-8"))["zones"].items()}
XP = {}
for fn in ("xpDB-classic.lua", "xpDB-traces.lua"):
    p = WOW + r"\Interface\AddOns\QuestieDB\support\Forever\QuestXP" + "\\" + fn
    for m in re.finditer(r"\[(\d+)\]\s*=\s*\{\s*(-?\d+)\s*,\s*(\d+)", open(p, encoding="utf-8").read()):
        XP.setdefault(int(m.group(1)), int(m.group(3)))

step_zones = {z for st in STEPS for z in st["zones"]}
total, missing = 0, collections.defaultdict(list)
why = collections.Counter()
for qid, q in Q.items():
    if not eligible(qid, q): continue
    lvl = q.get("questLevel") or 0
    if not (40 <= lvl <= 60): continue
    if (q.get("specialFlags") or 0) & 1: continue           # repeatables aren't "quests to do"
    sb = get(f"X-Quest-{qid}-2")
    g = loc_of(sb) if sb else None
    if g and g.get("fac") and "A" not in str(g["fac"]): continue
    total += 1
    if qid in routed: continue
    if qid in tracked:
        why["tracked once accepted (not suggested)"] += 1
        continue
    area = g["area"] if g else None
    if g is None or area is None: reason = "no quest giver in the database"
    elif g["name"] == "(item drop)": reason = "starts from an item drop"
    elif area in dungeons or (q.get("zoneOrSort") or 0) in dungeons: reason = "dungeon quest"
    elif area not in step_zones: reason = "giver's zone isn't on the route"
    else: reason = "other filter (level window)"
    why[reason] += 1
    zname = zone_names.get(area, f"area {area}") if area else "-"
    missing[(reason, zname)].append((lvl, q.get("name"), qid, XP.get(qid, 0)))

print(f"Alliance quests, level 40-60 (not repeatable): {total}")
print(f"Routed in a step: {total - sum(why.values())}   Otherwise: {sum(why.values())}")
for r, n in why.most_common(): print(f"  {n:4} {r}")
print("\nNot routed, by zone (quest count, base XP):")
rows = sorted(missing.items(), key=lambda kv: -sum(x[3] for x in kv[1]))
for (reason, zname), qs in rows[:40]:
    lv = [x[0] for x in qs]
    print(f"  {zname[:26]:26} {len(qs):3} quests  lvl {min(lv)}-{max(lv)}  {sum(x[3] for x in qs):>8,} xp   [{reason}]")
