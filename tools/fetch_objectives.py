"""Objectives of quests our data can't place, read from ForeverChanges (foreverchanges.pro) quest pages:
the items, mobs and objects each quest asks for (with their IDs) and the quest's description, which often
names the mob that has what you need ("A naga called Lady Sesspira leads the pillaging"). gen_route.py
places those quests from QuestieDB's spawns of what's named.

Usage:  python tools/fetch_objectives.py Data.lua tools/forever_objectives.json [ids.json [refresh]]
Quests: every open-world quest in Data.lua with objectives (ob=true), or new in Forever, but no place (no o=).
One request a second; quests already in the output file are skipped, so it can be re-run.
"""
import html, json, os, re, sys, time, urllib.request

DATA, OUT = sys.argv[1], sys.argv[2]
src = open(DATA, encoding="utf-8").read()
todo = []
for qid, body in re.findall(r"^  \[(\d+)\]=\{(.*)\},$", src, re.M):
    # objectives but no place; or a Forever quest (IDs from 79000) with no place, whose objectives
    # QuestieDB may not know at all (Reclaiming Ravencrest)
    if " o={" not in body and "d=true" not in body and ("ob=true" in body or int(qid) >= 79000):
        todo.append(int(qid))
found = json.load(open(OUT, encoding="utf-8")) if os.path.exists(OUT) else {}
if len(sys.argv) > 3:   # optional: only these quest IDs (a JSON list), e.g. the route's first
    only = set(json.load(open(sys.argv[3])))
    todo = [q for q in todo if q in only]
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/130.0"
NEED = re.compile(r'<li class="qp-need-item"><a class="qp-(\w+)" href="/(item|npc|object)/(\d+)/[^"]*".*?'
                  r'<span class="qp-\w+-name[^"]*">(.*?)</span>', re.S)
REFRESH = len(sys.argv) > 4 and sys.argv[4] == "refresh"   # fetch the listed IDs again
for q in todo:
    if str(q) in found and not REFRESH: continue
    rec = {"need": [], "desc": ""}
    try:
        req = urllib.request.Request(f"https://foreverchanges.pro/quest/{q}", headers={"User-Agent": UA, "Accept": "text/html"})
        page = urllib.request.urlopen(req, timeout=25).read().decode("utf-8", "replace")
        for _, kind, i, name in NEED.findall(page):
            rec["need"].append([kind, int(i), html.unescape(re.sub(r"<[^>]+>", "", name)).strip()])
        # objectives with no item/mob link: "Spitelash Battlemaster slain: 0/5", "First Power Stone"
        for g in re.findall(r'<li class="qp-need-goal">(.*?)</li>', page, re.S):
            t = html.unescape(re.sub(r"<[^>]+>", "", g)).strip()
            t = re.sub(r":\s*\d+\s*/\s*\d+$", "", t).strip()
            if t: rec["need"].append(["goal", 0, t])
        # the page's map: the zone (uiMap) and dots where the objectives are, in map % (0-100)
        mm = re.search(r'/quests/maps/(\d+)\.webp', page)
        if mm:
            rec["map"] = int(mm.group(1))
            rec["dots"] = [[float(x), float(y)] for x, y in
                           re.findall(r'class="qp-dot" style="left:([\d.]+)%;top:([\d.]+)%"', page)][:120]
        m = re.search(r"<h2>Description</h2>(.*?)</article>", page, re.S)
        if m: rec["desc"] = html.unescape(re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", m.group(1)))).strip()[:1500]
    except Exception as e:
        rec["error"] = str(e)[:100]
        print(q, "error", e, flush=True)
    found[str(q)] = rec
    json.dump(found, open(OUT, "w", encoding="utf-8"), indent=0, ensure_ascii=False)
    time.sleep(1.0)
print(len(todo), "quests;", sum(1 for v in found.values() if v.get("need")), "with objectives listed")
