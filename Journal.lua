-- Rubber Dinghy - Dungeon Journal: our own journal of every 10-60 dungeon.
--   Home: search, a grid of dungeon cards (levels, "4/5 quests", a tick when they're all done),
--   filters, Character Logs and Hide Dungeons.
--   Dungeon page: Quests (live status, where each starts, objective, hand-in, the chain before it,
--   XP, shareable), Bosses (the game's own Encounter Journal when it has the dungeon), Runs.
-- Data: Data_Dungeons.lua (QuestieDB + public facts) and the game itself. Built only when opened;
-- nothing here runs on game events.
local ADDON, ns = ...
local J = {}
ns.Journal = J

local W, H = 880, 620
local CARD_H = 104
local LIST_W = 300
local band = bit and bit.band or function(a, b)   -- the game has bit; this is only for test clients
  local r, m = 0, 1
  while a > 0 and b > 0 do
    if a % 2 == 1 and b % 2 == 1 then r = r + m end
    a, b, m = math.floor(a / 2), math.floor(b / 2), m * 2
  end
  return r
end

local GOLD, WHITE, GREY, GREEN, BLUE, ORANGE, RED = "|cffffd100", "|cffffffff", "|cff9d9d9d", "|cff33ff33",
  "|cff66ccff", "|cffff8040", "|cffff4040"

local frame, homeView, pageView, logsView, searchBox, optsPanel
local view = "home"
local cur        -- the dungeon on the page
local tab = "quests"
local selected   -- quest id / boss index / run on the page
local hideMode = false
local ej         -- the game's Encounter Journal, read once: [our dungeon name] = {desc, art, bosses}
local lfgLevels  -- the game's group finder level ranges, by dungeon name

local function DB() ns.db.journal = ns.db.journal or { hidden = {} }; return ns.db.journal end

---------------------------------------------------------------------------
-- Quests: status for you
---------------------------------------------------------------------------
local myFaction, classBit
local function Me()
  if not myFaction then
    local f = UnitFactionGroup and UnitFactionGroup("player")
    myFaction = (f == "Horde") and "H" or "A"
    local _, _, classID = UnitClass("player")
    classBit = classID and 2 ^ (classID - 1) or 0
  end
end

local function Quest(id) return ns.dungeonQuests and ns.dungeonQuests[id] end

local function ForMe(q, otherFaction)
  Me()
  if q.fa and q.fa ~= myFaction and not otherFaction then return false end
  if q.cl and not DB().allClass and band(q.cl, classBit) == 0 then return false end
  return true
end

local function IsDone(id) return ns.IsDone and ns.IsDone(id) or (C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(id)) end
local function LogIdx(id)
  if ns.LogIndex then return ns.LogIndex(id) or 0 end
  return C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(id) or 0
end

-- earlier quests of a quest (ours or the chain table): all-of, one-of
local function Pre(id)
  local q = Quest(id)
  if q then return q.pg, q.ps end
  local c = ns.dungeonChain and ns.dungeonChain[id]
  if c then return c[4], nil end
  return nil, nil
end
local function PreMet(id)
  local pg, ps = Pre(id)
  for _, p in ipairs(pg or {}) do if not IsDone(p) then return false end end
  if ps and #ps > 0 then
    for _, p in ipairs(ps) do if IsDone(p) then return true end end
    return false
  end
  return true
end

local ST = { READY = 1, LOG = 2, OPEN = 3, SOON = 4, LOCKED = 5, LOW = 6, DONE = 7 }
J.ST = ST
local ST_TEXT = {
  [1] = GREEN .. "Ready to turn in|r", [2] = GOLD .. "In your quest log|r", [3] = WHITE .. "You can pick it up now|r",
  [4] = GREY .. "Available from level %d|r", [5] = GREY .. "Needs earlier quests first|r",
  [6] = GREY .. "Available from level %d|r", [7] = GREEN .. "Completed|r",
}
local ST_COLOR = { [1] = GREEN, [2] = GOLD, [3] = WHITE, [4] = GREY, [5] = GREY, [6] = GREY, [7] = GREY }

function J.QuestStatus(id)
  local q = Quest(id)
  if IsDone(id) then return ST.DONE end
  local i = LogIdx(id)
  if i and i > 0 then return (ns.IsReady and ns.IsReady(id, i)) and ST.READY or ST.LOG end
  if not PreMet(id) then return ST.LOCKED end
  local lv = UnitLevel("player")
  local r = q and q.r or 0
  if r > lv then return (r - lv <= 2) and ST.SOON or ST.LOW end
  return ST.OPEN
end

--- XP a quest gives at your level (QuestieDB's base XP, the game's grey-quest rule).
function J.QuestXP(id)
  local q = Quest(id)
  local base = q and q.xp
  if not base then return nil end
  local qlv, xp = base[1], base[2]
  local mult = math.min(10, math.max(1, 2 * (qlv - UnitLevel("player")) + 20))
  xp = xp * mult / 10
  if xp <= 100 then xp = 5 * math.floor((xp + 2) / 5)
  elseif xp <= 500 then xp = 10 * math.floor((xp + 5) / 10)
  elseif xp <= 1000 then xp = 25 * math.floor((xp + 12) / 25)
  else xp = 50 * math.floor((xp + 25) / 50) end
  return math.floor(xp)
end

--- The chain before a quest, earliest first: { {id, name, done, inlog}, ... }
function J.Chain(id)
  local out, seen = {}, {}
  local function walk(x, depth)
    if seen[x] or depth > 20 then return end
    seen[x] = true
    local pg, ps = Pre(x)
    for _, p in ipairs(pg or {}) do walk(p, depth + 1) end
    -- one-of: follow the one you did, else the first
    if ps and #ps > 0 then
      local pick = ps[1]
      for _, p in ipairs(ps) do if IsDone(p) then pick = p; break end end
      walk(pick, depth + 1)
    end
    if x ~= id then
      local q, c = Quest(x), ns.dungeonChain and ns.dungeonChain[x]
      out[#out + 1] = { id = x, name = (q and q.n) or (c and c[1]) or ("Quest " .. x), giver = (q and q.g) or (c and c[3]),
                        done = IsDone(x), inlog = LogIdx(x) > 0 }
    end
  end
  walk(id, 0)
  return out
end

--- The same chain from the data alone (no game calls), cached: { {id, name}, ... }. For the tracker,
--- which redraws often and checks each step itself.
local staticChain = {}
function J.StaticChain(id)
  local c = staticChain[id]
  if c then return c end
  c = {}
  local seen = {}
  local function walk(x, depth)
    if seen[x] or depth > 20 then return end
    seen[x] = true
    local pg, ps = Pre(x)
    for _, p in ipairs(pg or {}) do walk(p, depth + 1) end
    if ps and ps[1] then walk(ps[1], depth + 1) end
    if x ~= id then
      local q, ch = Quest(x), ns.dungeonChain and ns.dungeonChain[x]
      c[#c + 1] = { id = x, name = (q and q.n) or (ch and ch[1]) or ("Quest " .. x) }
    end
  end
  walk(id, 0)
  staticChain[id] = c
  return c
end

local function Where(loc)
  if not loc then return nil end
  if not loc[2] then return loc[1] .. " (inside the dungeon)" end
  return ("%s, %s %.1f, %.1f"):format(loc[1], ns.MapName(loc[2]) or "?", loc[3], loc[4])
end

--- This dungeon's quests for you: ids, how many done, how many there are.
function J.Counts(d, otherFaction)
  local mine, done = {}, 0
  for _, id in ipairs(d.quests or {}) do
    local q = Quest(id)
    if q and ForMe(q, otherFaction) then
      mine[#mine + 1] = id
      if IsDone(id) then done = done + 1 end
    end
  end
  return mine, done
end

---------------------------------------------------------------------------
-- The game's own data: Encounter Journal and group finder (read once, on first open)
---------------------------------------------------------------------------
local function Norm(s) return s and s:lower():gsub("^the ", ""):gsub("[^%w]", "") or "" end

local function OurDungeonsFor(ejName)
  local n = Norm(ejName)
  local out = {}
  for _, d in ipairs(ns.dungeonDB or {}) do
    local hit = Norm(d.name) == n or (d.place and Norm(d.place) == n)
    for _, a in ipairs(d.ej or {}) do if Norm(a) == n then hit = true end end
    if hit then out[#out + 1] = d end
  end
  return out
end

function J.ScanGame()
  if ej then return end
  ej, lfgLevels = {}, {}
  local report = { when = time(), build = select(4, GetBuildInfo()), instances = {}, lfg = {} }
  if type(EJ_GetInstanceByIndex) == "function" and type(EJ_SelectInstance) == "function" then
    report.ej = true
    local tiers = 1
    if EJ_GetNumTiers then local ok, n = pcall(EJ_GetNumTiers); if ok and n then tiers = n end end
    report.tiers = tiers
    local prevTier = EJ_GetCurrentTier and select(2, pcall(EJ_GetCurrentTier))
    for t = 1, tiers do
      if EJ_SelectTier then pcall(EJ_SelectTier, t) end
      for _, raid in ipairs({ false, true }) do
        for i = 1, 80 do
          local ok, id, name, desc, bg, button, lore, button2, areaMap = pcall(EJ_GetInstanceByIndex, i, raid)
          if not ok or not id then break end
          pcall(EJ_SelectInstance, id)
          local info = { tier = t, raid = raid or nil, id = id, name = name, bg = bg, button = button, lore = lore,
                         button2 = button2, map = areaMap, bosses = 0 }
          local bosses = {}
          for e = 1, 40 do
            local okE, ename, edesc, encID = pcall(EJ_GetEncounterInfoByIndex, e, id)
            if not okE or not ename then okE, ename, edesc, encID = pcall(EJ_GetEncounterInfoByIndex, e) end
            if not okE or not ename then break end
            local icon
            if EJ_GetCreatureInfo then
              local okC, _, _, _, _, ic = pcall(EJ_GetCreatureInfo, 1, encID)
              if okC then icon = ic end
            end
            bosses[#bosses + 1] = { name = ename, desc = edesc, id = encID, icon = icon }
          end
          info.bosses = #bosses
          -- loot: does the game's journal have any for the first boss? (phase 2 decides on this)
          if bosses[1] and EJ_SelectEncounter and EJ_GetNumLoot then
            pcall(EJ_SelectEncounter, bosses[1].id)
            local okL, n = pcall(EJ_GetNumLoot)
            info.loot = okL and n or nil
          end
          report.instances[#report.instances + 1] = info
          for _, d in ipairs(OurDungeonsFor(name)) do
            local mineBosses = bosses
            if d.wing then   -- a wing: only its own bosses
              local want, sub = {}, {}
              for _, b in ipairs(d.bosses or {}) do want[Norm(b[1])] = true end
              for _, b in ipairs(bosses) do if want[Norm(b.name)] then sub[#sub + 1] = b end end
              if #sub > 0 then mineBosses = sub end
            end
            ej[d.name] = ej[d.name] or { desc = desc, art = button or bg, bg = bg, bosses = mineBosses }
          end
        end
      end
    end
    if prevTier and EJ_SelectTier then pcall(EJ_SelectTier, prevTier) end
  end
  -- group finder level ranges
  if C_LFGList and C_LFGList.GetAvailableCategories and C_LFGList.GetAvailableActivities then
    local okC, cats = pcall(C_LFGList.GetAvailableCategories)
    for _, c in ipairs(okC and cats or {}) do
      local okA, acts = pcall(C_LFGList.GetAvailableActivities, c)
      for _, a in ipairs(okA and acts or {}) do
        local okI, t = pcall(C_LFGList.GetActivityInfoTable, a)
        if okI and type(t) == "table" and t.fullName then
          local lo, hi = t.minLevel or t.minLevelSuggestion, t.maxLevelSuggestion or t.maxLevel
          report.lfg[#report.lfg + 1] = { t.fullName, lo, hi }
          for _, d in ipairs(OurDungeonsFor(t.fullName)) do
            if lo and lo > 0 and hi and hi > 0 then lfgLevels[d.name] = { lo, hi } end
          end
        end
      end
    end
  end
  ns.db.journalReport = report
end

local function Levels(d)
  local l = lfgLevels and lfgLevels[d.name]
  if l then return l[1], l[2] end
  return d.lo, d.hi
end

---------------------------------------------------------------------------
-- Small UI helpers
---------------------------------------------------------------------------
local function Font(fs, names) local n = ns.Font(names); if _G[n] then fs:SetFontObject(_G[n]) end end

local function Button(parent, text, w, onClick, tip)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w, 22)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  if tip then
    b:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:AddLine(tip, 1, 1, 1, true); GameTooltip:Show() end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  return b
end

local function Panel(parent)
  local p = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  if p.SetBackdrop then
    p:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                    edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    p:SetBackdropColor(0.06, 0.05, 0.04, 0.92)
    p:SetBackdropBorderColor(0.55, 0.45, 0.25, 1)
  end
  return p
end

local function Scroll(parent)
  local sf = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
  local child = CreateFrame("Frame", nil, sf)
  child:SetSize(10, 10)
  sf:SetScrollChild(child)
  sf.child = child
  return sf
end

-- A column of text lines (wrapping) with optional click and tooltip, for the detail panels.
local function Lines(parent, width)
  local L = { parent = parent, width = width, fs = {}, btn = {}, y = 0, n = 0, nb = 0 }
  function L:Reset()
    for _, f in ipairs(self.fs) do f:Hide() end
    for _, b in ipairs(self.btn) do b:Hide() end
    self.y, self.n, self.nb = -4, 0, 0
  end
  function L:Add(text, o)
    o = o or {}
    self.n = self.n + 1
    local fs = self.fs[self.n]
    if not fs then fs = self.parent:CreateFontString(nil, "OVERLAY"); self.fs[self.n] = fs end
    Font(fs, o.font or { "GameFontHighlight" })
    fs:SetJustifyH("LEFT")
    if fs.SetWordWrap then fs:SetWordWrap(true) end
    fs:SetWidth(self.width - (o.indent or 0) - 8)
    fs:ClearAllPoints()
    self.y = self.y - (o.gap or 2)
    fs:SetPoint("TOPLEFT", self.parent, "TOPLEFT", 6 + (o.indent or 0), self.y)
    fs:SetText(text)
    fs:Show()
    local h = math.max(12, fs:GetStringHeight() or 12)
    if o.onClick or o.tip then
      self.nb = self.nb + 1
      local b = self.btn[self.nb]
      if not b then
        b = CreateFrame("Button", nil, self.parent)
        b:SetScript("OnEnter", function(s) if s.tip then GameTooltip:SetOwner(s, "ANCHOR_RIGHT"); GameTooltip:AddLine(s.tip, 1, 1, 1, true); GameTooltip:Show() end end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:SetScript("OnClick", function(s) if s.onClick then s.onClick() end end)
        self.btn[self.nb] = b
      end
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", fs, "TOPLEFT", 0, 0)
      b:SetSize(self.width - (o.indent or 0) - 8, h)
      b.onClick, b.tip = o.onClick, o.tip
      b:Show()
    end
    self.y = self.y - h
    return fs
  end
  function L:Gap(n) self.y = self.y - (n or 8) end
  function L:Height() return -self.y + 8 end
  return L
end

local function Tip(self, lines)
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  for i, l in ipairs(lines) do
    if i == 1 then GameTooltip:AddLine(l) else GameTooltip:AddLine(l, 1, 1, 1, true) end
  end
  GameTooltip:Show()
end

--- Point the world map at a spot (the route's map pin, highlighted). Never sets a map marker.
local function ShowSpot(name, m, x, y)
  if not (m and x and y) then return end
  ns.ShowOnMap({ index = "!", map = m, x = x, y = y, name = name, actions = {}, journal = true })
end
J.ShowSpot = ShowSpot

---------------------------------------------------------------------------
-- Home: the dungeon cards
---------------------------------------------------------------------------
local cards = {}
local LEVEL_TINT = { { 0.20, 0.35, 0.18 }, { 0.18, 0.28, 0.40 }, { 0.36, 0.26, 0.14 }, { 0.38, 0.16, 0.14 } }

local function Visible(d)
  local o = DB()
  if d.horde and myFaction ~= "H" then return false end
  if o.foreverOnly and not d.forever then return false end
  if hideMode then return true end
  if o.hidden[d.name] then return false end
  local _, hi = Levels(d)
  if o.hideOutleveled and UnitLevel("player") > hi then return false end
  if o.hideAllDone then
    local mine, done = J.Counts(d)
    if #mine > 0 and done == #mine then return false end
  end
  return true
end

local function Card(i)
  local c = cards[i]
  if c then return c end
  c = CreateFrame("Button", nil, homeView.scroll.child, BackdropTemplateMixin and "BackdropTemplate" or nil)
  if c.SetBackdrop then
    c:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12 })
    c:SetBackdropBorderColor(0.55, 0.45, 0.25, 1)
  end
  c.art = c:CreateTexture(nil, "BACKGROUND")
  c.art:SetPoint("TOPLEFT", 3, -3); c.art:SetPoint("BOTTOMRIGHT", -3, 3)
  c.shade = c:CreateTexture(nil, "BORDER")
  c.shade:SetPoint("TOPLEFT", 3, -3); c.shade:SetPoint("TOPRIGHT", -3, -3); c.shade:SetHeight(34)
  c.shade:SetColorTexture(0, 0, 0, 0.55)
  c.name = c:CreateFontString(nil, "OVERLAY"); Font(c.name, { "GameFontNormalLarge" })
  c.name:SetPoint("TOPLEFT", 12, -10)
  c.count = c:CreateFontString(nil, "OVERLAY"); Font(c.count, { "GameFontHighlight" })
  c.count:SetPoint("TOPRIGHT", -12, -12)
  c.tick = c:CreateTexture(nil, "OVERLAY")
  c.tick:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
  c.tick:SetSize(20, 20)
  c.tick:SetPoint("RIGHT", c.count, "LEFT", -4, 0)
  c.levels = c:CreateFontString(nil, "OVERLAY"); Font(c.levels, { "GameFontHighlightSmall" })
  c.levels:SetPoint("BOTTOMLEFT", 12, 10)
  c.tag = c:CreateFontString(nil, "OVERLAY"); Font(c.tag, { "GameFontHighlightSmall" })
  c.tag:SetPoint("BOTTOMRIGHT", -12, 10)
  c:SetScript("OnClick", function(self)
    if hideMode then
      local o = DB()
      o.hidden[self.d.name] = not o.hidden[self.d.name] or nil
      J.Refresh()
    else
      J.OpenDungeon(self.d.name)
    end
  end)
  c:SetScript("OnEnter", function(self)
    if hideMode then
      Tip(self, { self.d.name, DB().hidden[self.d.name] and "Click to show this dungeon again." or "Click to hide this dungeon." })
    else
      local lines = { self.d.name, "Click to open its quests, bosses and runs." }
      local e = ej and ej[self.d.name]
      if e and e.desc and e.desc ~= "" then lines[#lines + 1] = e.desc end
      Tip(self, lines)
    end
  end)
  c:SetScript("OnLeave", function() GameTooltip:Hide() end)
  cards[i] = c
  return c
end

local function RenderHome()
  local list = {}
  for _, d in ipairs(ns.dungeonDB or {}) do if Visible(d) then list[#list + 1] = d end end
  local cw = math.floor((W - 64) / 2)
  local o = DB()
  for i, d in ipairs(list) do
    local c = Card(i)
    c.d = d
    c:SetSize(cw, CARD_H)
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", homeView.scroll.child, "TOPLEFT", ((i - 1) % 2) * (cw + 10), -math.floor((i - 1) / 2) * (CARD_H + 10))
    local e = ej and ej[d.name]
    local art = e and (e.art or e.bg)
    if art then
      c.art:SetTexture(art); c.art:SetTexCoord(0, 1, 0, 1); c.art:SetVertexColor(1, 1, 1)
    else
      local lo = Levels(d)
      local t = LEVEL_TINT[math.min(4, math.max(1, math.floor((lo - 10) / 13) + 1))]
      c.art:SetColorTexture(t[1], t[2], t[3], 1)
    end
    c.name:SetText(d.name)
    local mine, done = J.Counts(d)
    c.count:SetText(#mine > 0 and (#mine == done and (done .. "/" .. #mine .. " quests") or ((done > 0 and (done .. "/") or "") .. #mine .. (#mine == 1 and " quest" or " quests"))) or "0 quests")
    c.tick:SetShown(#mine > 0 and done == #mine and not o.hideTick)
    local lo, hi = Levels(d)
    c.levels:SetText(("LV %d-%d"):format(lo, hi))
    local tag = {}
    if d.forever then tag[#tag + 1] = BLUE .. "WoW Forever|r" end
    local step = ns.steps and J.Step(d.name)
    if step and ns.DungeonOn(d.name) then tag[#tag + 1] = GREEN .. "In your route|r" end
    c.tag:SetText(table.concat(tag, "  "))
    c:SetAlpha((hideMode and o.hidden[d.name]) and 0.35 or 1)
    c:Show()
  end
  for i = #list + 1, #cards do cards[i]:Hide() end
  homeView.scroll.child:SetSize(W - 50, math.ceil(#list / 2) * (CARD_H + 10) + 10)
  homeView.empty:SetShown(#list == 0)
  homeView.hideB:SetText(hideMode and "Done hiding" or "Hide Dungeons")
  homeView.foreverB:SetText(o.foreverOnly and "All dungeons" or "Forever only")
end

---------------------------------------------------------------------------
-- Dungeon page
---------------------------------------------------------------------------
local rows = {}

function J.Step(name)
  for _, st in ipairs(ns.steps or {}) do if st.dungeon == name then return st end end
end
local function Dungeon(name)
  for _, d in ipairs(ns.dungeonDB or {}) do if d.name == name then return d end end
end
J.Dungeon = Dungeon

local function Row(i)
  local r = rows[i]
  if r then return r end
  r = CreateFrame("Button", nil, pageView.list.child)
  r:SetSize(LIST_W - 28, 22)
  r.hl = r:CreateTexture(nil, "BACKGROUND"); r.hl:SetAllPoints(); r.hl:SetColorTexture(1, 0.82, 0, 0.15)
  r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(16, 16); r.icon:SetPoint("LEFT", 2, 0)
  r.text = r:CreateFontString(nil, "OVERLAY"); Font(r.text, { "GameFontHighlight" })
  r.text:SetPoint("LEFT", r.icon, "RIGHT", 4, 0); r.text:SetPoint("RIGHT", -34, 0); r.text:SetJustifyH("LEFT")
  if r.text.SetWordWrap then r.text:SetWordWrap(false) end
  r.right = r:CreateFontString(nil, "OVERLAY"); Font(r.right, { "GameFontHighlightSmall" })
  r.right:SetPoint("RIGHT", -2, 0)
  r:SetScript("OnClick", function(self) selected = self.key; J.RenderPage() end)
  rows[i] = r
  return r
end

local QUEST_ICON = { [1] = "Interface\\GossipFrame\\ActiveQuestIcon", [2] = "Interface\\GossipFrame\\IncompleteQuestIcon",
  [3] = "Interface\\GossipFrame\\AvailableQuestIcon", [4] = "Interface\\GossipFrame\\AvailableQuestIcon",
  [5] = "Interface\\GossipFrame\\AvailableQuestIcon", [6] = "Interface\\GossipFrame\\AvailableQuestIcon",
  [7] = "Interface\\RaidFrame\\ReadyCheck-Ready" }
local SKULL = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"

local function QuestRows(d)
  local ids = J.Counts(d, DB().otherFaction)
  local items = {}
  for _, id in ipairs(ids) do items[#items + 1] = { id = id, s = J.QuestStatus(id), q = Quest(id) } end
  table.sort(items, function(a, b)
    if a.s ~= b.s then return a.s < b.s end
    return (a.q.l or 0) < (b.q.l or 0)
  end)
  return items
end

local function Bosses(d)
  local e = ej and ej[d.name]
  local out = {}
  local byName = {}
  for _, b in ipairs(d.bosses or {}) do byName[Norm(b[1])] = b end
  if e and e.bosses and #e.bosses > 0 then
    for _, b in ipairs(e.bosses) do
      local ours = byName[Norm(b.name)]
      out[#out + 1] = { name = b.name, desc = b.desc, icon = b.icon, npc = ours and ours[2], level = ours and ours[3],
                        drops = ours and ours[4] }
    end
  else
    for _, b in ipairs(d.bosses or {}) do out[#out + 1] = { name = b[1], npc = b[2], level = b[3], drops = b[4] } end
  end
  return out
end

local function RenderQuestDetail(L, id)
  local q = Quest(id)
  if not q then return end
  local s = J.QuestStatus(id)
  L:Add(q.n, { font = { "GameFontNormalLarge" } })
  local tags = { ("Level %d"):format(q.l or 0) }
  if (q.r or 0) > 0 then tags[#tags + 1] = ("requires %d"):format(q.r) end
  if q.fa then tags[#tags + 1] = (q.fa == "A" and "Alliance" or "Horde") .. " only" end
  if q.cl then tags[#tags + 1] = "class quest" end
  L:Add(GREY .. table.concat(tags, " - ") .. "|r", { font = { "GameFontHighlightSmall" } })
  local st = ST_TEXT[s]
  if s == ST.SOON or s == ST.LOW then st = st:format(q.r or 0) end
  if s == ST.LOG then
    local have, need = ns.Progress and ns.Progress(id)
    if need and need > 0 then st = st .. GREY .. (" (%d/%d)"):format(have, need) .. "|r" end
  end
  L:Add(st, { gap = 6 })
  local chain = J.Chain(id)
  if s == ST.LOCKED and #chain > 0 then
    local doneN = 0
    for _, c in ipairs(chain) do if c.done then doneN = doneN + 1 end end
    L:Add(ORANGE .. ("Needs a quest chain first: you're on step %d of %d."):format(doneN + 1, #chain + 1) .. "|r", { gap = 2 })
  end

  L:Gap(6)
  L:Add(GOLD .. "Starts at|r", { font = { "GameFontNormal" } })
  local g = q.g
  L:Add(Where(g) or "Not recorded", { indent = 8, onClick = (g and g[2]) and function() ShowSpot(g[1], g[2], g[3], g[4]) end or nil,
    tip = (g and g[2]) and "Show it on the world map." or nil })
  if q.ot then
    L:Gap(4)
    L:Add(GOLD .. "Objective|r", { font = { "GameFontNormal" } })
    L:Add(q.ot, { indent = 8 })
  end
  local nq = ns.quests and ns.quests[id]
  if nq and nq.dr then
    for _, dr in ipairs(nq.dr) do L:Add(GREY .. dr[1] .. ": " .. dr[2] .. "|r", { indent = 8, font = { "GameFontHighlightSmall" } }) end
  end
  L:Gap(4)
  L:Add(GOLD .. "Turn in|r", { font = { "GameFontNormal" } })
  local t = q.t
  L:Add(Where(t) or "Not recorded", { indent = 8, onClick = (t and t[2]) and function() ShowSpot(t[1], t[2], t[3], t[4]) end or nil,
    tip = (t and t[2]) and "Show it on the world map." or nil })
  if #chain > 0 then
    L:Gap(4)
    L:Add(GOLD .. "Quest chain|r", { font = { "GameFontNormal" } })
    for i, c in ipairs(chain) do
      local mark = c.done and (GREEN .. "done|r") or (c.inlog and (GOLD .. "in your log|r") or (GREY .. "not yet|r"))
      L:Add(("%d. %s - %s"):format(i, c.name, mark), { indent = 8,
        tip = c.giver and ("Starts at " .. (Where(c.giver) or "?") .. (c.giver[2] and "\nClick to show it on the map." or "")) or nil,
        onClick = (c.giver and c.giver[2]) and function() ShowSpot(c.giver[1], c.giver[2], c.giver[3], c.giver[4]) end or nil })
    end
    L:Add(("%d. %s - this quest"):format(#chain + 1, q.n), { indent = 8 })
  end
  if q.nx then
    local nxq = Quest(q.nx) or (ns.quests and ns.quests[q.nx])
    local nm = (nxq and (nxq.n)) or (ns.dungeonChain and ns.dungeonChain[q.nx] and ns.dungeonChain[q.nx][1])
    if nm then L:Gap(4); L:Add(GREY .. "Leads to: " .. nm .. "|r") end
  end
  L:Gap(6)
  L:Add(GOLD .. "Reward|r", { font = { "GameFontNormal" } })
  local xp = J.QuestXP(id)
  L:Add((xp and (ns.RunLog.Thousands(xp) .. " XP at your level") or "XP not recorded"), { indent = 8 })
  L:Gap(4)
  L:Add(q.sh and (GREEN .. "Shareable quest|r - accept it, then share it with your group.") or (GREY .. "Not shareable|r"))
end

local function RenderBossDetail(L, d, b)
  L:Add(b.name, { font = { "GameFontNormalLarge" } })
  if b.level and b.level > 0 then L:Add(GREY .. "Level " .. b.level .. "|r", { font = { "GameFontHighlightSmall" } }) end
  if b.desc and b.desc ~= "" then L:Gap(6); L:Add(b.desc) end
  if b.drops then
    L:Gap(6)
    L:Add(GOLD .. "Quest items it drops|r", { font = { "GameFontNormal" } })
    for _, dr in ipairs(b.drops) do
      local q = Quest(dr[2])
      L:Add(dr[1] .. GREY .. " - for " .. (q and q.n or "a quest") .. "|r", { indent = 8,
        onClick = function() tab, selected = "quests", dr[2]; J.RenderPage() end, tip = "Click to open the quest." })
    end
  end
  local n, best = 0, nil
  for _, run in ipairs(ns.RunLog.For(d.name)) do
    local t = run.bosses and run.bosses[b.name]
    if t then n = n + 1; if not best or t < best then best = t end end
  end
  L:Gap(6)
  L:Add(GOLD .. "Your runs|r", { font = { "GameFontNormal" } })
  L:Add(n > 0 and (("Killed in %d run%s, fastest %s into the run."):format(n, n == 1 and "" or "s", ns.RunLog.Clock(best)))
    or "Not killed in a logged run yet.", { indent = 8 })
end

local function RunTitle(run)
  local when = date("%b %d %H:%M", run.t0)
  local n, of = ns.RunLog.BossCount(run)
  return ("%s  %s  %s XP  %d/%d bosses"):format(when, ns.RunLog.Clock(ns.RunLog.Secs(run)),
    ns.RunLog.Thousands(ns.RunLog.MobXP(run)), n, of)
end

local function RenderRunDetail(L, run)
  local RL = ns.RunLog
  L:Add((run.d or "?") .. GREY .. "  " .. date("%b %d %Y, %H:%M", run.t0) .. "|r", { font = { "GameFontNormalLarge" } })
  L:Gap(4)
  L:Add(("Time: %s (first kill to last kill)%s"):format(RL.Clock(RL.Secs(run)), run.done and GREEN .. " - cleared|r" or ""))
  L:Add(("Mobs: %d killed, %s XP"):format(run.kills or 0, RL.Thousands(RL.MobXP(run))))
  if (run.qxp or 0) > 0 then L:Add(("Quests handed in during the run: %s XP"):format(RL.Thousands(run.qxp))) end
  L:Add(("Money looted: %s"):format(GetCoinTextureString and GetCoinTextureString(RL.Gold(run)) or (RL.Gold(run) .. "c")))
  L:Add(("Deaths: %d"):format(run.deaths or 0))
  L:Add(("Level %d%s"):format(run.lv0 or 0, (run.lv1 and run.lv1 ~= run.lv0) and (" to " .. run.lv1) or ""))
  if (run.out or 0) > 60 then L:Add(("Time outside: %s"):format(RL.Clock(run.out))) end
  local d = Dungeon(run.d)
  if d then
    L:Gap(6)
    L:Add(GOLD .. "Bosses|r", { font = { "GameFontNormal" } })
    for _, b in ipairs(d.bosses or {}) do
      local t = run.bosses[b[1]]
      L:Add((t and GREEN or GREY) .. b[1] .. "|r" .. (t and (GREY .. "  at " .. RL.Clock(t) .. "|r") or ""), { indent = 8 })
    end
  end
  L:Gap(10)
  L:Add(RED .. "Delete this run|r", { onClick = function() J.ConfirmDelete(run) end, tip = "Removes it from your Run Log (asks first)." })
end

function J.ConfirmDelete(run)
  if not (StaticPopupDialogs and StaticPopup_Show) then ns.RunLog.Delete(run); J.Refresh(); return end
  StaticPopupDialogs.RUBBERDINGHY_DELETE_RUN = StaticPopupDialogs.RUBBERDINGHY_DELETE_RUN or {
    text = "Delete this run of %s from your Run Log?",
    button1 = YES or "Yes", button2 = NO or "No",
    OnAccept = function(self, data) ns.RunLog.Delete(data); selected = nil; J.Refresh() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
  }
  StaticPopup_Show("RUBBERDINGHY_DELETE_RUN", run.d or "a dungeon", nil, run)
end

function J.RenderPage()
  local d = cur and Dungeon(cur)
  if not d then return end
  local P = pageView
  local lo, hi = Levels(d)
  P.title:SetText(d.name)
  local ent = d.ent
  P.sub:SetText(("Levels %d-%d%s"):format(lo, hi, ent and ("   Entrance: " .. (ns.MapName(ent[1]) or "?") .. (" %.1f, %.1f"):format(ent[2], ent[3])) or ""))
  P.locB:SetShown(ent ~= nil)
  local step = J.Step(d.name)
  P.routeCB:SetShown(step ~= nil)
  P.readyB:SetShown(step ~= nil and ns.StartPrep ~= nil)
  if step then
    P.routeCB:SetChecked(ns.DungeonOn(d.name))
    P.readyB:SetText((ns.db.prep == d.name) and "Stop getting ready" or "Get ready")
  end
  for _, t in ipairs(P.tabs) do
    if t.key == tab then t:LockHighlight() else t:UnlockHighlight() end
  end
  P.factionB:SetShown(tab == "quests")
  P.factionB:SetText(DB().otherFaction and "Both factions" or "My faction")

  -- left list
  local items = {}
  if tab == "quests" then
    for _, it in ipairs(QuestRows(d)) do
      items[#items + 1] = { key = it.id, text = ST_COLOR[it.s] .. it.q.n .. "|r", right = GREY .. (it.q.l or "") .. "|r", icon = QUEST_ICON[it.s] }
    end
  elseif tab == "bosses" then
    for i, b in ipairs(Bosses(d)) do
      local killed
      local run = ns.RunLog.Current()
      if run and run.bosses[b.name] then killed = true end
      items[#items + 1] = { key = i, text = (killed and GREY or WHITE) .. b.name .. "|r", right = GREY .. ((b.level and b.level > 0) and b.level or "") .. "|r",
                            icon = b.icon or SKULL }
    end
  else
    for _, run in ipairs(ns.RunLog.For(d.name)) do
      items[#items + 1] = { key = run, text = WHITE .. RunTitle(run) .. "|r", icon = run.done and "Interface\\RaidFrame\\ReadyCheck-Ready" or nil }
    end
  end
  if selected == nil or (type(selected) ~= type(items[1] and items[1].key)) then selected = items[1] and items[1].key end
  local found = false
  for i, it in ipairs(items) do
    local r = Row(i)
    r.key = it.key
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -(i - 1) * 22)
    r.text:SetText(it.text); r.right:SetText(it.right or "")
    if it.icon then r.icon:SetTexture(it.icon); r.icon:Show() else r.icon:Hide() end
    r.hl:SetShown(it.key == selected)
    if it.key == selected then found = true end
    r:Show()
  end
  for i = #items + 1, #rows do rows[i]:Hide() end
  if not found then selected = items[1] and items[1].key end
  P.list.child:SetSize(LIST_W - 28, #items * 22 + 4)
  P.empty:SetShown(#items == 0)
  P.empty:SetText(tab == "runs" and "No runs logged yet. Runs are recorded on their own when you go in." or
    (tab == "quests" and "No quests recorded for this dungeon." or "No bosses recorded."))

  -- right detail
  local L = P.detail
  L:Reset()
  if tab == "quests" and selected then RenderQuestDetail(L, selected)
  elseif tab == "bosses" and selected then RenderBossDetail(L, d, Bosses(d)[selected] or {})
  elseif tab == "runs" and selected then RenderRunDetail(L, selected)
  elseif tab == "runs" then
    local e = ej and ej[d.name]
    if e and e.desc and e.desc ~= "" then L:Add(e.desc) end
  end
  P.detailScroll.child:SetSize(W - LIST_W - 60, L:Height())
end

---------------------------------------------------------------------------
-- Character Logs: every run, newest first
---------------------------------------------------------------------------
local logRows = {}
local function RenderLogs()
  local runs = ns.RunLog.All()
  local n = 0
  for i = #runs, 1, -1 do
    local run = runs[i]
    n = n + 1
    local r = logRows[n]
    if not r then
      r = CreateFrame("Button", nil, logsView.scroll.child)
      r:SetSize(W - 70, 22)
      r.hl = r:CreateTexture(nil, "HIGHLIGHT"); r.hl:SetAllPoints(); r.hl:SetColorTexture(1, 0.82, 0, 0.15)
      r.text = r:CreateFontString(nil, "OVERLAY"); Font(r.text, { "GameFontHighlight" })
      r.text:SetPoint("LEFT", 4, 0); r.text:SetJustifyH("LEFT")
      r:SetScript("OnClick", function(self) J.OpenDungeon(self.run.d, "runs", self.run) end)
      logRows[n] = r
    end
    r.run = run
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -(n - 1) * 22)
    r.text:SetText(GOLD .. (run.d or "?") .. "|r   " .. RunTitle(run) .. (run.deaths and run.deaths > 0 and (GREY .. ("  %d death%s"):format(run.deaths, run.deaths == 1 and "" or "s") .. "|r") or ""))
    r:Show()
  end
  for i = n + 1, #logRows do logRows[i]:Hide() end
  logsView.scroll.child:SetSize(W - 70, n * 22 + 4)
  logsView.empty:SetShown(n == 0)
end

---------------------------------------------------------------------------
-- Search: dungeons, bosses and quests
---------------------------------------------------------------------------
local resultRows = {}
local function Fold(s) return (s or ""):lower() end

local function RenderSearch(text)
  local q = Fold(text)
  local res = {}
  if #q >= 2 then
    for _, d in ipairs(ns.dungeonDB or {}) do
      if Fold(d.name):find(q, 1, true) then res[#res + 1] = { GOLD .. d.name .. "|r", d.name } end
      for _, b in ipairs(d.bosses or {}) do
        if Fold(b[1]):find(q, 1, true) then res[#res + 1] = { WHITE .. b[1] .. "|r" .. GREY .. "  boss, " .. d.name .. "|r", d.name, "bosses", b[1] } end
      end
      for _, id in ipairs(d.quests or {}) do
        local qq = Quest(id)
        if qq and ForMe(qq, true) and Fold(qq.n):find(q, 1, true) then
          res[#res + 1] = { WHITE .. qq.n .. "|r" .. GREY .. "  quest, " .. d.name .. "|r", d.name, "quests", id }
        end
      end
      if #res > 60 then break end
    end
  end
  local box = homeView.results
  box:SetShown(#q >= 2)
  for i, r in ipairs(res) do
    local b = resultRows[i]
    if not b then
      b = CreateFrame("Button", nil, box)
      b:SetSize(W - 80, 20)
      b.hl = b:CreateTexture(nil, "HIGHLIGHT"); b.hl:SetAllPoints(); b.hl:SetColorTexture(1, 0.82, 0, 0.15)
      b.text = b:CreateFontString(nil, "OVERLAY"); Font(b.text, { "GameFontHighlight" })
      b.text:SetPoint("LEFT", 6, 0); b.text:SetJustifyH("LEFT")
      b:SetScript("OnClick", function(self)
        local r2 = self.r
        if searchBox then searchBox:SetText(""); searchBox:ClearFocus() end
        local sel = r2[4]
        if r2[3] == "bosses" then
          local d = Dungeon(r2[2])
          for i2, bb in ipairs(d and Bosses(d) or {}) do if bb.name == sel then sel = i2 end end
          if type(sel) ~= "number" then sel = nil end
        end
        J.OpenDungeon(r2[2], r2[3], sel)
      end)
      resultRows[i] = b
    end
    b.r = r
    b:ClearAllPoints(); b:SetPoint("TOPLEFT", 8, -8 - (i - 1) * 20)
    b.text:SetText(r[1])
    b:Show()
    if i >= 24 then break end
  end
  for i = math.min(#res, 24) + 1, #resultRows do resultRows[i]:Hide() end
  box.none:SetShown(#q >= 2 and #res == 0)
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local function ShowView(v)
  view = v
  homeView:SetShown(v == "home")
  pageView:SetShown(v == "page")
  logsView:SetShown(v == "logs")
  if optsPanel then optsPanel:Hide() end
end

local function OptCheck(parent, y, label, key, tip)
  local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  cb:SetSize(24, 24)
  cb:SetPoint("TOPLEFT", 10, y)
  local fs = (type(cb.Text) == "table" and cb.Text) or (type(cb.text) == "table" and cb.text) or nil
  if not fs then fs = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); fs:SetPoint("LEFT", cb, "RIGHT", 2, 0) end
  fs:SetText(label)
  cb:SetScript("OnClick", function(self) DB()[key] = self:GetChecked() and true or nil; J.Refresh() end)
  cb:SetScript("OnShow", function(self) self:SetChecked(DB()[key] and true or false) end)
  if tip then
    cb:SetScript("OnEnter", function(self) Tip(self, { label, tip }) end)
    cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  return cb
end

local function Build()
  local ok, f = pcall(CreateFrame, "Frame", "RubberDinghyJournal", UIParent, "BackdropTemplate")
  if not ok or not f then f = CreateFrame("Frame", "RubberDinghyJournal", UIParent) end
  frame = f
  f:SetSize(W, H)
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local x, y = self:GetLeft(), self:GetTop()
    if x and y then DB().pos = { x, y } end
  end)
  if f.SetBackdrop then
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                    edgeSize = 24, insets = { left = 6, right = 6, top = 6, bottom = 6 } })
    f:SetBackdropColor(0.08, 0.06, 0.04, 0.97)
  end
  tinsert(UISpecialFrames, "RubberDinghyJournal")
  local title = f:CreateFontString(nil, "OVERLAY"); Font(title, { "GameFontNormalLarge" })
  title:SetPoint("TOP", 0, -16)
  title:SetText("Dungeon Journal")
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -6, -6)

  local okS, sb = pcall(CreateFrame, "EditBox", "RubberDinghyJournalSearch", f, "SearchBoxTemplate")
  if not okS or not sb then sb = CreateFrame("EditBox", "RubberDinghyJournalSearch", f, "InputBoxTemplate") end
  searchBox = sb
  sb:SetSize(240, 22)
  sb:SetPoint("TOPLEFT", 22, -14)
  sb:SetAutoFocus(false)
  if type(sb.Instructions) == "table" then sb.Instructions:SetText("Search dungeons, bosses, quests...") end
  sb:HookScript("OnTextChanged", function(self)
    if view ~= "home" then ShowView("home"); RenderHome() end
    RenderSearch(self:GetText())
  end)
  sb:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)

  -- Home
  homeView = CreateFrame("Frame", nil, f)
  homeView:SetPoint("TOPLEFT", 14, -44); homeView:SetPoint("BOTTOMRIGHT", -14, 14)
  local logsB = Button(homeView, "Character Logs", 130, function() ShowView("logs"); RenderLogs() end,
    "Every dungeon run this character has done: time, XP, bosses, deaths. Recorded on its own.")
  logsB:SetPoint("TOPRIGHT", -246, -4)
  homeView.hideB = Button(homeView, "Hide Dungeons", 120, function() hideMode = not hideMode; RenderHome() end,
    "Click this, then click dungeons to hide them from the list (or show them again). Click Done hiding when you're finished.")
  homeView.hideB:SetPoint("TOPRIGHT", -114, -4)
  local optB = Button(homeView, "Options", 100, function()
    if optsPanel:IsShown() then optsPanel:Hide() else optsPanel:Show() end
  end, "What the dungeon list shows.")
  optB:SetPoint("TOPRIGHT", -8, -4)
  homeView.foreverB = Button(homeView, "Forever only", 110, function() DB().foreverOnly = not DB().foreverOnly or nil; RenderHome() end,
    "Show only the dungeons that are new in WoW Forever (click again for all of them).")
  homeView.foreverB:SetPoint("TOPLEFT", 8, -4)
  local sub = homeView:CreateFontString(nil, "OVERLAY"); Font(sub, { "GameFontHighlightSmall" })
  sub:SetPoint("LEFT", homeView.foreverB, "RIGHT", 12, 0)
  sub:SetText(GREY .. "Click a dungeon for its quests, bosses and runs.|r")
  homeView.scroll = Scroll(homeView)
  homeView.scroll:SetPoint("TOPLEFT", 8, -36); homeView.scroll:SetPoint("BOTTOMRIGHT", -28, 4)
  homeView.empty = homeView:CreateFontString(nil, "OVERLAY"); Font(homeView.empty, { "GameFontHighlight" })
  homeView.empty:SetPoint("CENTER")
  homeView.empty:SetText("Every dungeon is hidden. Click Hide Dungeons to bring them back, or check Options.")
  homeView.results = Panel(homeView)
  homeView.results:SetPoint("TOPLEFT", 8, -36); homeView.results:SetPoint("BOTTOMRIGHT", -8, 4)
  homeView.results:SetFrameLevel(homeView:GetFrameLevel() + 20)
  homeView.results:Hide()
  homeView.results.none = homeView.results:CreateFontString(nil, "OVERLAY"); Font(homeView.results.none, { "GameFontHighlight" })
  homeView.results.none:SetPoint("TOPLEFT", 14, -14)
  homeView.results.none:SetText("No results")

  optsPanel = Panel(f)
  optsPanel:SetSize(330, 150)
  optsPanel:SetPoint("TOPRIGHT", f, "TOPRIGHT", -20, -78)
  optsPanel:SetFrameLevel(f:GetFrameLevel() + 40)
  optsPanel:Hide()
  OptCheck(optsPanel, -10, "Hide dungeons you've outleveled", "hideOutleveled", "Hides a dungeon once your level is above its range.")
  OptCheck(optsPanel, -36, "Hide dungeons with every quest done", "hideAllDone")
  OptCheck(optsPanel, -62, "Hide the green tick on finished dungeons", "hideTick")
  OptCheck(optsPanel, -88, "Show every class's quests", "allClass", "Normally only your own class's quests are listed.")
  OptCheck(optsPanel, -114, "Show the other faction's quests too", "otherFaction")

  -- Dungeon page
  pageView = CreateFrame("Frame", nil, f)
  pageView:SetPoint("TOPLEFT", 14, -44); pageView:SetPoint("BOTTOMRIGHT", -14, 14)
  local P = pageView
  local back = Button(P, "< All dungeons", 120, function() ShowView("home"); RenderHome() end)
  back:SetPoint("TOPLEFT", 8, -4)
  P.title = P:CreateFontString(nil, "OVERLAY"); Font(P.title, { "QuestTitleFontBlackShadow", "GameFontNormalHuge", "GameFontNormalLarge" })
  P.title:SetPoint("TOPLEFT", 8, -34)
  P.sub = P:CreateFontString(nil, "OVERLAY"); Font(P.sub, { "GameFontHighlightSmall" })
  P.sub:SetPoint("TOPLEFT", P.title, "BOTTOMLEFT", 0, -4)
  P.locB = Button(P, "Show Location", 116, function()
    local d = Dungeon(cur)
    if d and d.ent then ShowSpot(d.name .. " entrance", d.ent[1], d.ent[2], d.ent[3]) end
  end, "Opens the world map on the dungeon's entrance.")
  P.locB:SetPoint("LEFT", back, "RIGHT", 10, 0)
  P.routeCB = CreateFrame("CheckButton", nil, P, "UICheckButtonTemplate")
  P.routeCB:SetSize(24, 24)
  P.routeCB:SetPoint("LEFT", P.locB, "RIGHT", 14, 0)
  local rl = (type(P.routeCB.Text) == "table" and P.routeCB.Text) or (type(P.routeCB.text) == "table" and P.routeCB.text) or nil
  if not rl then rl = P.routeCB:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); rl:SetPoint("LEFT", P.routeCB, "RIGHT", 2, 0) end
  rl:SetText("In my route")
  P.routeCB:SetScript("OnClick", function(self)
    if not self:GetChecked() and ns.Tracker and ns.Tracker.ConfirmSkipDungeon then
      self:SetChecked(true); ns.Tracker.ConfirmSkipDungeon(cur)
    else ns.SetDungeon(cur, self:GetChecked() and true or false) end
    J.RenderPage()
  end)
  P.readyB = Button(P, "Get ready", 130, function()
    if ns.db.prep == cur then ns.StopPrep() else ns.StartPrep(cur) end
    J.RenderPage()
  end, "A side route that walks every quest chain and picks up every quest this dungeon has for you.")
  P.readyB:SetPoint("LEFT", P.routeCB, "RIGHT", 96, 0)
  P.tabs = {}
  local tx = -8
  for _, t in ipairs({ { "runs", "Runs" }, { "bosses", "Bosses" }, { "quests", "Quests" } }) do
    local b = Button(P, t[2], 96, function() tab, selected = t[1], nil; J.RenderPage() end)
    b.key = t[1]
    b:SetPoint("TOPRIGHT", tx, -40)
    tx = tx - 100
    P.tabs[#P.tabs + 1] = b
  end
  P.factionB = Button(P, "My faction", 110, function() DB().otherFaction = not DB().otherFaction or nil; selected = nil; J.RenderPage() end,
    "Show only your faction's quests, or both factions'.")
  P.factionB:SetPoint("TOPRIGHT", tx - 10, -40)
  local listBox = Panel(P)
  listBox:SetPoint("TOPLEFT", 4, -78); listBox:SetPoint("BOTTOMLEFT", 4, 4); listBox:SetWidth(LIST_W)
  P.list = Scroll(listBox)
  P.list:SetPoint("TOPLEFT", 6, -6); P.list:SetPoint("BOTTOMRIGHT", -26, 6)
  P.empty = listBox:CreateFontString(nil, "OVERLAY"); Font(P.empty, { "GameFontHighlightSmall" })
  P.empty:SetPoint("TOPLEFT", 10, -10); P.empty:SetWidth(LIST_W - 20); P.empty:SetJustifyH("LEFT")
  local detailBox = Panel(P)
  detailBox:SetPoint("TOPLEFT", listBox, "TOPRIGHT", 8, 0); detailBox:SetPoint("BOTTOMRIGHT", -4, 4)
  P.detailScroll = Scroll(detailBox)
  P.detailScroll:SetPoint("TOPLEFT", 8, -8); P.detailScroll:SetPoint("BOTTOMRIGHT", -28, 8)
  P.detail = Lines(P.detailScroll.child, W - LIST_W - 70)

  -- Character Logs
  logsView = CreateFrame("Frame", nil, f)
  logsView:SetPoint("TOPLEFT", 14, -44); logsView:SetPoint("BOTTOMRIGHT", -14, 14)
  local back2 = Button(logsView, "< All dungeons", 120, function() ShowView("home"); RenderHome() end)
  back2:SetPoint("TOPLEFT", 8, -4)
  local lt = logsView:CreateFontString(nil, "OVERLAY"); Font(lt, { "GameFontNormalLarge" })
  lt:SetPoint("LEFT", back2, "RIGHT", 14, 0)
  lt:SetText("Character Logs " .. GREY .. "- click a run for its details|r")
  logsView.scroll = Scroll(logsView)
  logsView.scroll:SetPoint("TOPLEFT", 8, -36); logsView.scroll:SetPoint("BOTTOMRIGHT", -28, 4)
  logsView.empty = logsView:CreateFontString(nil, "OVERLAY"); Font(logsView.empty, { "GameFontHighlight" })
  logsView.empty:SetPoint("CENTER")
  logsView.empty:SetText("No runs yet. Every dungeon run is recorded on its own from now on.")

  ShowView("home")
end

local function Place()
  frame:ClearAllPoints()
  local p = DB().pos
  if p then frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p[1], p[2])
  else frame:SetPoint("CENTER") end
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------
function J.Refresh()
  if not frame or not frame:IsShown() then return end
  if view == "home" then RenderHome() elseif view == "page" then J.RenderPage() else RenderLogs() end
end
J.RefreshIfShown = J.Refresh

function J.Toggle()
  if frame and frame:IsShown() then frame:Hide(); return end
  J.Open()
end

function J.Open()
  if InCombatLockdown and InCombatLockdown() and not frame then ns.Print("the journal opens after combat."); return end
  if not frame then Build(); Place() end
  ns.Safe("JournalScan", J.ScanGame)
  frame:Show()
  J.Refresh()
end

--- Open the journal on a dungeon (route name or place), optionally on a tab and an item.
function J.OpenDungeon(name, toTab, sel)
  local d = Dungeon(name) or ns.RunLog.Dungeon(name)
  if not d then J.Open(); return end
  if not frame or not frame:IsShown() then J.Open() end
  cur = d.name
  tab = toTab or ((cur == (ns.RunLog.Current() or {}).d) and "bosses" or "quests")
  selected = sel
  ShowView("page")
  J.RenderPage()
end

---------------------------------------------------------------------------
-- Hooks into the route (Core.lua stays as it is): the route's dungeon steps, the get-ready route and
-- the tracker ask these three; they now answer from our journal instead of the old DungeonJournal addon.
---------------------------------------------------------------------------
--- Open the journal on a dungeon step's page (the tracker's "Open in the Dungeon Journal"), or the list.
function ns.OpenJournal(step)
  step = step or (ns.route and ns.route.step)
  if step and step.dungeon then J.OpenDungeon(step.dungeon) else J.Toggle() end
  return true
end

--- A quest's entry for the tracker: where it starts, its objective, and the chain before it
--- ({ {id, name}, ... }, cached, no game calls; the tracker redraws often).
function ns.JournalQuest(id)
  local q = Quest(id)
  if not q then return nil end
  local out = { objective = q.ot }
  local g = q.g
  if g then out.pickup = g[2] and (g[1] .. ", " .. (ns.MapName(g[2]) or "?")) or g[1] end
  local chain = J.StaticChain(id)
  if #chain > 0 then out.chain = chain end
  return out
end

--- The dungeon you're in: the route's own answer when it knows it, else ours (the game's instance ID,
--- or its name for the dungeon, as in the Encounter Journal).
local routeCurrent = ns.CurrentDungeon
function ns.CurrentDungeon()
  local r = routeCurrent and routeCurrent()
  if not r then return nil end
  for _, d in ipairs(ns.dungeonDB or {}) do
    if d.name == r or d.place == r then return r end
  end
  local _, _, _, _, _, _, _, id = GetInstanceInfo()
  for _, d in ipairs(ns.dungeonDB or {}) do
    if (id and d.inst == id) then return d.place or d.name end
    for _, n in ipairs(d.ej or {}) do if n == r then return d.place or d.name end end
  end
  return r
end
