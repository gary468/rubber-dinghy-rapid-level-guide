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

local W, H = 940, 680
local CARD_H = 112
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
    local tiers = 0
    if EJ_GetNumTiers then local ok, n = pcall(EJ_GetNumTiers); if ok and n then tiers = n end end
    report.tiers = tiers
    -- Forever's client reports no tiers: then read whatever the journal has selected (one pass)
    local tierList = {}
    for t = 1, tiers do tierList[#tierList + 1] = t end
    if #tierList == 0 then tierList[1] = false end
    local prevTier = EJ_GetCurrentTier and select(2, pcall(EJ_GetCurrentTier))
    for _, t in ipairs(tierList) do
      if t and EJ_SelectTier then pcall(EJ_SelectTier, t) end
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
            local icon, display
            if EJ_GetCreatureInfo then
              local okC, _, _, _, disp, ic = pcall(EJ_GetCreatureInfo, 1, encID)
              if okC then icon, display = ic, disp end
            end
            bosses[#bosses + 1] = { name = ename, desc = edesc, id = encID, icon = icon, display = display }
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
            ej[d.name] = ej[d.name] or { id = id, desc = desc, art = button or bg, bg = bg, bosses = mineBosses }
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
            -- Forever's group finder gives the top level (its bottom comes back as 0): keep our bottom
            if hi and hi > 0 then lfgLevels[d.name] = { (lo and lo > 0) and lo or d.lo, hi } end
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
-- Look: the game's own textures, each checked in the client before use, with plain fallbacks.
---------------------------------------------------------------------------
local function Font(fs, names) local n = ns.Font(names); if _G[n] then fs:SetFontObject(_G[n]) end end

local probe            -- a hidden texture, for clients without GetFileIDFromPath
local texOK = {}
local function Has(path)
  if not path then return false end
  if type(path) == "number" then return true end
  local v = texOK[path]
  if v ~= nil then return v end
  v = false
  if GetFileIDFromPath then
    local ok, id = pcall(GetFileIDFromPath, path)
    if ok then v = id ~= nil and id ~= 0; texOK[path] = v; return v end
  end
  if probe then
    local ok, set = pcall(probe.SetTexture, probe, path)
    v = ok and set and true or false
  end
  texOK[path] = v
  return v
end

local TEX = {
  rock = "Interface\\FrameGeneral\\UI-Background-Rock",
  marble = "Interface\\FrameGeneral\\UI-Background-Marble",
  goldBorder = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
  border = "Interface\\DialogFrame\\UI-DialogBox-Border",
  header = "Interface\\DialogFrame\\UI-DialogBox-Header",
  parchment = "Interface\\QuestFrame\\QuestBG",
  questHL = "Interface\\QuestFrame\\UI-QuestTitleHighlight",
  tipBorder = "Interface\\Tooltips\\UI-Tooltip-Border",
  white = "Interface\\Buttons\\WHITE8X8",
  mask = "Interface\\CharacterFrame\\TempPortraitAlphaMask",
}
local ICON = {
  start = "Interface\\GossipFrame\\AvailableQuestIcon",
  turnin = "Interface\\GossipFrame\\ActiveQuestIcon",
  objective = "Interface\\Icons\\INV_Misc_Note_01",
  chain = "Interface\\Icons\\INV_Misc_Book_09",
  reward = "Interface\\Icons\\INV_Misc_Coin_01",
  share = "Interface\\Icons\\INV_Misc_GroupNeedMore",
  map = "Interface\\Icons\\INV_Misc_Map_01",
  boss = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull",
  clock = "Interface\\Icons\\INV_Misc_PocketWatch_01",
  drop = "Interface\\Icons\\INV_Misc_Bag_10",
  done = "Interface\\RaidFrame\\ReadyCheck-Ready",
  alliance = "Interface\\TargetingFrame\\UI-PVP-Alliance",
  horde = "Interface\\TargetingFrame\\UI-PVP-Horde",
  quests = "Interface\\GossipFrame\\AvailableQuestIcon",
}
-- the PvP crest textures hold the emblem in their top-left part
local CREST_TC = { 0, 0.62, 0, 0.62 }
local function Ico(path, size)
  if not Has(path) then return "" end
  return ("|T%s:%d:%d:0:0|t "):format(path, size or 16, size or 16)
end

-- Parchment page colors (dark ink on light paper)
local P_TITLE, P_HEAD, P_MUTED, P_GOOD, P_WARN, P_BAD, P_LINK =
  "|cff2b1709", "|cff6a2c04", "|cff6b5537", "|cff1d6b12", "|cff9a4a00", "|cff8f1a10", "|cff1a4f8c"
local INK = { 0.18, 0.11, 0.05 }

local function Grad(tex, orient, a, b)
  tex:SetColorTexture(1, 1, 1, 1)
  if CreateColor and tex.SetGradient then
    local ok = pcall(tex.SetGradient, tex, orient, CreateColor(a[1], a[2], a[3], a[4]), CreateColor(b[1], b[2], b[3], b[4]))
    if ok then return end
  end
  if tex.SetGradientAlpha then pcall(tex.SetGradientAlpha, tex, orient, a[1], a[2], a[3], a[4], b[1], b[2], b[3], b[4]) end
end

local function Backdrop(f, bg, br, edge, edgeSize)
  if not f.SetBackdrop then return end
  f:SetBackdrop({ bgFile = TEX.white, edgeFile = edge or TEX.tipBorder, edgeSize = edgeSize or 12,
                  insets = { left = 3, right = 3, top = 3, bottom = 3 } })
  f:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
  f:SetBackdropBorderColor(br[1], br[2], br[3], br[4] or 1)
end

local GOLD_EDGE, DIM_EDGE = { 0.85, 0.68, 0.3 }, { 0.42, 0.34, 0.2 }

local function Panel(parent)
  local p = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  Backdrop(p, { 0.05, 0.04, 0.03, 0.9 }, DIM_EDGE)
  return p
end

-- A parchment page: the quest frame's paper when the client has it, else a paper color.
local function Parchment(parent)
  local p = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  Backdrop(p, { 0.80, 0.71, 0.53, 1 }, GOLD_EDGE)
  local t = p:CreateTexture(nil, "BACKGROUND", nil, 1)
  t:SetPoint("TOPLEFT", 4, -4); t:SetPoint("BOTTOMRIGHT", -4, 4)
  if Has(TEX.parchment) then
    t:SetTexture(TEX.parchment); t:SetTexCoord(0, 0.5859375, 0, 0.65625)
  else
    Grad(t, "VERTICAL", { 0.74, 0.64, 0.46, 1 }, { 0.88, 0.80, 0.62, 1 })
  end
  p.paper = t
  return p
end

-- Flat buttons in the journal's own style (the red panel buttons all looked alike).
local function FlatButton(parent, text, w, onClick, tip, h)
  local b = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  b:SetSize(w, h or 24)
  Backdrop(b, { 0.13, 0.10, 0.06, 0.95 }, DIM_EDGE)
  b.label = b:CreateFontString(nil, "OVERLAY"); Font(b.label, { "GameFontNormal" })
  b.label:SetPoint("CENTER", 0, 0)
  b.label:SetText(text)
  function b:SetText(s) self.label:SetText(s) end
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetPoint("TOPLEFT", 3, -3); hl:SetPoint("BOTTOMRIGHT", -3, 3)
  hl:SetColorTexture(1, 0.82, 0.3, 0.12)
  b:SetScript("OnClick", onClick)
  if tip then
    b:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:AddLine(tip, 1, 1, 1, true); GameTooltip:Show() end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  return b
end

-- Tabs that look like tabs: the chosen one is lit and joins the page below it.
local function Tab(parent, text, w, onClick)
  local b = FlatButton(parent, text, w, onClick, nil, 28)
  function b:SetActive(on)
    if on then
      Backdrop(self, { 0.30, 0.22, 0.10, 1 }, GOLD_EDGE)
      self.label:SetTextColor(1, 0.86, 0.35)
    else
      Backdrop(self, { 0.09, 0.07, 0.05, 0.95 }, DIM_EDGE)
      self.label:SetTextColor(0.62, 0.55, 0.42)
    end
  end
  return b
end

local function Scroll(parent)
  local sf = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
  local child = CreateFrame("Frame", nil, sf)
  child:SetSize(10, 10)
  sf:SetScrollChild(child)
  sf.child = child
  return sf
end

-- A column of text lines (wrapping) with optional click, tooltip, icons and rules, for the pages.
-- dark = ink on parchment.
local function Lines(parent, width, dark)
  local L = { parent = parent, width = width, fs = {}, btn = {}, rules = {}, y = 0, n = 0, nb = 0, nr = 0 }
  function L:Reset()
    for _, f in ipairs(self.fs) do f:Hide() end
    for _, b in ipairs(self.btn) do b:Hide() end
    for _, r in ipairs(self.rules) do r:Hide() end
    self.y, self.n, self.nb, self.nr = -6, 0, 0, 0
  end
  function L:Add(text, o)
    o = o or {}
    self.n = self.n + 1
    local fs = self.fs[self.n]
    if not fs then fs = self.parent:CreateFontString(nil, "OVERLAY"); self.fs[self.n] = fs end
    Font(fs, o.font or (dark and { "QuestFont", "GameFontHighlight" } or { "GameFontHighlight" }))
    if dark then
      fs:SetTextColor(INK[1], INK[2], INK[3]); fs:SetShadowOffset(0, 0)
    else
      fs:SetTextColor(1, 1, 1); fs:SetShadowOffset(1, -1)
    end
    fs:SetJustifyH("LEFT")
    if fs.SetWordWrap then fs:SetWordWrap(true) end
    fs:SetWidth(self.width - (o.indent or 0) - 12)
    fs:ClearAllPoints()
    self.y = self.y - (o.gap or 2)
    fs:SetPoint("TOPLEFT", self.parent, "TOPLEFT", 10 + (o.indent or 0), self.y)
    fs:SetText((o.icon and Ico(o.icon, o.iconSize) or "") .. text)
    fs:Show()
    local h = math.max(12, fs:GetStringHeight() or 12)
    if o.onClick or o.tip or o.link then
      self.nb = self.nb + 1
      local b = self.btn[self.nb]
      if not b then
        b = CreateFrame("Button", nil, self.parent)
        local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 0.9, 0.5, dark and 0.25 or 0.12)
        b:SetScript("OnEnter", function(s)
          if s.link then GameTooltip:SetOwner(s, "ANCHOR_RIGHT"); pcall(GameTooltip.SetHyperlink, GameTooltip, s.link); GameTooltip:Show()
          elseif s.tip then GameTooltip:SetOwner(s, "ANCHOR_RIGHT"); GameTooltip:AddLine(s.tip, 1, 1, 1, true); GameTooltip:Show() end
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:SetScript("OnClick", function(s) if s.onClick then s.onClick() end end)
        self.btn[self.nb] = b
      end
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", fs, "TOPLEFT", -2, 1)
      b:SetSize(self.width - (o.indent or 0) - 12, h + 2)
      b.onClick, b.tip, b.link = o.onClick, o.tip, o.link
      b:Show()
    end
    self.y = self.y - h
    return fs
  end
  --- A section header: icon, title, and a thin rule under it.
  function L:Head(text, icon)
    self:Gap(10)
    self:Add((dark and P_HEAD or GOLD) .. text .. "|r", { font = dark and { "QuestTitleFont", "GameFontNormalLarge" } or { "GameFontNormal" },
      icon = icon, iconSize = 18 })
    self.nr = self.nr + 1
    local r = self.rules[self.nr]
    if not r then r = self.parent:CreateTexture(nil, "ARTWORK"); self.rules[self.nr] = r end
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", self.parent, "TOPLEFT", 10, self.y - 3)
    r:SetSize(self.width - 24, 1)
    if dark then r:SetColorTexture(0.42, 0.26, 0.10, 0.55) else r:SetColorTexture(0.85, 0.68, 0.3, 0.4) end
    r:Show()
    self.y = self.y - 7
  end
  function L:Gap(n) self.y = self.y - (n or 8) end
  function L:Height() return -self.y + 12 end
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
-- Dungeon art: the game's own pictures. First the Encounter Journal's art for the dungeon (if the
-- client has it), then Blizzard's loading screen for the dungeon (one per Classic dungeon; spellings
-- vary, so a few are tried), then one named after the dungeon (in case Forever ships one for its new
-- dungeons), then the loading screen of the continent it's on. Looked up once per dungeon.
---------------------------------------------------------------------------
local LEVEL_TINT = { { 0.20, 0.35, 0.18 }, { 0.18, 0.28, 0.40 }, { 0.36, 0.26, 0.14 }, { 0.38, 0.16, 0.14 } }
local LS = "Interface\\Glues\\LoadingScreens\\"
local LOADSCREEN = {
  ["Ragefire Chasm"] = { "LoadScreenRagefireChasm" },
  ["Wailing Caverns"] = { "LoadScreenWailingCaverns" },
  ["The Deadmines"] = { "LoadScreenDeadmines" },
  ["Shadowfang Keep"] = { "LoadScreenShadowfangKeep" },
  ["Blackfathom Deeps"] = { "LoadScreenBlackfathomDeeps" },
  ["The Stockade"] = { "LoadScreenStormwindStockades", "LoadScreenStockades", "LoadScreenStockade" },
  ["Gnomeregan"] = { "LoadScreenGnomeregan" },
  ["Razorfen Kraul"] = { "LoadScreenRazorfenKraul" },
  ["Scarlet Monastery"] = { "LoadScreenScarletMonastery", "LoadScreenMonastery" },
  ["Razorfen Downs"] = { "LoadScreenRazorfenDowns", "LoadScreenRazorfenDown" },
  ["Uldaman"] = { "LoadScreenUldaman" },
  ["Zul'Farrak"] = { "LoadScreenZulFarrak" },
  ["Maraudon"] = { "LoadScreenMaraudon" },
  ["Sunken Temple"] = { "LoadScreenSunkenTemple", "LoadScreenTempleOfAtalHakkar" },
  ["Blackrock Depths"] = { "LoadScreenBlackrockDepths", "LoadScreenBlackrock" },
  ["Blackrock Spire"] = { "LoadScreenBlackrockSpire", "LoadScreenBlackrock" },
  ["Dire Maul"] = { "LoadScreenDireMaul" },
  ["Stratholme"] = { "LoadScreenStratholme" },
  ["Scholomance"] = { "LoadScreenScholomance" },
}
local CONTINENT_SCREEN = { [1415] = { "LoadScreenEasternKingdom", "LoadScreenEasternKingdoms" },
                           [1414] = { "LoadScreenKalimdor" } }
local cardArt = {}   -- [dungeon name] = { path, isLoadingScreen } or false

local function CardArt(d)
  local a = cardArt[d.name]
  if a ~= nil then return a end
  a = false
  local e = ej and ej[d.name]
  if e and (e.art or e.bg) then a = { e.art or e.bg, false } end
  if not a then
    local tries = {}
    for _, n in ipairs(LOADSCREEN[d.place or d.name] or LOADSCREEN[d.name] or {}) do tries[#tries + 1] = n end
    local camel = (d.place or d.name):gsub("^The ", ""):gsub("[^%w ]", ""):gsub("(%w+)", function(w) return w:sub(1, 1):upper() .. w:sub(2) end):gsub(" ", "")
    tries[#tries + 1] = "LoadScreen" .. camel
    local cont = d.ent and ns.Continent and ns.Continent(d.ent[1])
    for _, n in ipairs(CONTINENT_SCREEN[cont] or {}) do tries[#tries + 1] = n end
    for _, n in ipairs(tries) do
      if Has(LS .. n) then a = { LS .. n, true }; break end
    end
  end
  cardArt[d.name] = a
  local rep = ns.db and ns.db.journalReport
  if rep then rep.art = rep.art or {}; rep.art[d.name] = a and a[1] or "none" end
  return a
end

--- Paint a dungeon's art into a texture, showing a band of it (top..bottom of the picture).
local function PaintArt(tex, d, top, bottom)
  local art = CardArt(d)
  if art then
    tex:SetTexture(art[1])
    if art[2] then tex:SetTexCoord(0, 1, top or 0.33, bottom or 0.67) else tex:SetTexCoord(0, 1, 0, 1) end
    tex:SetVertexColor(1, 1, 1)
  else
    tex:SetTexCoord(0, 1, 0, 1)
    local lo = d.lo or 10
    local t = LEVEL_TINT[math.min(4, math.max(1, math.floor((lo - 10) / 13) + 1))]
    Grad(tex, "HORIZONTAL", { t[1] * 1.4, t[2] * 1.4, t[3] * 1.4, 1 }, { t[1] * 0.5, t[2] * 0.5, t[3] * 0.5, 1 })
  end
  return art
end

--- A boss portrait: the game's journal portrait (by creature display) when there is one, else a skull.
local function PaintPortrait(tex, b)
  if b.display and SetPortraitTextureFromCreatureDisplayID then
    if pcall(SetPortraitTextureFromCreatureDisplayID, tex, b.display) then tex:SetTexCoord(0, 1, 0, 1); return true end
  end
  if b.icon then tex:SetTexture(b.icon); tex:SetTexCoord(0, 1, 0, 1); return true end
  tex:SetTexture(ICON.boss); tex:SetTexCoord(0, 1, 0, 1)
  return false
end

---------------------------------------------------------------------------
-- Home: the dungeon cards
---------------------------------------------------------------------------
local cards = {}

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
    c:SetBackdrop({ edgeFile = TEX.tipBorder, edgeSize = 14 })
    c:SetBackdropBorderColor(GOLD_EDGE[1], GOLD_EDGE[2], GOLD_EDGE[3], 1)
  end
  c.art = c:CreateTexture(nil, "BACKGROUND")
  c.art:SetPoint("TOPLEFT", 3, -3); c.art:SetPoint("BOTTOMRIGHT", -3, 3)
  c.top = c:CreateTexture(nil, "BORDER")        -- dark band behind the name
  c.top:SetPoint("TOPLEFT", 3, -3); c.top:SetPoint("TOPRIGHT", -3, -3); c.top:SetHeight(40)
  Grad(c.top, "VERTICAL", { 0, 0, 0, 0 }, { 0, 0, 0, 0.8 })
  c.bottom = c:CreateTexture(nil, "BORDER")     -- and behind the levels
  c.bottom:SetPoint("BOTTOMLEFT", 3, 3); c.bottom:SetPoint("BOTTOMRIGHT", -3, 3); c.bottom:SetHeight(30)
  Grad(c.bottom, "VERTICAL", { 0, 0, 0, 0.85 }, { 0, 0, 0, 0 })
  c.glow = c:CreateTexture(nil, "HIGHLIGHT")
  c.glow:SetPoint("TOPLEFT", 3, -3); c.glow:SetPoint("BOTTOMRIGHT", -3, 3)
  if Has(TEX.questHL) then c.glow:SetTexture(TEX.questHL); c.glow:SetBlendMode("ADD"); c.glow:SetAlpha(0.6)
  else c.glow:SetColorTexture(1, 0.85, 0.4, 0.12) end
  c.name = c:CreateFontString(nil, "OVERLAY"); Font(c.name, { "QuestTitleFontBlackShadow", "GameFontNormalLarge" })
  c.name:SetTextColor(1, 0.86, 0.4)
  c.name:SetPoint("TOPLEFT", 14, -11)
  c.count = c:CreateFontString(nil, "OVERLAY"); Font(c.count, { "GameFontHighlight" })
  c.count:SetPoint("TOPRIGHT", -14, -13)
  c.qicon = c:CreateTexture(nil, "OVERLAY"); c.qicon:SetSize(16, 16)
  c.qicon:SetPoint("RIGHT", c.count, "LEFT", -3, 0)
  c.tick = c:CreateTexture(nil, "OVERLAY"); c.tick:SetTexture(ICON.done); c.tick:SetSize(22, 22)
  c.tick:SetPoint("RIGHT", c.qicon, "LEFT", -2, 0)
  c.levels = c:CreateFontString(nil, "OVERLAY"); Font(c.levels, { "GameFontNormal" })
  c.levels:SetPoint("BOTTOMLEFT", 14, 10)
  c.tag = c:CreateFontString(nil, "OVERLAY"); Font(c.tag, { "GameFontHighlightSmall" })
  c.tag:SetPoint("BOTTOMRIGHT", -14, 11)
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
  local cw = math.floor((W - 70) / 2)
  local o = DB()
  for i, d in ipairs(list) do
    local c = Card(i)
    c.d = d
    c:SetSize(cw, CARD_H)
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", homeView.scroll.child, "TOPLEFT", ((i - 1) % 2) * (cw + 12), -math.floor((i - 1) / 2) * (CARD_H + 12))
    PaintArt(c.art, d, 0.30, 0.66)
    c.name:SetText(d.name)
    local mine, done = J.Counts(d)
    local cnt = #mine == 0 and "no quests" or ((done > 0 and (done .. "/") or "") .. #mine .. (#mine == 1 and " quest" or " quests"))
    c.count:SetText(cnt)
    if Has(ICON.start) and #mine > 0 then c.qicon:SetTexture(ICON.start); c.qicon:Show() else c.qicon:Hide() end
    c.tick:SetShown(#mine > 0 and done == #mine and not o.hideTick)
    local lo, hi = Levels(d)
    c.levels:SetText(("Level %d-%d"):format(lo, hi))
    local tag = {}
    if d.forever then tag[#tag + 1] = BLUE .. "WoW Forever|r" end
    if J.Step(d.name) and ns.DungeonOn(d.name) then tag[#tag + 1] = GREEN .. "In your route|r" end
    c.tag:SetText(table.concat(tag, "   "))
    c:SetAlpha((hideMode and o.hidden[d.name]) and 0.35 or 1)
    c:Show()
  end
  for i = #list + 1, #cards do cards[i]:Hide() end
  homeView.scroll.child:SetSize(W - 50, math.ceil(#list / 2) * (CARD_H + 12) + 10)
  homeView.empty:SetShown(#list == 0)
  homeView.hideB:SetText(hideMode and "Done hiding" or "Hide Dungeons")
  homeView.foreverB:SetText(o.foreverOnly and "All dungeons" or "Forever only")
end

---------------------------------------------------------------------------
-- Dungeon page
---------------------------------------------------------------------------
local rows = {}
local ROW_H = 28

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
  r = CreateFrame("Button", nil, pageView.list.child, BackdropTemplateMixin and "BackdropTemplate" or nil)
  r:SetSize(LIST_W - 30, ROW_H)
  Backdrop(r, { 0.10, 0.08, 0.05, 0.85 }, { 0.30, 0.24, 0.14, 1 })
  r.sel = r:CreateTexture(nil, "BACKGROUND"); r.sel:SetAllPoints(); Grad(r.sel, "HORIZONTAL", { 1, 0.78, 0.3, 0.35 }, { 1, 0.78, 0.3, 0.02 })
  r.bar = r:CreateTexture(nil, "ARTWORK"); r.bar:SetPoint("TOPLEFT"); r.bar:SetPoint("BOTTOMLEFT"); r.bar:SetWidth(3)
  r.bar:SetColorTexture(1, 0.82, 0.3, 1)
  local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 0.9, 0.6, 0.08)
  r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(22, 22); r.icon:SetPoint("LEFT", 8, 0)
  -- level badge on a boss portrait
  r.badge = CreateFrame("Frame", nil, r, BackdropTemplateMixin and "BackdropTemplate" or nil)
  r.badge:SetSize(20, 16); r.badge:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMLEFT", -4, -3)
  Backdrop(r.badge, { 0.05, 0.04, 0.03, 0.95 }, GOLD_EDGE, nil, 8)
  r.badge.text = r.badge:CreateFontString(nil, "OVERLAY"); Font(r.badge.text, { "GameFontHighlightSmall" })
  r.badge.text:SetPoint("CENTER", 0, 0)
  r.badge:Hide()
  r.text = r:CreateFontString(nil, "OVERLAY"); Font(r.text, { "GameFontHighlight" })
  r.text:SetPoint("LEFT", r.icon, "RIGHT", 8, 0); r.text:SetPoint("RIGHT", -52, 0); r.text:SetJustifyH("LEFT")
  if r.text.SetWordWrap then r.text:SetWordWrap(false) end
  r.sub = r:CreateFontString(nil, "OVERLAY"); Font(r.sub, { "GameFontDisableSmall", "GameFontHighlightSmall" })
  r.sub:SetPoint("TOPLEFT", r.text, "BOTTOMLEFT", 0, -2); r.sub:SetPoint("RIGHT", -52, 0); r.sub:SetJustifyH("LEFT")
  if r.sub.SetWordWrap then r.sub:SetWordWrap(false) end
  r.right = r:CreateFontString(nil, "OVERLAY"); Font(r.right, { "GameFontHighlightSmall" })
  r.right:SetPoint("RIGHT", -8, 0)
  r.crestA = r:CreateTexture(nil, "OVERLAY"); r.crestA:SetSize(18, 18)
  r.crestH = r:CreateTexture(nil, "OVERLAY"); r.crestH:SetSize(18, 18)
  r.crestH:SetPoint("RIGHT", -8, 0); r.crestA:SetPoint("RIGHT", r.crestH, "LEFT", 0, 0)
  for _, c in ipairs({ { r.crestA, ICON.alliance }, { r.crestH, ICON.horde } }) do
    if Has(c[2]) then c[1]:SetTexture(c[2]); c[1]:SetTexCoord(CREST_TC[1], CREST_TC[2], CREST_TC[3], CREST_TC[4]) end
    c[1]:Hide()
  end
  r:SetScript("OnClick", function(self) selected = self.key; J.RenderPage() end)
  rows[i] = r
  return r
end

local QUEST_ICON = { [1] = ICON.turnin, [2] = "Interface\\GossipFrame\\IncompleteQuestIcon",
  [3] = ICON.start, [4] = ICON.start, [5] = ICON.start, [6] = ICON.start, [7] = ICON.done }

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
      out[#out + 1] = { name = b.name, desc = b.desc, icon = b.icon, display = b.display, enc = b.id, npc = ours and ours[2],
                        level = ours and ours[3], drops = ours and ours[4] }
    end
  else
    for _, b in ipairs(d.bosses or {}) do out[#out + 1] = { name = b[1], npc = b[2], level = b[3], drops = b[4] } end
  end
  return out
end

local function Where(loc, dark)
  if not loc then return nil end
  if not loc[2] then return loc[1] .. ((dark and P_MUTED or GREY) .. "  (inside the dungeon)|r") end
  return ("%s%s  -  %s %.1f, %.1f|r"):format(loc[1], dark and P_MUTED or GREY, ns.MapName(loc[2]) or "?", loc[3], loc[4])
end

local ST_PAGE = {
  [1] = P_GOOD .. "Ready to turn in|r", [2] = P_WARN .. "In your quest log|r", [3] = P_GOOD .. "You can pick it up now|r",
  [4] = P_MUTED .. "Available from level %d|r", [5] = P_WARN .. "Needs earlier quests first|r",
  [6] = P_MUTED .. "Available from level %d|r", [7] = P_GOOD .. "Completed|r",
}

local function RenderQuestDetail(L, id)
  local q = Quest(id)
  if not q then return end
  local s = J.QuestStatus(id)
  L:Add(P_TITLE .. q.n .. "|r", { font = { "QuestTitleFont", "GameFontNormalLarge" }, gap = 4 })
  local tags = { ("Level %d"):format(q.l or 0) }
  if (q.r or 0) > 0 then tags[#tags + 1] = ("requires %d"):format(q.r) end
  if q.fa then tags[#tags + 1] = (q.fa == "A" and "Alliance" or "Horde") .. " only" end
  if q.cl then tags[#tags + 1] = "class quest" end
  L:Add(P_MUTED .. table.concat(tags, "  -  ") .. "|r", { font = { "QuestFontNormalSmall", "GameFontHighlightSmall" } })
  local st = ST_PAGE[s]
  if s == ST.SOON or s == ST.LOW then st = st:format(q.r or 0) end
  if s == ST.LOG then
    local have, need = ns.Progress and ns.Progress(id)
    if need and need > 0 then st = st .. P_MUTED .. ("  (%d/%d)"):format(have, need) .. "|r" end
  end
  L:Add(st, { gap = 6, icon = QUEST_ICON[s], iconSize = 16 })
  local chain = J.Chain(id)
  if s == ST.LOCKED and #chain > 0 then
    local doneN = 0
    for _, c in ipairs(chain) do if c.done then doneN = doneN + 1 end end
    L:Add(P_WARN .. ("Needs a quest chain first: you're on step %d of %d."):format(doneN + 1, #chain + 1) .. "|r", { gap = 2 })
  end

  if q.ot then
    L:Head("Objective", ICON.objective)
    L:Add(q.ot, { gap = 4 })
  end
  local nq = ns.quests and ns.quests[id]
  if nq and nq.dr then
    for _, dr in ipairs(nq.dr) do L:Add(P_MUTED .. dr[1] .. ": " .. dr[2] .. "|r", { indent = 8, font = { "QuestFontNormalSmall", "GameFontHighlightSmall" } }) end
  end
  local rq = ns.quests and ns.quests[id]
  L:Head("Starts at", ICON.start)
  local g = (q.g and q.g[2]) and q.g or (rq and rq.g and rq.g[2] and rq.g) or q.g
  L:Add((Where(g, true) or (P_MUTED .. "Not in the quest database yet|r")) .. ((g and g[2]) and ("   " .. P_LINK .. "Show on map|r") or ""), { gap = 4,
    onClick = (g and g[2]) and function() ShowSpot(g[1], g[2], g[3], g[4]) end or nil, tip = (g and g[2]) and "Show it on the world map." or nil })
  L:Head("Turn in", ICON.turnin)
  local t = (q.t and q.t[2]) and q.t or (rq and rq.t and rq.t[2] and rq.t) or q.t
  L:Add((Where(t, true) or (P_MUTED .. "Not in the quest database yet|r")) .. ((t and t[2]) and ("   " .. P_LINK .. "Show on map|r") or ""), { gap = 4,
    onClick = (t and t[2]) and function() ShowSpot(t[1], t[2], t[3], t[4]) end or nil, tip = (t and t[2]) and "Show it on the world map." or nil })
  if #chain > 0 then
    L:Head("Quest chain", ICON.chain)
    for i, c in ipairs(chain) do
      local mark = c.done and (P_GOOD .. "done|r") or (c.inlog and (P_WARN .. "in your log|r") or (P_MUTED .. "not yet|r"))
      L:Add(("%d.  %s  -  %s"):format(i, c.name, mark), { indent = 6, gap = 3,
        tip = c.giver and ("Starts at " .. (Where(c.giver) or "?") .. (c.giver[2] and "\nClick to show it on the map." or "")) or nil,
        onClick = (c.giver and c.giver[2]) and function() ShowSpot(c.giver[1], c.giver[2], c.giver[3], c.giver[4]) end or nil })
    end
    L:Add(("%d.  %s  -  %sthis quest|r"):format(#chain + 1, q.n, P_HEAD), { indent = 6, gap = 3 })
  end
  if q.nx then
    local nxq = Quest(q.nx) or (ns.quests and ns.quests[q.nx])
    local nm = (nxq and (nxq.n)) or (ns.dungeonChain and ns.dungeonChain[q.nx] and ns.dungeonChain[q.nx][1])
    if nm then L:Add(P_MUTED .. "Leads to: " .. nm .. "|r", { gap = 6 }) end
  end
  L:Head("Rewards", ICON.reward)
  local xp = J.QuestXP(id)
  L:Add(xp and (P_TITLE .. (q.xe and "about " or "") .. ns.RunLog.Thousands(xp) .. " XP|r" .. P_MUTED .. "  at your level|r")
    or (P_MUTED .. "No XP|r"), { gap = 4, font = { "QuestTitleFont", "GameFontNormalLarge" },
    tip = q.xe and "Forever's databases don't have this quest's XP yet: this is what a quest of its level usually gives." or nil })
  L:Add(q.sh and (P_GOOD .. "Shareable|r  -  accept it, then share it with your group.") or (P_MUTED .. "Can't be shared|r"),
    { gap = 6, icon = Has(ICON.share) and ICON.share or nil, iconSize = 16 })
end

local lootCache = {}
--- A boss's loot from the game's own Encounter Journal (read when the boss is opened, then kept).
local function BossLoot(d, b)
  if not (b.enc and EJ_SelectEncounter and EJ_GetNumLoot) then return nil end
  local c = lootCache[b.enc]
  if c and (c.complete or (c.tries or 0) >= 3) then return c end
  local e = ej and ej[d.name]
  if e and e.id then pcall(EJ_SelectInstance, e.id) end
  pcall(EJ_SelectEncounter, b.enc)
  local ok, n = pcall(EJ_GetNumLoot)
  local out, complete = {}, true
  for i = 1, (ok and n or 0) do
    local info
    if C_EncounterJournal and C_EncounterJournal.GetLootInfoByIndex then
      local okI, t = pcall(C_EncounterJournal.GetLootInfoByIndex, i)
      if okI and type(t) == "table" then info = t end
    elseif EJ_GetLootInfoByIndex then
      local okI, itemID, _, name, icon, slot, armor, link = pcall(EJ_GetLootInfoByIndex, i)
      if okI and itemID then info = { itemID = itemID, name = name, icon = icon, slot = slot, armorType = armor, link = link } end
    end
    if info and info.itemID then
      if not info.name or info.name == "" then
        local nm, link, q, _, _, _, _, _, _, icon = GetItemInfo(info.itemID)
        info.name, info.link, info.itemQuality, info.icon = nm, info.link or link, info.itemQuality or q, info.icon or icon
        if not nm then
          complete = false   -- the game hasn't loaded this item yet: ask for it, look again shortly
          if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, info.itemID) end
        end
      end
      out[#out + 1] = info
    end
  end
  out.complete = complete
  out.tries = ((c and c.tries) or 0) + 1   -- at most 3 looks for items still loading
  lootCache[b.enc] = out
  return out
end

local function QualityHex(q)
  if q and GetItemQualityColor then
    local ok, _, _, _, hex = pcall(GetItemQualityColor, q)
    if ok and hex then return "|c" .. hex end
  end
  return P_TITLE
end

local function RenderBossDetail(L, d, b)
  L:Add(P_TITLE .. (b.name or "?") .. "|r", { font = { "QuestTitleFont", "GameFontNormalLarge" }, gap = 4 })
  if b.level and b.level > 0 then L:Add(P_MUTED .. "Level " .. b.level .. " elite|r", { font = { "QuestFontNormalSmall", "GameFontHighlightSmall" } }) end
  if b.desc and b.desc ~= "" then L:Gap(4); L:Add(b.desc) end
  if b.drops then
    L:Head("Quest items it drops", ICON.drop)
    for _, dr in ipairs(b.drops) do
      local q = Quest(dr[2])
      L:Add(P_TITLE .. dr[1] .. "|r" .. P_MUTED .. "  -  for " .. (q and q.n or "a quest") .. "|r", { indent = 4, gap = 3,
        onClick = function() tab, selected = "quests", dr[2]; J.RenderPage() end, tip = "Click to open the quest." })
    end
  end
  local loot = BossLoot(d, b)
  if loot and #loot > 0 then
    L:Head("Loot", ICON.reward)
    for _, it in ipairs(loot) do
      local kind = { it.slot, it.armorType }
      local extra = (#kind > 0 and (kind[1] or "") ~= "") and (P_MUTED .. "   " .. table.concat(kind, ", ") .. "|r") or ""
      L:Add(QualityHex(it.itemQuality) .. (it.name or ("item " .. it.itemID)) .. "|r" .. extra,
        { gap = 4, icon = it.icon, iconSize = 22, link = it.link or ("item:" .. it.itemID) })
    end
    if not loot.complete and loot.tries < 3 and C_Timer then   -- item names still loading: look again in a moment
      local want = b.enc
      C_Timer.After(1.5, function()
        local cur2 = (cur and Dungeon(cur)) and Bosses(Dungeon(cur))[selected]
        if frame and frame:IsShown() and tab == "bosses" and cur2 and cur2.enc == want then J.RenderPage() end
      end)
    end
  end
  local n, best = 0, nil
  for _, run in ipairs(ns.RunLog.For(d.name)) do
    local t = run.bosses and run.bosses[b.name]
    if t then n = n + 1; if not best or t < best then best = t end end
  end
  L:Head("Your runs", ICON.clock)
  L:Add(n > 0 and (("Killed in %d run%s, fastest %s into the run."):format(n, n == 1 and "" or "s", ns.RunLog.Clock(best)))
    or (P_MUTED .. "Not killed in a logged run yet.|r"), { gap = 4 })
end

local function RunTitle(run)
  local when = date("%b %d  %H:%M", run.t0)
  local n, of = ns.RunLog.BossCount(run)
  return ("%s   %s   %s XP   %d/%d bosses"):format(when, ns.RunLog.Clock(ns.RunLog.Secs(run)),
    ns.RunLog.Thousands(ns.RunLog.MobXP(run)), n, of)
end

local function RenderRunDetail(L, run)
  local RL = ns.RunLog
  L:Add(P_TITLE .. (run.d or "?") .. "|r", { font = { "QuestTitleFont", "GameFontNormalLarge" }, gap = 4 })
  L:Add(P_MUTED .. date("%A %b %d %Y, %H:%M", run.t0) .. "|r", { font = { "QuestFontNormalSmall", "GameFontHighlightSmall" } })
  L:Head("The run", ICON.clock)
  L:Add(("Time  %s%s"):format(P_TITLE .. RL.Clock(RL.Secs(run)) .. "|r", run.done and ("   " .. P_GOOD .. "cleared|r") or ""), { gap = 4 })
  L:Add(("Mobs  %s%d killed, %s XP|r"):format(P_TITLE, run.kills or 0, RL.Thousands(RL.MobXP(run))), { gap = 3 })
  if (run.qxp or 0) > 0 then L:Add(("Quests handed in  %s%s XP|r"):format(P_TITLE, RL.Thousands(run.qxp)), { gap = 3 }) end
  L:Add(("Money looted  %s"):format(GetCoinTextureString and GetCoinTextureString(RL.Gold(run)) or (RL.Gold(run) .. "c")), { gap = 3 })
  L:Add(("Deaths  %s%d|r"):format(P_TITLE, run.deaths or 0), { gap = 3 })
  L:Add(("Level  %s%d%s|r"):format(P_TITLE, run.lv0 or 0, (run.lv1 and run.lv1 ~= run.lv0) and (" to " .. run.lv1) or ""), { gap = 3 })
  if (run.out or 0) > 60 then L:Add(("Time outside  %s%s|r"):format(P_TITLE, RL.Clock(run.out)), { gap = 3 }) end
  local d = Dungeon(run.d)
  if d then
    L:Head("Bosses", ICON.boss)
    for _, b in ipairs(d.bosses or {}) do
      local t = run.bosses[b[1]]
      L:Add((t and (P_GOOD .. b[1] .. "|r" .. P_MUTED .. "   at " .. RL.Clock(t) .. "|r")) or (P_MUTED .. b[1] .. "|r"), { indent = 4, gap = 3 })
    end
  end
  L:Gap(14)
  L:Add(P_BAD .. "Delete this run|r", { onClick = function() J.ConfirmDelete(run) end, tip = "Removes it from your Run Log (asks first)." })
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

-- The boss's 3D model on a stage of the dungeon's art (journal display when the client has it, else
-- by NPC ID); hidden when there's neither.
local function ShowModel(d, b)
  local M = pageView.model
  if not M then return 0 end
  local ok = false
  if b and b.display and M.SetDisplayInfo then ok = pcall(M.SetDisplayInfo, M, b.display)
  elseif b and b.npc and b.npc > 0 and M.SetCreature then ok = pcall(M.SetCreature, M, b.npc) end
  pageView.stage:SetShown(ok)
  if not ok then return 0 end
  PaintArt(pageView.stage.art, d, 0.25, 0.75)
  if M.SetRotation then pcall(M.SetRotation, M, 0.35) end
  return 190
end

-- The summary under the list: your progress here, at a glance.
local function RenderSummary(d)
  local S = pageView.summary
  local mine, done = J.Counts(d)
  local inLog, ready = 0, 0
  for _, id in ipairs(mine) do
    local s = J.QuestStatus(id)
    if s == ST.LOG then inLog = inLog + 1 elseif s == ST.READY then ready = ready + 1 end
  end
  local runs = ns.RunLog.For(d.name)
  local best
  for _, r in ipairs(runs) do local s = ns.RunLog.Secs(r); if s > 0 and (not best or s < best) then best = s end end
  local lines = {
    GOLD .. "Your progress|r",
    ("%s%d|r of %d quests done%s"):format(WHITE, done, #mine, (inLog + ready > 0) and ("  -  " .. GREEN .. (inLog + ready) .. " in your log|r") or ""),
    ("%s%d|r bosses   -   %s%d|r run%s logged%s"):format(WHITE, #(d.bosses or {}), WHITE, #runs, #runs == 1 and "" or "s",
      best and ("   -   best " .. WHITE .. ns.RunLog.Clock(best) .. "|r") or ""),
  }
  S.text:SetText(table.concat(lines, "\n"))
end

function J.RenderPage()
  local d = cur and Dungeon(cur)
  if not d then return end
  local P = pageView
  local lo, hi = Levels(d)
  PaintArt(P.banner.art, d, 0.28, 0.58)
  P.title:SetText(d.name)
  local ent = d.ent
  local bits = { ("Level %d-%d"):format(lo, hi) }
  if ent then bits[#bits + 1] = ("%s  %.1f, %.1f"):format(ns.MapName(ent[1]) or "?", ent[2], ent[3]) end
  if d.forever then bits[#bits + 1] = BLUE .. "WoW Forever|r" end
  local step = J.Step(d.name)
  if step then bits[#bits + 1] = ns.DungeonOn(d.name) and (GREEN .. "In your route|r") or (GREY .. "Not in your route|r") end
  P.sub:SetText(table.concat(bits, GREY .. "    |    |r"))
  local e = ej and ej[d.name]
  P.desc:SetText((e and e.desc and e.desc ~= "") and e.desc or "")
  P.locB:SetShown(ent ~= nil)
  P.routeCB:SetShown(step ~= nil)
  P.readyB:SetShown(step ~= nil and ns.StartPrep ~= nil)
  if step then
    P.routeCB:SetChecked(ns.DungeonOn(d.name))
    P.readyB:SetText((ns.db.prep == d.name) and "Stop getting ready" or "Get ready")
  end
  local nQuests = #(select(1, J.Counts(d, DB().otherFaction)))
  local counts = { quests = nQuests, bosses = #Bosses(d), runs = #ns.RunLog.For(d.name) }
  for _, t in ipairs(P.tabs) do
    t:SetActive(t.key == tab)
    t:SetText(("%s%s  %s(%d)|r"):format(Ico(t.icon, 16), t.title, GREY, counts[t.key] or 0))
  end
  Me()
  for _, cb in ipairs(P.crests) do
    cb:SetShown(tab == "quests")
    local lit = cb.fa == myFaction or DB().otherFaction
    cb.tex:SetDesaturated(not lit); cb.tex:SetAlpha(lit and 1 or 0.45)
  end

  -- left list
  local items = {}
  local bosses = Bosses(d)
  if tab == "quests" then
    local lv = UnitLevel("player")
    for _, it in ipairs(QuestRows(d)) do
      local q, sub = it.q, nil
      if it.s == ST.DONE then sub = "Completed"
      elseif it.s == ST.READY then sub = "Ready to turn in"
      elseif it.s == ST.LOG then
        local have, need = ns.Progress and ns.Progress(it.id)
        sub = "In your quest log" .. ((need and need > 0) and ("  " .. have .. "/" .. need) or "")
      elseif it.s == ST.LOCKED then sub = "Needs earlier quests first"
      elseif (q.r or 0) > lv then sub = "Available from level " .. q.r
      else sub = "Level " .. (q.l or "?") .. "  -  you can pick it up" end
      items[#items + 1] = { key = it.id, text = ST_COLOR[it.s] .. q.n .. "|r", sub = sub, icon = QUEST_ICON[it.s], fa = q.fa or "both" }
    end
  elseif tab == "bosses" then
    local run = ns.RunLog.Current()
    for i, b in ipairs(bosses) do
      local killed = run and run.bosses[b.name]
      items[#items + 1] = { key = i, text = (killed and GREY or WHITE) .. b.name .. "|r", boss = b,
                            sub = killed and "Killed this run" or ((b.drops and "Drops quest items") or nil) }
    end
  else
    for _, run in ipairs(ns.RunLog.For(d.name)) do
      items[#items + 1] = { key = run, text = WHITE .. RunTitle(run) .. "|r", icon = run.done and ICON.done or ICON.clock }
    end
  end
  if selected == nil or (type(selected) ~= type(items[1] and items[1].key)) then selected = items[1] and items[1].key end
  local found = false
  local rh = (tab == "runs") and ROW_H or 44
  for i, it in ipairs(items) do
    local r = Row(i)
    r.key = it.key
    r:SetHeight(rh - 4)
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -(i - 1) * rh)
    r.text:SetText(it.text); r.right:SetText(it.right or "")
    r.sub:SetText(it.sub or ""); r.sub:SetShown(it.sub ~= nil)
    r.text:ClearAllPoints()
    r.text:SetPoint(it.sub and "BOTTOMLEFT" or "LEFT", r.icon, it.sub and "RIGHT" or "RIGHT", 8, it.sub and 1 or 0)
    r.text:SetPoint("RIGHT", -52, 0)
    local size = it.boss and 32 or 20
    r.icon:SetSize(size, size)
    if it.boss then PaintPortrait(r.icon, it.boss); r.icon:Show()
    elseif it.icon then r.icon:SetTexture(it.icon); r.icon:SetTexCoord(0, 1, 0, 1); r.icon:Show()
    else r.icon:Hide() end
    local lvl = it.boss and it.boss.level
    r.badge:SetShown(lvl ~= nil and lvl > 0)
    if lvl and lvl > 0 then r.badge.text:SetText(lvl) end
    r.crestA:SetShown(it.fa == "A" or it.fa == "both")
    r.crestH:SetShown(it.fa == "H" or it.fa == "both")
    r.sel:SetShown(it.key == selected); r.bar:SetShown(it.key == selected)
    if it.key == selected then found = true end
    r:Show()
  end
  for i = #items + 1, #rows do rows[i]:Hide() end
  if not found then selected = items[1] and items[1].key end
  P.list.child:SetSize(LIST_W - 30, #items * rh + 4)
  P.empty:SetShown(#items == 0)
  P.empty:SetText(tab == "runs" and "No runs logged yet. Runs are recorded on their own when you go in." or
    (tab == "quests" and "No quests recorded for this dungeon." or "No bosses recorded."))
  RenderSummary(d)

  -- right page
  local L = P.detail
  L:Reset()
  local top = 0
  if tab == "bosses" and selected then top = ShowModel(d, bosses[selected]) else P.stage:Hide() end
  L.y = -6 - top
  if top > 0 then L.y = L.y - 4 end
  if tab == "quests" and selected then RenderQuestDetail(L, selected)
  elseif tab == "bosses" and selected then RenderBossDetail(L, d, bosses[selected] or {})
  elseif tab == "runs" and selected then RenderRunDetail(L, selected)
  else
    L:Add(P_TITLE .. d.name .. "|r", { font = { "QuestTitleFont", "GameFontNormalLarge" } })
    if e and e.desc and e.desc ~= "" then L:Gap(4); L:Add(e.desc) end
    L:Gap(6)
    L:Add(P_MUTED .. (tab == "runs" and "Every run you do here is recorded on its own: time, XP, bosses, deaths." or "Nothing here yet.") .. "|r")
  end
  P.detailScroll.child:SetSize(W - LIST_W - 70, L:Height())
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
      r = CreateFrame("Button", nil, logsView.scroll.child, BackdropTemplateMixin and "BackdropTemplate" or nil)
      r:SetSize(W - 76, 40)
      Backdrop(r, { 0.07, 0.05, 0.04, 0.9 }, DIM_EDGE)
      r.thumb = r:CreateTexture(nil, "ARTWORK"); r.thumb:SetSize(96, 32); r.thumb:SetPoint("LEFT", 4, 0)
      local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetPoint("TOPLEFT", 3, -3); hl:SetPoint("BOTTOMRIGHT", -3, 3); hl:SetColorTexture(1, 0.85, 0.4, 0.1)
      r.name = r:CreateFontString(nil, "OVERLAY"); Font(r.name, { "GameFontNormal" })
      r.name:SetPoint("TOPLEFT", r.thumb, "TOPRIGHT", 10, -2)
      r.text = r:CreateFontString(nil, "OVERLAY"); Font(r.text, { "GameFontHighlightSmall" })
      r.text:SetPoint("BOTTOMLEFT", r.thumb, "BOTTOMRIGHT", 10, 2)
      r:SetScript("OnClick", function(self) J.OpenDungeon(self.run.d, "runs", self.run) end)
      logRows[n] = r
    end
    r.run = run
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -(n - 1) * 44)
    local d = Dungeon(run.d) or ns.RunLog.Dungeon(run.d)
    if d then PaintArt(r.thumb, d, 0.35, 0.65); r.thumb:Show() else r.thumb:Hide() end
    r.name:SetText((run.d or "?") .. (run.done and ("  " .. Ico(ICON.done, 14)) or ""))
    r.text:SetText(RunTitle(run) .. (run.deaths and run.deaths > 0 and (GREY .. ("   %d death%s"):format(run.deaths, run.deaths == 1 and "" or "s") .. "|r") or ""))
    r:Show()
  end
  for i = n + 1, #logRows do logRows[i]:Hide() end
  logsView.scroll.child:SetSize(W - 76, n * 44 + 4)
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
      if Fold(d.name):find(q, 1, true) then res[#res + 1] = { GOLD .. d.name .. "|r" .. GREY .. "  dungeon|r", d.name, nil, nil, ICON.map } end
      for _, b in ipairs(d.bosses or {}) do
        if Fold(b[1]):find(q, 1, true) then res[#res + 1] = { WHITE .. b[1] .. "|r" .. GREY .. "  boss, " .. d.name .. "|r", d.name, "bosses", b[1], ICON.boss } end
      end
      for _, id in ipairs(d.quests or {}) do
        local qq = Quest(id)
        if qq and ForMe(qq, true) and Fold(qq.n):find(q, 1, true) then
          res[#res + 1] = { WHITE .. qq.n .. "|r" .. GREY .. "  quest, " .. d.name .. "|r", d.name, "quests", id, ICON.start }
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
      b:SetSize(W - 90, 22)
      local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 0.82, 0.3, 0.15)
      b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(16, 16); b.icon:SetPoint("LEFT", 6, 0)
      b.text = b:CreateFontString(nil, "OVERLAY"); Font(b.text, { "GameFontHighlight" })
      b.text:SetPoint("LEFT", b.icon, "RIGHT", 6, 0); b.text:SetJustifyH("LEFT")
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
    b:ClearAllPoints(); b:SetPoint("TOPLEFT", 8, -8 - (i - 1) * 22)
    b.text:SetText(r[1])
    if r[5] and Has(r[5]) then b.icon:SetTexture(r[5]); b.icon:Show() else b.icon:Hide() end
    b:Show()
    if i >= 22 then break end
  end
  for i = math.min(#res, 22) + 1, #resultRows do resultRows[i]:Hide() end
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
  cb:SetPoint("TOPLEFT", 12, y)
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
  probe = f:CreateTexture(nil, "BACKGROUND"); probe:Hide()
  f:SetSize(W, H)
  f:SetFrameStrata("DIALOG")   -- same layer as the settings and Dungeons windows; the last one opened is in front
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  if f.SetClampRectInsets then f:SetClampRectInsets(0, 0, 18, 0) end   -- keep the title plate (above the frame) on screen
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local x, y = self:GetLeft(), self:GetTop()
    if x and y then DB().pos = { x, y } end
  end)
  -- the window: dark stone behind, the dialog border (gold when the client has it)
  if f.SetBackdrop then
    local rock = Has(TEX.rock)
    f:SetBackdrop({ bgFile = rock and TEX.rock or TEX.white, tile = rock, tileSize = rock and 256 or nil,
                    edgeFile = Has(TEX.goldBorder) and TEX.goldBorder or TEX.border,
                    edgeSize = 28, insets = { left = 7, right = 7, top = 7, bottom = 7 } })
    if rock then f:SetBackdropColor(0.55, 0.48, 0.40, 1) else f:SetBackdropColor(0.07, 0.055, 0.04, 0.98) end
  end
  local shade = f:CreateTexture(nil, "BACKGROUND", nil, 2)   -- darken the middle so the pages stand out
  shade:SetPoint("TOPLEFT", 8, -8); shade:SetPoint("BOTTOMRIGHT", -8, 8)
  shade:SetColorTexture(0, 0, 0, 0.35)
  tinsert(UISpecialFrames, "RubberDinghyJournal")
  -- title on the dialog header plate
  local plate = f:CreateTexture(nil, "ARTWORK")
  if Has(TEX.header) then
    plate:SetTexture(TEX.header); plate:SetSize(340, 64); plate:SetPoint("TOP", 0, 14)
  else plate:Hide() end
  local title = f:CreateFontString(nil, "OVERLAY"); Font(title, { "GameFontNormalLarge" })
  title:SetPoint("TOP", 0, Has(TEX.header) and 0 or -14)
  title:SetText("Dungeon Journal")
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -5, -5)

  local okS, sb = pcall(CreateFrame, "EditBox", "RubberDinghyJournalSearch", f, "SearchBoxTemplate")
  if not okS or not sb then sb = CreateFrame("EditBox", "RubberDinghyJournalSearch", f, "InputBoxTemplate") end
  searchBox = sb
  sb:SetSize(250, 22)
  sb:SetPoint("TOPLEFT", 24, -22)
  sb:SetAutoFocus(false)
  if type(sb.Instructions) == "table" then sb.Instructions:SetText("Search dungeons, bosses, quests...") end
  sb:HookScript("OnTextChanged", function(self)
    if view ~= "home" then ShowView("home"); RenderHome() end
    RenderSearch(self:GetText())
  end)
  sb:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)

  -- Home
  homeView = CreateFrame("Frame", nil, f)
  homeView:SetPoint("TOPLEFT", 16, -52); homeView:SetPoint("BOTTOMRIGHT", -16, 16)
  local optB = FlatButton(homeView, "Options", 90, function()
    if optsPanel:IsShown() then optsPanel:Hide() else optsPanel:Show() end
  end, "What the dungeon list shows.")
  optB:SetPoint("TOPRIGHT", -6, -2)
  homeView.hideB = FlatButton(homeView, "Hide Dungeons", 124, function() hideMode = not hideMode; RenderHome() end,
    "Click this, then click dungeons to hide them from the list (or show them again). Click Done hiding when you're finished.")
  homeView.hideB:SetPoint("RIGHT", optB, "LEFT", -6, 0)
  local logsB = FlatButton(homeView, Ico(ICON.clock, 14) .. "Character Logs", 150, function() ShowView("logs"); RenderLogs() end,
    "Every dungeon run this character has done: time, XP, bosses, deaths. Recorded on its own.")
  logsB:SetPoint("RIGHT", homeView.hideB, "LEFT", -6, 0)
  homeView.foreverB = FlatButton(homeView, "Forever only", 112, function() DB().foreverOnly = not DB().foreverOnly or nil; RenderHome() end,
    "Show only the dungeons that are new in WoW Forever (click again for all of them).")
  homeView.foreverB:SetPoint("TOPLEFT", 6, -2)
  local sub = homeView:CreateFontString(nil, "OVERLAY"); Font(sub, { "GameFontHighlightSmall" })
  sub:SetPoint("LEFT", homeView.foreverB, "RIGHT", 12, 0)
  sub:SetText(GREY .. "Click a dungeon for its quests, bosses and runs.|r")
  homeView.scroll = Scroll(homeView)
  homeView.scroll:SetPoint("TOPLEFT", 6, -36); homeView.scroll:SetPoint("BOTTOMRIGHT", -26, 4)
  homeView.empty = homeView:CreateFontString(nil, "OVERLAY"); Font(homeView.empty, { "GameFontHighlight" })
  homeView.empty:SetPoint("CENTER")
  homeView.empty:SetText("Every dungeon is hidden. Click Hide Dungeons to bring them back, or check Options.")
  homeView.results = Panel(homeView)
  homeView.results:SetPoint("TOPLEFT", 6, -36); homeView.results:SetPoint("BOTTOMRIGHT", -6, 4)
  homeView.results:SetFrameLevel(homeView:GetFrameLevel() + 20)
  homeView.results:Hide()
  homeView.results.none = homeView.results:CreateFontString(nil, "OVERLAY"); Font(homeView.results.none, { "GameFontHighlight" })
  homeView.results.none:SetPoint("TOPLEFT", 14, -14)
  homeView.results.none:SetText("No results")

  optsPanel = Panel(f)
  optsPanel:SetSize(340, 150)
  optsPanel:SetPoint("TOPRIGHT", f, "TOPRIGHT", -22, -82)
  optsPanel:SetFrameLevel(f:GetFrameLevel() + 40)
  optsPanel:Hide()
  OptCheck(optsPanel, -10, "Hide dungeons you've outleveled", "hideOutleveled", "Hides a dungeon once your level is above its range.")
  OptCheck(optsPanel, -36, "Hide dungeons with every quest done", "hideAllDone")
  OptCheck(optsPanel, -62, "Hide the green tick on finished dungeons", "hideTick")
  OptCheck(optsPanel, -88, "Show every class's quests", "allClass", "Normally only your own class's quests are listed.")
  OptCheck(optsPanel, -114, "Show the other faction's quests too", "otherFaction")

  -- Dungeon page: an art banner, tabs, the list on the left and a parchment page on the right
  pageView = CreateFrame("Frame", nil, f)
  pageView:SetPoint("TOPLEFT", 16, -52); pageView:SetPoint("BOTTOMRIGHT", -16, 16)
  local P = pageView
  local BANNER_H = 118
  P.banner = CreateFrame("Frame", nil, P, BackdropTemplateMixin and "BackdropTemplate" or nil)
  P.banner:SetPoint("TOPLEFT", 0, 0); P.banner:SetPoint("TOPRIGHT", 0, 0); P.banner:SetHeight(BANNER_H)
  if P.banner.SetBackdrop then
    P.banner:SetBackdrop({ edgeFile = TEX.tipBorder, edgeSize = 14 })
    P.banner:SetBackdropBorderColor(GOLD_EDGE[1], GOLD_EDGE[2], GOLD_EDGE[3], 1)
  end
  P.banner.art = P.banner:CreateTexture(nil, "BACKGROUND")
  P.banner.art:SetPoint("TOPLEFT", 3, -3); P.banner.art:SetPoint("BOTTOMRIGHT", -3, 3)
  local fadeL = P.banner:CreateTexture(nil, "BORDER")      -- dark on the left for the title, clear on the right
  fadeL:SetPoint("TOPLEFT", 3, -3); fadeL:SetPoint("BOTTOMLEFT", 3, 3); fadeL:SetWidth(560)
  Grad(fadeL, "HORIZONTAL", { 0, 0, 0, 0.85 }, { 0, 0, 0, 0 })
  local fadeB = P.banner:CreateTexture(nil, "BORDER")
  fadeB:SetPoint("BOTTOMLEFT", 3, 3); fadeB:SetPoint("BOTTOMRIGHT", -3, 3); fadeB:SetHeight(46)
  Grad(fadeB, "VERTICAL", { 0, 0, 0, 0.7 }, { 0, 0, 0, 0 })
  local back = FlatButton(P.banner, "< All dungeons", 118, function() ShowView("home"); RenderHome() end, nil, 22)
  back:SetPoint("TOPLEFT", 10, -10)
  P.title = P.banner:CreateFontString(nil, "OVERLAY"); Font(P.title, { "QuestTitleFontBlackShadow", "GameFontNormalHuge", "GameFontNormalLarge" })
  P.title:SetTextColor(1, 0.86, 0.4)
  P.title:SetPoint("TOPLEFT", 16, -42)
  P.sub = P.banner:CreateFontString(nil, "OVERLAY"); Font(P.sub, { "GameFontHighlight" })
  P.sub:SetPoint("TOPLEFT", P.title, "BOTTOMLEFT", 0, -6)
  P.desc = P.banner:CreateFontString(nil, "OVERLAY"); Font(P.desc, { "GameFontHighlightSmall" })
  P.desc:SetPoint("TOPLEFT", P.sub, "BOTTOMLEFT", 0, -6); P.desc:SetWidth(520); P.desc:SetJustifyH("LEFT")
  if P.desc.SetMaxLines then P.desc:SetMaxLines(2) end
  -- actions on the right of the banner
  P.locB = FlatButton(P.banner, Ico(ICON.map, 14) .. "Show Location", 150, function()
    local d = Dungeon(cur)
    if d and d.ent then ShowSpot(d.name .. " entrance", d.ent[1], d.ent[2], d.ent[3]) end
  end, "Opens the world map on the dungeon's entrance.")
  P.locB:SetPoint("TOPRIGHT", -12, -12)
  P.readyB = FlatButton(P.banner, "Get ready", 150, function()
    if ns.db.prep == cur then ns.StopPrep() else ns.StartPrep(cur) end
    J.RenderPage()
  end, "A side route that walks every quest chain and picks up every quest this dungeon has for you.")
  P.readyB:SetPoint("TOP", P.locB, "BOTTOM", 0, -6)
  P.routeCB = CreateFrame("CheckButton", nil, P.banner, "UICheckButtonTemplate")
  P.routeCB:SetSize(24, 24)
  P.routeCB:SetPoint("TOPLEFT", P.readyB, "BOTTOMLEFT", 2, -4)
  local rl = (type(P.routeCB.Text) == "table" and P.routeCB.Text) or (type(P.routeCB.text) == "table" and P.routeCB.text) or nil
  if not rl then rl = P.routeCB:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); rl:SetPoint("LEFT", P.routeCB, "RIGHT", 2, 0) end
  rl:SetText("In my route")
  P.routeCB:SetScript("OnClick", function(self)
    if not self:GetChecked() and ns.Tracker and ns.Tracker.ConfirmSkipDungeon then
      self:SetChecked(true); ns.Tracker.ConfirmSkipDungeon(cur)
    else ns.SetDungeon(cur, self:GetChecked() and true or false) end
    J.RenderPage()
  end)
  -- tabs, sitting on top of the pages
  P.tabs = {}
  local tx = 4
  for _, t in ipairs({ { "quests", "Quests", ICON.quests }, { "bosses", "Bosses", ICON.boss }, { "runs", "Runs", ICON.clock } }) do
    local b = Tab(P, t[2], 136, function() tab, selected = t[1], nil; J.RenderPage() end)
    b.key, b.title, b.icon = t[1], t[2], t[3]
    b:SetPoint("TOPLEFT", tx, -(BANNER_H + 8))
    tx = tx + 140
    P.tabs[#P.tabs + 1] = b
  end
  -- faction crests: yours is always on; click the other one to see its quests too
  P.crests = {}
  for i, f in ipairs({ { "H", ICON.horde, "Horde" }, { "A", ICON.alliance, "Alliance" } }) do
    local cb = CreateFrame("Button", nil, P, BackdropTemplateMixin and "BackdropTemplate" or nil)
    cb:SetSize(30, 28)
    Backdrop(cb, { 0.12, 0.09, 0.06, 0.95 }, DIM_EDGE)
    cb:SetPoint("TOPRIGHT", -4 - (i - 1) * 34, -(BANNER_H + 8))
    cb.tex = cb:CreateTexture(nil, "ARTWORK"); cb.tex:SetPoint("TOPLEFT", 4, -4); cb.tex:SetPoint("BOTTOMRIGHT", -4, 4)
    if Has(f[2]) then cb.tex:SetTexture(f[2]); cb.tex:SetTexCoord(CREST_TC[1], CREST_TC[2], CREST_TC[3], CREST_TC[4]) end
    cb.fa = f[1]
    cb:SetScript("OnClick", function(self)
      Me()
      if self.fa ~= myFaction then DB().otherFaction = not DB().otherFaction or nil; selected = nil; J.RenderPage() end
    end)
    cb:SetScript("OnEnter", function(self)
      Me()
      Tip(self, { f[3] .. " quests", self.fa == myFaction and "Your faction's quests are always shown."
        or ("Click to " .. (DB().otherFaction and "hide" or "show") .. " the " .. f[3] .. " quests too.") })
    end)
    cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    P.crests[#P.crests + 1] = cb
  end
  local bodyTop = -(BANNER_H + 36)
  local listBox = Panel(P)
  listBox:SetPoint("TOPLEFT", 0, bodyTop); listBox:SetPoint("BOTTOMLEFT", 0, 0); listBox:SetWidth(LIST_W)
  P.summary = CreateFrame("Frame", nil, listBox, BackdropTemplateMixin and "BackdropTemplate" or nil)
  P.summary:SetPoint("BOTTOMLEFT", 6, 6); P.summary:SetPoint("BOTTOMRIGHT", -6, 6); P.summary:SetHeight(64)
  Backdrop(P.summary, { 0.16, 0.12, 0.06, 0.9 }, DIM_EDGE)
  P.summary.text = P.summary:CreateFontString(nil, "OVERLAY"); Font(P.summary.text, { "GameFontHighlightSmall" })
  P.summary.text:SetPoint("TOPLEFT", 10, -9); P.summary.text:SetPoint("RIGHT", -10, 0); P.summary.text:SetJustifyH("LEFT")
  if P.summary.text.SetSpacing then P.summary.text:SetSpacing(3) end
  P.list = Scroll(listBox)
  P.list:SetPoint("TOPLEFT", 4, -6); P.list:SetPoint("BOTTOMRIGHT", -26, 76)
  P.empty = listBox:CreateFontString(nil, "OVERLAY"); Font(P.empty, { "GameFontHighlightSmall" })
  P.empty:SetPoint("TOPLEFT", 12, -12); P.empty:SetWidth(LIST_W - 24); P.empty:SetJustifyH("LEFT")
  local page = Parchment(P)
  page:SetPoint("TOPLEFT", listBox, "TOPRIGHT", 8, 0); page:SetPoint("BOTTOMRIGHT", 0, 0)
  P.detailScroll = Scroll(page)
  P.detailScroll:SetPoint("TOPLEFT", 10, -10); P.detailScroll:SetPoint("BOTTOMRIGHT", -30, 10)
  P.detail = Lines(P.detailScroll.child, W - LIST_W - 80, true)
  -- the boss model's stage, at the top of the page
  P.stage = CreateFrame("Frame", nil, P.detailScroll.child, BackdropTemplateMixin and "BackdropTemplate" or nil)
  P.stage:SetPoint("TOPLEFT", 8, -6); P.stage:SetSize(W - LIST_W - 96, 184)
  if P.stage.SetBackdrop then P.stage:SetBackdrop({ edgeFile = TEX.tipBorder, edgeSize = 12 }); P.stage:SetBackdropBorderColor(0.42, 0.26, 0.1, 1) end
  P.stage.art = P.stage:CreateTexture(nil, "BACKGROUND")
  P.stage.art:SetPoint("TOPLEFT", 3, -3); P.stage.art:SetPoint("BOTTOMRIGHT", -3, 3)
  local dim = P.stage:CreateTexture(nil, "BORDER"); dim:SetPoint("TOPLEFT", 3, -3); dim:SetPoint("BOTTOMRIGHT", -3, 3); dim:SetColorTexture(0, 0, 0, 0.45)
  local okM, model = pcall(CreateFrame, "PlayerModel", nil, P.stage)
  if okM and model then
    model:SetPoint("TOPLEFT", 4, -4); model:SetPoint("BOTTOMRIGHT", -4, 4)
    P.model = model
  end
  P.stage:Hide()

  -- Character Logs
  logsView = CreateFrame("Frame", nil, f)
  logsView:SetPoint("TOPLEFT", 16, -52); logsView:SetPoint("BOTTOMRIGHT", -16, 16)
  local back2 = FlatButton(logsView, "< All dungeons", 118, function() ShowView("home"); RenderHome() end, nil, 22)
  back2:SetPoint("TOPLEFT", 6, -2)
  local lt = logsView:CreateFontString(nil, "OVERLAY"); Font(lt, { "GameFontNormalLarge" })
  lt:SetPoint("LEFT", back2, "RIGHT", 14, 0)
  lt:SetText(Ico(ICON.clock, 18) .. "Character Logs " .. GREY .. "- click a run for its details|r")
  logsView.scroll = Scroll(logsView)
  logsView.scroll:SetPoint("TOPLEFT", 6, -34); logsView.scroll:SetPoint("BOTTOMRIGHT", -26, 4)
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
  frame:Raise()
  J.Refresh()
end

--- Open the journal on a dungeon (route name or place), optionally on a tab and an item.
function J.OpenDungeon(name, toTab, sel)
  local d = Dungeon(name) or ns.RunLog.Dungeon(name)
  if not d then J.Open(); return end
  if not frame or not frame:IsShown() then J.Open() else frame:Raise() end
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
