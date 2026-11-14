"""Builds Data_Dungeons.lua: our own dungeon journal data (dungeons, bosses, quests).

Usage:  python -I tools/gen_dungeons.py "<WoW>/_forever_" Data_Dungeons.lua

Sources, all licensed or public facts (never the DungeonJournal addon, which has no licence):
  * QuestieDB (GPLv3, installed in the client): dungeon area/instance IDs and entrances, every quest
    (giver, ender, chain, objective text, shareable flag, races/classes), NPC levels, quest XP.
  * DUNGEONS below: level ranges and boss names. Classic dungeons: Wowhead Classic. WoW Forever's
    new dungeons: Blizzard's dungeon announcement (via Icy Veins / pcgames.de) and Warcraft Tavern's
    Forever dungeon guides. In game the addon prefers the game's own Encounter Journal (boss list,
    descriptions, portraits) and LFG level ranges when the client has them.
The same table feeds the route planner (tools/routelib.load_dungeons).
"""
import math, os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from questiedb import QDB, pos, ALLIANCE_RACES, HORDE_RACES, QUEST_FLAG_SHARABLE

# name: as the route names it (wings "Place: Wing"). area: QuestieDB area IDs (the dungeon's quests
# have it as their zone). inst: the game's instance IDs. ent: (uiMapID, x, y) only where QuestieDB
# has none. quests: quest names to add by hand (Forever dungeons QuestieDB doesn't zone yet), matched
# to QuestieDB IDs by name. bosses: in the order you meet them.
DUNGEONS = [
    dict(name="Ragefire Chasm", key="rfc", lo=13, hi=18, area=2437, inst=389, horde=True,
         bosses=["Oggleflint", "Taragaman the Hungerer", "Jergosh the Invoker", "Bazzalan"]),
    dict(name="Hall of Thanes", key="hall", lo=13, hi=18, area=16919, inst=3065, forever=True,
         ej=["The Hall of Thanes"], ent=(1455, 43.5, 52.0),   # Warcraft Tavern: the passage in Ironforge
         bosses=["Faldrim Anvilmar", "Magmatus", "Plunder", "Durgen Dirgehammer"],
         quests=["Important Heirlooms", "The Restless Dead", "Old Ironforge Incursion", "An Ancient Grudge",
                 "The Treaty of Understanding"]),
    dict(name="Ruins of Lordaeron", key="rol", lo=15, hi=20, area=16611, inst=2999, forever=True,
         bosses=["Witherfang", "The Baron", "Viktor the Vile", "The Abandoned", "Bjork", "Rath'mael"],
         quests=["Abominable Creatures", "Bloodied Insignia", "Remember That I Love You", "Crest of Lordaeron",
                 "Light's Justice", "The New Plague", "The Wrath of Rath'mael", "A Frightened Request",
                 "Unending Torment"]),
    dict(name="Wailing Caverns", key="wc", lo=17, hi=24, area=718, inst=43,
         bosses=["Lady Anacondra", "Lord Cobrahn", "Kresh", "Lord Pythas", "Skum", "Lord Serpentis",
                 "Verdan the Everliving", "Mutanus the Devourer"]),
    dict(name="The Deadmines", key="dm", lo=17, hi=26, area=1581, inst=36,
         bosses=["Rhahk'Zor", "Sneed's Shredder", "Sneed", "Gilnid", "Mr. Smite", "Captain Greenskin",
                 "Edwin VanCleef", "Cookie"]),
    dict(name="Shadowfang Keep", key="sfk", lo=22, hi=30, area=209, inst=33,
         bosses=["Rethilgore", "Razorclaw the Butcher", "Baron Silverlaine", "Commander Springvale",
                 "Odo the Blindwatcher", "Fenrus the Devourer", "Wolf Master Nandos", "Archmage Arugal"]),
    dict(name="Blackfathom Deeps", key="bfd", lo=24, hi=32, area=719, inst=48,
         bosses=["Ghamoo-ra", "Lady Sarevess", "Gelihast", "Lorgus Jett", "Baron Aquanis",
                 "Twilight Lord Kelris", "Old Serra'kis", "Aku'mai"]),
    dict(name="The Stockade", key="stocks", lo=24, hi=32, area=717, inst=34,
         bosses=["Targorr the Dread", "Kam Deepfury", "Hamhock", "Bazil Thredd", "Dextren Ward"]),
    dict(name="Excavation Site: Wetlands", key="exca", lo=24, hi=29, area=16732, inst=2998, forever=True,
         bosses=["Saltspine", "Shadetooth", "Highland Horror", "Relic Guardian"],
         quests=["Songblade Search", "Lost in the Thicket Things", "Highland Hides", "Horrors in the Highland",
                 "Lost Relic Carry", "Changing Tastes", "Open the Maw", "Elder Knowledge"]),
    dict(name="City of Dalaran", key="dala", lo=28, hi=33, area=16544, inst=2959, forever=True,
         bosses=["Atrexis the Grave Knight", "Lyn the Ignored", "Mana Devourer", "Arcane Anomaly", "Fel Ancient",
                 "Arcanic Enigma", "Unstable Sentry", "Shade of the Archmage"],
         quests=["Power Overwhelming", "A Green Sample", "Starving Arcane", "Heart of Disruption",
                 "Source of Power", "The Grave Knight", "Opportunistic Education"]),
    dict(name="Gnomeregan", key="gnomer", lo=29, hi=38, area=721, inst=90,
         bosses=["Grubbis", "Viscous Fallout", "Electrocutioner 6000", "Crowd Pummeler 9-60",
                 "Mekgineer Thermaplugg"]),
    dict(name="Razorfen Kraul", key="rfk", lo=29, hi=38, area=491, inst=47,
         bosses=["Roogug", "Aggem Thorncurse", "Death Speaker Jargba", "Overlord Ramtusk",
                 "Agathelos the Raging", "Charlga Razorflank"]),
    dict(name="Scarlet Monastery: Graveyard", key="smgy", place="Scarlet Monastery", wing="Graveyard",
         lo=26, hi=36, area=796, inst=189, bosses=["Interrogator Vishas", "Bloodmage Thalnos"]),
    dict(name="Scarlet Monastery: Library", key="lib", place="Scarlet Monastery", wing="Library",
         lo=29, hi=39, area=796, inst=189, bosses=["Houndmaster Loksey", "Arcanist Doan"]),
    dict(name="Scarlet Monastery: Armory", key="arm", place="Scarlet Monastery", wing="Armory",
         lo=32, hi=42, area=796, inst=189, bosses=["Herod"]),
    dict(name="Scarlet Monastery: Cathedral", key="cath", place="Scarlet Monastery", wing="Cathedral",
         lo=35, hi=45, area=796, inst=189,
         bosses=["High Inquisitor Fairbanks", "Scarlet Commander Mograine", "High Inquisitor Whitemane"]),
    dict(name="The Drowned City", key="drowned", lo=35, hi=40, forever=True, ent=(1434, 21.4, 27.9),
         bosses=["Zul'Alai", "Var'Taka", "Captain Dreadrise", "Deathless Marrow", "Primeval Elemental",
                 "Min'loth the Serpent"],
         quests=["Magics of the Drowned City", "Take Two With Water", "Ancient Gurubashi Secrets",
                 "Ancient Gurubashi Idol", "The Drowned City", "The Only Good Brinescale",
                 "Shady Saltseers", "The Saltseer Captain"]),
    dict(name="Razorfen Downs", key="rfd", lo=37, hi=46, area=722, inst=129,
         bosses=["Tuten'kash", "Mordresh Fire Eye", "Glutton", "Amnennar the Coldbringer"]),
    dict(name="Krol'dok Stronghold", key="kroldok", lo=40, hi=45, forever=True, ent=(2548, 37.5, 37.5),
         bosses=["Slavecrusher Grox", "Twilight Commander Zarmok", "War Handler Ashka", "Nar'gurk",
                 "Bossman Toof", "Overlord Mugg"],
         quests=["Eye of Mugg", "Tome of Twilight", "Twilight Mementos", "Vengeance of the Highborne",
                 "Krol'dok Moulding", "A Token of Vengeance"]),
    dict(name="Uldaman", key="ulda", lo=41, hi=51, area=1337, inst=70,
         bosses=["Revelosh", "Ironaya", "Obsidian Sentinel", "Ancient Stone Keeper", "Galgann Firehammer",
                 "Grimlok", "Archaedas"]),
    dict(name="Zul'Farrak", key="zf", lo=44, hi=54, area=1176, inst=209,
         bosses=["Antu'sul", "Theka the Martyr", "Witch Doctor Zum'rah", "Nekrum Gutchewer",
                 "Shadowpriest Sezz'ziz", "Sergeant Bly", "Hydromancer Velratha", "Chief Ukorz Sandscalp",
                 "Gahz'rilla"]),
    dict(name="Maraudon", key="mara", lo=46, hi=55, area=2100, inst=349,
         bosses=["Noxxion", "Razorlash", "Lord Vyletongue", "Celebras the Cursed", "Landslide",
                 "Tinkerer Gizlock", "Rotgrip", "Princess Theradras"]),
    dict(name="Alcaz Prison", key="alcaz", lo=48, hi=53, forever=True, ent=(1445, 75.0, 15.0),
         bosses=["Tidemistress Ca'zass", "Overseer Wrex", "Katerina the Cleaner", "Zarla Ober", "The Questioner"],
         quests=["A Bit of Wet Work", "The Dragon's Journal", "The Secret Prison", "The Man in the Iron Chains",
                 "More Valuable Than Gold", "A Little Payback", "Blood Red Bandanas", "No Orc Left Behind",
                 "The Honor of the Kor'kron", "Bad News for Folkar"]),
    dict(name="Sunken Temple", key="st", lo=50, hi=60, area=1477, inst=109, ej=["The Temple of Atal'Hakkar"],
         bosses=["Atal'alarion", "Dreamscythe", "Weaver", "Jammal'an the Prophet", "Ogom the Wretched",
                 "Morphaz", "Hazzas", "Shade of Eranikus", "Avatar of Hakkar"]),
    dict(name="Blackrock Depths", key="brd", lo=52, hi=60, area=1584, inst=230,
         bosses=["Lord Roccor", "High Interrogator Gerstahn", "Houndmaster Grebmar", "Bael'Gar",
                 "Lord Incendius", "Fineous Darkvire", "General Angerforge", "Golem Lord Argelmach",
                 "Hurley Blackbreath", "Phalanx", "Ribbly Screwspigot", "Plugger Spazzring",
                 "Ambassador Flamelash", "Magmus", "Emperor Dagran Thaurissan"]),
    dict(name="Lower Blackrock Spire", key="lbrs", place="Blackrock Spire", wing="Lower", lo=55, hi=60,
         area=1583, inst=229,
         bosses=["Highlord Omokk", "Shadow Hunter Vosh'gajin", "War Master Voone", "Mother Smolderweb",
                 "Urok Doomhowl", "Quartermaster Zigris", "Halycon", "Gizrul the Slavener", "Overlord Wyrmthalak"]),
    dict(name="Upper Blackrock Spire", key="ubrs", place="Blackrock Spire", wing="Upper", lo=55, hi=60,
         area=1583, inst=229, raidlike=True,
         bosses=["Pyroguard Emberseer", "Solakar Flamewreath", "Warchief Rend Blackhand", "The Beast",
                 "General Drakkisath"]),
    dict(name="Dire Maul: East", key="dme", place="Dire Maul", wing="East", lo=55, hi=60, area=2557, inst=429,
         bosses=["Pusillin", "Zevrim Thornhoof", "Hydrospawn", "Lethtendris", "Alzzin the Wildshaper"]),
    dict(name="Blackmaw Hold", key="blackmaw", lo=55, hi=60, forever=True, ent=(1447, 38.7, 33.4),
         bosses=["Varrox Bleakhoof"],
         quests=["Blackmaw Reclamation", "Blackmaw Magic"]),
    dict(name="Dire Maul: West", key="dmw", place="Dire Maul", wing="West", lo=57, hi=60, area=2557, inst=429,
         bosses=["Tendris Warpwood", "Illyanna Ravenoak", "Magister Kalendris", "Immol'thar",
                 "Prince Tortheldrin"]),
    dict(name="Dire Maul: North", key="dmn", place="Dire Maul", wing="North", lo=57, hi=60, area=2557, inst=429,
         bosses=["Guard Mol'dar", "Stomper Kreeg", "Guard Fengus", "Guard Slip'kik", "Captain Kromcrush",
                 "King Gordok"]),
    dict(name="Stratholme: Living", key="stratliving", place="Stratholme", wing="Living", lo=58, hi=60,
         area=2017, inst=329,
         bosses=["The Unforgiven", "Timmy the Cruel", "Malor the Zealous", "Cannon Master Willey",
                 "Archivist Galford", "Balnazzar"]),
    dict(name="Stratholme: Undead", key="stratundead", place="Stratholme", wing="Undead", lo=58, hi=60,
         area=2017, inst=329,
         bosses=["Magistrate Barthilas", "Nerub'enkan", "Baroness Anastari", "Maleki the Pallid",
                 "Ramstein the Gorger", "Baron Rivendare"]),
    dict(name="Scholomance", key="scholo", lo=58, hi=60, area=2057, inst=289,
         bosses=["Kirtonos the Herald", "Jandice Barov", "Rattlegore", "Marduk Blackpool", "Vectus",
                 "Ras Frostwhisper", "Instructor Malicia", "Doctor Theolen Krastinov", "Lorekeeper Polkelt",
                 "The Ravenian", "Lord Alexei Barov", "Lady Illucia Barov", "Darkmaster Gandling"]),
    dict(name="Shaper's Terrace", key="shaper", lo=58, hi=60, forever=True, ent=(1449, 48.1, 6.1),
         ej=["The Shaper's Terrace"], bosses=["Bolt", "Cinder", "Snowtalon", "Nanaya"]),
]

