"""Where ForeverChanges files each Forever quest ("level 45 quest in Shaman" = a shaman class quest).
QuestieDB doesn't mark every Forever class quest as class-only (Challenge of the Desert Wolf sent a mage
to a shaman totem), so gen_route.py turns a class category into the quest's class restriction.

Usage:  python tools/fetch_categories.py Data.lua tools/forever_categories.json
Quests: every Forever quest (ID 79000 and up) on the route with no class restriction (no cl=); --all: every one.
One request a second; quests already in the output file are skipped, so it can be re-run.
"""
import json, os, re, sys, time, urllib.request

DATA, OUT = sys.argv[1], sys.argv[2]
src = open(DATA, encoding="utf-8").read()
steps_part = src[:src.index("ns.quests = {")]
on_route = set(int(x) for x in re.findall(r"\d+", " ".join(re.findall(r"(?:quests|pick)=\{([^}]*)\}", steps_part))))
todo = [int(q) for q, body in re.findall(r"^  \[(\d+)\]=\{(.*)\},$", src, re.M)
        if int(q) >= 79000 and " cl=" not in body and (int(q) in on_route or "--all" in sys.argv)]
found = json.load(open(OUT, encoding="utf-8")) if os.path.exists(OUT) else {}
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/130.0"
for q in todo:
    if str(q) in found: continue
    cat = None
    try:
        req = urllib.request.Request(f"https://foreverchanges.pro/quest/{q}", headers={"User-Agent": UA, "Accept": "text/html"})
        page = urllib.request.urlopen(req, timeout=25).read(40000).decode("utf-8", "replace")
        m = re.search(r"<title>[^<]*?quest in ([^<]+?) (?:·|&middot;|-|\|)", page)
        if m: cat = m.group(1).strip()
    except Exception as e:
        print(q, "error", e, flush=True)
    found[str(q)] = cat
    json.dump(found, open(OUT, "w", encoding="utf-8"), indent=0, ensure_ascii=False)
    time.sleep(1.0)
classes = {"Warrior", "Paladin", "Hunter", "Rogue", "Priest", "Shaman", "Mage", "Warlock", "Druid"}
print(len(todo), "quests;", sum(1 for v in found.values() if v in classes), "class quests found")