# Wing-specific quests in multi-wing places (QuestieDB zones them all to the place): the wing whose
# boss or mobs the quest is about, from Wowhead Classic's quest pages.
WING_QUESTS = {
    "Scarlet Monastery: Graveyard": ["Vorrel's Revenge", "In the Name of the Light"],
    "Scarlet Monastery: Library": ["Mythology of the Titans", "Rituals of Power", "Compendium of the Fallen",
                                   "Down the Scarlet Path", "Hearts of Zeal", "Test of Lore", "Answered Questions"],
    "Scarlet Monastery: Armory": ["Into The Scarlet Monastery", "The Scarlet Hammer"],
    "Scarlet Monastery: Cathedral": ["In the Name of the Light", "Into The Scarlet Monastery"],
    "Dire Maul: East": ["Pusillin and the Elder Azj'Tordin", "Lethtendris's Web", "The Madness Within",
                        "Shards of the Felvine", "A Broken Trap"],
    "Dire Maul: West": ["The Treasure of the Shen'dralar", "Elven Legends", "The Prince's Gem",
                        "Unfinished Business", "The Shen'dralar Ancient"],
    "Dire Maul: North": ["The Gordok Ogre Suit", "Gordok Ogre Suit", "The Gordok Taste Test", "Free Knot!",
                         "Unfinished Gordok Business"],
    "Lower Blackrock Spire": ["Warlord's Command", "Bijou's Belongings", "Message to Maxwell",
                              "Maxwell's Mission", "Urok Doomhowl", "Kibler's Exotic Pets", "Mother's Milk",
                              "Spire Spider Eggs", "Bijou's Reconnaissance Report", "Bijou's Belongings",
                              "The Matron Protectorate", "Seal of Ascension"],
    "Upper Blackrock Spire": ["General Drakkisath's Command", "General Drakkisath's Demise",
                              "The Darkstone Tablet", "Blackhand's Command", "The Last Element"],
    "Stratholme: Living": ["The Archivist", "Of Love and Family", "Houses of the Holy", "The Medallion of Faith",
                           "Hearthsong", "The Truth Comes Crashing Down", "Aurius' Reckoning"],
    "Stratholme: Undead": ["Dead Man's Plea", "Ramstein", "Of Lost Honor", "Menethil's Gift", "Above and Beyond",
                           "The Great Fras Siabi"],
}

RACE_MASK = ALLIANCE_RACES | HORDE_RACES


def lstr(s):
    s = str(s).replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ")
    return '"' + s + '"'


def main(wow, out_path):
    db = QDB(wow)
    xp = {}
    xpfile = wow + r"\Interface\AddOns\QuestieDB\support\Forever\QuestXP\xpDB-classic.lua"
    for m in re.finditer(r"\[(\d+)\]\s*=\s*\{(\d+),\s*(\d+)\}", open(xpfile, encoding="utf-8").read()):
        xp[int(m.group(1))] = (int(m.group(2)), int(m.group(3)))
    qids = db.ids("Quest")
    quests = {q: db.quest(q) for q in qids}
    by_name = {}
    for q in quests.values():
        if q and q.get("name"): by_name.setdefault(q["name"].lower(), []).append(q["id"])
    black = set()
    try:
        bl = wow + r"\Interface\AddOns\Questie\Database\Corrections\QuestieQuestBlacklist.lua"
        black = {int(m.group(1)) for m in re.finditer(r"\[(\d+)\]\s*=\s*true", open(bl, encoding="utf-8").read())}
    except FileNotFoundError:
        pass

    def area_set(d):
        a = d.get("area")
        if not a: return set()
        s = {a} | set((db.dungeons.get(a) or {}).get("alts") or [])
        return s

    def where(givers, kind_npc=True):
        """First NPC/object/item of a startedBy/finishedBy field -> (name, uiMap, x, y) or None."""
        if not givers: return None
        for k, getter in ((1, db.npc), (2, db.obj)):
            for i in pos(givers, k) or []:
                e = getter(i)
                if not e or not e.get("name"): continue
                for area, pts in (e.get("spawns") or {}).items():
                    for p in pts or []:
                        if isinstance(p, list) and len(p) >= 2 and p[0] is not None and p[0] >= 0:
                            m = db.uimap.get(area)
                            if m: return (e["name"], m, round(p[0], 1), round(p[1], 1))
                return (e["name"], None, None, None)   # inside a dungeon (no map position)
        for i in pos(givers, 3) or []:
            it = db.item(i)
            if it and it.get("name"):
                src = [db.npc(n) for n in (it.get("npcs") or [])[:3]]
                src = [s["name"] for s in src if s and s.get("name")]
                return ("(item) " + it["name"] + (" from " + ", ".join(src) if src else ""), None, None, None)
        return None

    def objective_npcs(q):
        """NPCs a quest's objectives are about: mobs to kill, and the mobs that drop its items."""
        o = q.get("objectives") or {}
        out = []
        for c in pos(o, 1) or []:
            if isinstance(c, list) and c and isinstance(c[0], int): out.append(c[0])
        for c in pos(o, 3) or []:
            if isinstance(c, list) and c and isinstance(c[0], int):
                it = db.item(c[0])
                if it: out += [n for n in (it.get("npcs") or [])[:25] if isinstance(n, int)]
        return out

    def item_inside(item_id, areas):
        """An item that (mostly) drops inside the dungeon: at least half its droppers are zoned there."""
        it = db.item(item_id)
        npcs = [db.npc(n) for n in (it or {}).get("npcs") or [] if isinstance(n, int)]
        npcs = [e for e in npcs if e]
        if not npcs: return False
        return sum(1 for e in npcs if e.get("zone") in areas) * 2 >= len(npcs)

    def inside(q, areas):
        """The quest happens inside the dungeon: it starts there (from an NPC or a dropped item), or
        an objective mob, object or item is there. Repeatable quests don't count."""
        if (q.get("specialFlags") or 0) & 1: return None
        sb = q.get("startedBy") or {}
        for n in pos(sb, 1) or []:
            e = db.npc(n)
            if e and e.get("zone") in areas: return e
        for i in pos(sb, 3) or []:
            if isinstance(i, int) and item_inside(i, areas): return True
        o = q.get("objectives") or {}
        for c in pos(o, 1) or []:
            if isinstance(c, list) and c and isinstance(c[0], int):
                e = db.npc(c[0])
                if e and e.get("zone") in areas: return e
        for c in pos(o, 3) or []:
            if isinstance(c, list) and c and isinstance(c[0], int) and item_inside(c[0], areas): return True
        for c in pos(o, 2) or []:
            if isinstance(c, list) and c and isinstance(c[0], int):
                e = db.obj(c[0])
                if e and e.get("zone") in areas: return e
        return None

    place_bosses = {}
    for d in DUNGEONS:
        if d.get("place"):
            for bn in d.get("bosses") or []: place_bosses[(d["place"], bn.lower())] = d["name"]

    def zoned_quests(d, wing_claimed):
        areas = area_set(d)
        ids = []
        if areas:
            for q in quests.values():
                if not q or q["id"] in black: continue
                if (q.get("zoneOrSort") or 0) in areas or inside(q, areas): ids.append(q["id"])
        if d.get("wing"):
            mine = {i for n in WING_QUESTS.get(d["name"], []) for i in by_name.get(n.lower(), [])}
            mine |= boss_wing.get(d["name"], set())
            # a wing keeps its own quests, plus the place's quests no wing claims
            ids = [i for i in ids if i in mine or i not in wing_claimed]
            ids += [i for i in mine if i not in ids and i not in black]
        for n in d.get("quests") or []:
            for i in by_name.get(n.lower(), []):
                if i not in ids and i not in black: ids.append(i)
        return sorted(set(ids))

    wing_claimed = {i for names in WING_QUESTS.values() for n in names for i in by_name.get(n.lower(), [])}
    # A quest about one wing's boss (kill it, or loot an item it drops) belongs to that wing.
    boss_wing = {}
    for d in DUNGEONS:
        if not d.get("wing"): continue
        areas = area_set(d)
        for q in quests.values():
            if not q or q["id"] in black: continue
            if not ((q.get("zoneOrSort") or 0) in areas or inside(q, areas)): continue
            for n in objective_npcs(q):
                e = db.npc(n)
                w = e and place_bosses.get((d["place"], (e.get("name") or "").lower()))
                if w:
                    boss_wing.setdefault(w, set()).add(q["id"]); wing_claimed.add(q["id"])

    # boss NPC IDs: an NPC with the boss's name, preferably zoned in the dungeon
    npc_by_name = {}
    for i in db.ids("Npc"):
        e = db.npc(i)
        if e and e.get("name"): npc_by_name.setdefault(e["name"].lower(), []).append(e)

    out = ["-- Generated by tools/gen_dungeons.py from QuestieDB (GPLv3) and public dungeon facts",
           "-- (Wowhead Classic, Blizzard's WoW Forever dungeon announcement, Warcraft Tavern guides).",
           "-- Do not edit by hand: change tools/gen_dungeons.py and re-run it.",
           "local _, ns = ...",
           "-- One entry per dungeon (wings separately). ent = {uiMapID, x, y}; bosses = {name, npcID, level};",
           "-- quests = every quest for it, both factions (the journal shows yours).",
           "ns.dungeonDB = {"]
    used = set()
    report = []
    for d in DUNGEONS:
        a = d.get("area")
        qd = db.dungeons.get(a) if a else None
        ent = d.get("ent")
        if not ent and qd and qd["entrances"]:
            pa, x, y = qd["entrances"][0]
            ent = (db.uimap.get(pa), x, y)
        areas = area_set(d)
        ids = zoned_quests(d, wing_claimed)
        # quest items each boss drops: [npc] -> {{item, quest id}, ...}
        drops = {}
        for qid in ids:
            q = quests.get(qid) or {}
            for c in pos(q.get("objectives") or {}, 3) or []:
                if isinstance(c, list) and c and isinstance(c[0], int):
                    it = db.item(c[0])
                    for n in (it or {}).get("npcs") or []:
                        drops.setdefault(n, []).append((it["name"], qid))
        bosses = []
        for bn in d.get("bosses") or []:
            cands = npc_by_name.get(bn.lower(), [])
            cands.sort(key=lambda e: (0 if (e.get("zone") in areas) else 1, e["id"]))
            e = cands[0] if cands else None
            lvl = (e["hi"] or e["lo"]) if e else 0
            dr = drops.get(e["id"], []) if e else []
            drs = ("," + "{" + ",".join(f"{{{lstr(n)},{q}}}" for n, q in dr[:6]) + "}") if dr else ""
            bosses.append(f"{{{lstr(bn)},{e['id'] if e else 0},{lvl or 0}{drs}}}")
        used.update(ids)
        inst = d.get("inst")
        f = [f"name={lstr(d['name'])}", f"key={lstr(d['key'])}", f"lo={d['lo']}", f"hi={d['hi']}"]
        if d.get("place"): f.append(f"place={lstr(d['place'])}")
        if d.get("wing"): f.append(f"wing={lstr(d['wing'])}")
        if areas: f.append("area={" + ",".join(map(str, sorted(areas))) + "}")
        if inst: f.append(f"inst={inst}")
        if ent and ent[0]: f.append(f"ent={{{ent[0]},{ent[1]},{ent[2]}}}")
        if d.get("forever"): f.append("forever=true")
        if d.get("horde"): f.append("horde=true")
        if d.get("raidlike"): f.append("raidlike=true")
        if d.get("ej"): f.append("ej={" + ",".join(lstr(x) for x in d["ej"]) + "}")
        f.append("bosses={" + ",".join(bosses) + "}")
        f.append("quests={" + ",".join(map(str, ids)) + "}")
        out.append("  {" + ", ".join(f) + "},")
        missing = [bn for bn in d.get("bosses") or [] if not npc_by_name.get(bn.lower())]
        report.append(f"{d['name']}: {len(ids)} quests, {len(bosses)} bosses" +
                      (f" (no NPC ID: {', '.join(missing)})" if missing else ""))
    out.append("}")

    out.append("-- Quests: n name, l level, r required level, g giver / t ender {name, uiMapID, x, y} (no map = inside),")
    out.append("-- ot objective text, sh shareable, fa A/H (one faction only), cl class mask, pg all-of / ps one-of")
    out.append("-- earlier quests, nx next quest, xp {quest level, base XP}.")
    out.append("ns.dungeonQuests = {")
    for qid in sorted(used):
        q = quests.get(qid)
        if not q: continue
        p = [f"n={lstr(q.get('name') or ('Quest ' + str(qid)))}", f"l={q.get('questLevel') or 0}",
             f"r={q.get('requiredLevel') or 0}"]
        for key, fld in (("g", "startedBy"), ("t", "finishedBy")):
            w = where(q.get(fld))
            if w:
                p.append(f"{key}={{{lstr(w[0])}" + (f",{w[1]},{w[2]},{w[3]}" if w[1] else "") + "}")
        ot = q.get("objectivesText")
        if isinstance(ot, list) and ot:
            txt = " ".join(s for s in ot if isinstance(s, str)).strip()
            if txt: p.append(f"ot={lstr(txt[:400])}")
        if (q.get("questFlags") or 0) & QUEST_FLAG_SHARABLE: p.append("sh=true")
        ra = (q.get("requiredRaces") or 0) & RACE_MASK
        if ra and ra & ALLIANCE_RACES and not ra & HORDE_RACES: p.append('fa="A"')
        elif ra and ra & HORDE_RACES and not ra & ALLIANCE_RACES: p.append('fa="H"')
        cl = (q.get("requiredClasses") or 0) & 0xFFFF
        if cl: p.append(f"cl={cl}")
        for key, fld in (("pg", "preQuestGroup"), ("ps", "preQuestSingle")):
            v = [x for x in (q.get(fld) or []) if isinstance(x, int) and x > 0]
            if v: p.append(f"{key}={{" + ",".join(map(str, v)) + "}")
        if isinstance(q.get("nextQuestInChain"), int) and q["nextQuestInChain"] > 0:
            p.append(f"nx={q['nextQuestInChain']}")
        if qid in xp: p.append(f"xp={{{xp[qid][0]},{xp[qid][1]}}}")
        out.append(f"  [{qid}]={{" + ", ".join(p) + "},")
    # chain quests behind dungeon quests (names for the "needs" lines), one level deep is not enough:
    # walk every prerequisite so the journal can show "step 2 of 4".
    seen = set(used)
    todo = [x for qid in used for fld in ("preQuestGroup", "preQuestSingle")
            for x in ((quests.get(qid) or {}).get(fld) or []) if isinstance(x, int) and x > 0]
    chain = {}
    while todo:
        x = todo.pop()
        if x in seen: continue
        seen.add(x)
        q = quests.get(x)
        if not q: continue
        w = where(q.get("startedBy"))
        pre = [y for fld in ("preQuestGroup", "preQuestSingle") for y in (q.get(fld) or []) if isinstance(y, int) and y > 0]
        chain[x] = (q.get("name") or "", q.get("questLevel") or 0, w, pre)
        todo += pre
    out.append("}")
    out.append("-- Earlier quests in the chains behind them: [id] = {name, level, giver {name, uiMapID, x, y}, {earlier ids}}")
    out.append("ns.dungeonChain = {")
    for x, (n, l, w, pre) in sorted(chain.items()):
        g = (f"{{{lstr(w[0])}" + (f",{w[1]},{w[2]},{w[3]}" if w[1] else "") + "}") if w else "nil"
        out.append(f"  [{x}]={{{lstr(n)},{l},{g},{{{','.join(map(str, pre))}}}}},")
    out.append("}")
    open(out_path, "w", encoding="utf-8", newline="\n").write("\n".join(out) + "\n")
    print("\n".join(report))
    print(f"{len(used)} dungeon quests, {len(chain)} chain quests -> {out_path}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
