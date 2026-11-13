-- Rubber Dinghy - objective tracker. Replaces Blizzard's "All Objectives" tracker in the same spot,
-- drawn with Forever's own tracker art and fonts (checked at runtime, plain fallbacks otherwise).
-- Blizzard's tracker is hidden the way Questie does it on Forever: hook OnShow, defer while in combat,
-- never reparent the protected frame.
local ADDON, ns = ...

local WIDTH = 270
local MAX_DETAILED, MAX_STOPS = 5, 14
local CONTAINER_BG = { "ui-questtracker-tracker-header", "Objective-Header" }
local MODULE_BG = { "ui-questtracker-secondary-objective-header", "Objective-Header" }
local COLLAPSE = { "ui-questtrackerbutton-collapse-all" }
local EXPAND = { "ui-questtrackerbutton-expand-all" }
local CHECK = { "ui-questtracker-tracker-check", "Tracker-Check" }
local POI_RING = { "UI-QuestPoi-QuestNumber" }
local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"

local T = {}
ns.Tracker = T
local frame, header, titleFS, collapseBtn, body, mover
local xpwrap, xpbar
local XP_H = 22
local pool, used = {}, 0
local HEADER_FONT, TITLE_FONT, LINE_FONT, SMALL_FONT

---------------------------------------------------------------------------
-- Blizzard tracker suppression (Questie's Forever approach)
---------------------------------------------------------------------------
local hideBlizz, hooked = false, false
local vis = CreateFrame("Frame")
local function ApplyBlizz()
  local otf = ObjectiveTrackerFrame
  if otf then
    if InCombatLockdown() and (not hideBlizz or otf:IsProtected()) then
      vis:RegisterEvent("PLAYER_REGEN_ENABLED")
      return
    end
    vis:UnregisterEvent("PLAYER_REGEN_ENABLED")
    if hideBlizz then otf:Hide() else otf:Show() end
  else
    local wf = QuestWatchFrame or WatchFrame
    if wf then if hideBlizz then wf:Hide() else wf:Show() end end
  end
end
vis:SetScript("OnEvent", ApplyBlizz)

local function SetBlizzHidden(hide)
  hideBlizz = hide
  if ObjectiveTrackerFrame and not hooked then
    ObjectiveTrackerFrame:HookScript("OnShow", function() if hideBlizz then ApplyBlizz() end end)
    hooked = true
  end
  ApplyBlizz()
end

---------------------------------------------------------------------------
-- Line pool
---------------------------------------------------------------------------
local function NewLine()
  local b = CreateFrame("Button", nil, body)
  b.bg = b:CreateTexture(nil, "BACKGROUND")
  b.bg:SetAllPoints()
  b.badge = CreateFrame("Frame", nil, b)
  b.badge:SetSize(18, 18)
  b.badge.ring = b.badge:CreateTexture(nil, "ARTWORK")
  b.badge.ring:SetAllPoints()
  ns.SetAtlasOr(b.badge.ring, POI_RING, CIRCLE, 0.1, 0.1, 0.1, 0.95)
  b.badge.num = b.badge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  b.badge.num:SetPoint("CENTER")
  b.check = b:CreateTexture(nil, "ARTWORK")
  b.check:SetSize(12, 12)
  b.hasCheck = ns.SetAtlasOr(b.check, CHECK, nil) ~= nil
  b.isRDLine = true
  b.text = b:CreateFontString(nil, "OVERLAY", LINE_FONT)
  b.text:SetJustifyH("LEFT")
  b.text:SetWordWrap(true)
  b:SetScript("OnEnter", function(self)
    if self.stop then
      self.text:SetTextColor(1, 1, 1)
      ns.StopTooltip(self, self.stop)
      GameTooltip:AddLine("Click: show on the map.  Right-click: skip.", 0.4, 0.8, 1)
      GameTooltip:Show()
    elseif self.tip then
      GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:AddLine(self.tip, 1, 1, 1, true); GameTooltip:Show()
    end
  end)
  b:SetScript("OnLeave", function(self)
    GameTooltip:Hide()
    if self.baseColor then self.text:SetTextColor(unpack(self.baseColor)) end
  end)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:SetScript("OnClick", function(self, button)
    if button == "RightButton" and self.stop then T.SkipMenu(self.stop, self); return end
    if self.onClick then self.onClick() elseif self.stop then ns.ShowOnMap(self.stop) end
  end)
  return b
end

local y = 0
local function Add(text, opts)
  opts = opts or {}
  used = used + 1
  local b = pool[used]
  if not b then b = NewLine(); pool[used] = b end
  local indent = opts.indent or 0
  b.stop, b.tip, b.onClick = opts.stop, opts.tip, opts.onClick
  b.text:SetFontObject(opts.font or LINE_FONT)
  b.text:ClearAllPoints()
  -- badge (numbered stop) or check mark in front of the text
  local left = indent
  b.badge:Hide(); b.check:Hide()
  if opts.badge then
    b.badge:ClearAllPoints()
    b.badge:SetPoint("TOPLEFT", b, "TOPLEFT", indent, 1)
    b.badge.num:SetText(opts.badge)
    local cr, cg, cb = 1, 1, 1
    if ns.Map and ns.Map.KindColor and opts.stop then cr, cg, cb = ns.Map.KindColor(opts.stop) end
    b.badge.num:SetTextColor(cr, cg, cb)
    b.badge:Show()
    left = indent + 22
  elseif opts.check and b.hasCheck then
    b.check:ClearAllPoints()
    b.check:SetPoint("TOPLEFT", b, "TOPLEFT", indent, -1)
    b.check:Show()
    left = indent + 14
  end
  b.text:SetPoint("TOPLEFT", b, "TOPLEFT", left, -2)
  b.text:SetWidth(WIDTH - left - 6)
  b.text:SetText(text)
  local c = opts.color or { 1, 1, 1 }
  b.baseColor = c
  b.text:SetTextColor(c[1], c[2], c[3])
  if opts.bg then
    if not ns.SetAtlasOr(b.bg, opts.bg, "Interface\\BUTTONS\\WHITE8X8", 0, 0, 0, 0.45) then end
    b.bg:Show()
  else
    b.bg:Hide()
  end
  local h = math.max(opts.badge and 20 or 14, (b.text:GetStringHeight() or 12) + 4, opts.height or 0)
  b:ClearAllPoints()
  b:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -y)
  b:SetSize(WIDTH, h)
  b:Show()
  y = y + h + (opts.gap or 0)
  return b
end

---------------------------------------------------------------------------
-- Render
---------------------------------------------------------------------------
local GOLD, WHITE, GREY, GREEN = { 1, 0.82, 0 }, { 1, 1, 1 }, { 0.6, 0.6, 0.6 }, { 0.2, 1, 0.2 }

--- The XP bar (fills it in; shows or hides it). Returns the height it takes.
function T.RefreshXP()
  if not xpwrap then return 0 end
  local st = ns.db.trackerXP and ns.XP and ns.XP.State()   -- off by default: it's on Blizzard's bar
  if not st then
    xpwrap:Hide(); xpwrap:SetHeight(0.1)
    return 0
  end
  xpwrap:Show(); xpwrap:SetHeight(XP_H)
  xpbar:SetValue(st.cur / st.max)
  local w = xpbar:GetWidth() or (WIDTH - 8)
  local from = st.cur / st.max
  local to = math.min(1, (st.cur + st.banked) / st.max)
  if to > from then
    xpbar.banked:ClearAllPoints()
    xpbar.banked:SetPoint("TOPLEFT", xpbar, "TOPLEFT", from * w, 0)
    xpbar.banked:SetPoint("BOTTOMLEFT", xpbar, "BOTTOMLEFT", from * w, 0)
    xpbar.banked:SetWidth(math.max(1, (to - from) * w))
    xpbar.banked:Show()
  else
    xpbar.banked:Hide()
  end
  xpwrap.text:SetText(ns.XP.Text(st))
  return XP_H
end
local function TopH() return header:GetHeight() + 4 + ((xpwrap and xpwrap:IsShown()) and (XP_H + 2) or 0) end

local blizzHidden
local function Render(r)
  if not frame or not r or not r.step then return end   -- nothing to show yet (e.g. during start-up)
  used, y = 0, 0
  local db = ns.db
  frame:SetShown(not db.noTracker or db.unlocked)
  -- Blizzard's tracker is hidden only while ours is showing (hide ours: you get Blizzard's back)
  local wantHidden = not db.keepBlizzard and not db.noTracker
  if wantHidden ~= blizzHidden then blizzHidden = wantHidden; SetBlizzHidden(wantHidden) end
  collapseBtn:SetCollapsed(db.collapsed)
  local slots = {} -- where quest item buttons go: {qid=, y=pixels below the tracker top}
  T.RefreshXP()
  local function Slot(qid) slots[#slots + 1] = { qid = qid, y = TopH() + y } end
  if db.collapsed or (db.noTracker and not db.unlocked) then
    for i = 1, #pool do pool[i]:Hide() end
    body:SetHeight(1); frame:SetHeight(header:GetHeight())
    if xpwrap then xpwrap:Hide() end
    if ns.Items then ns.Safe("Items", ns.Items.Place, slots, frame) end
    return
  end
  -- never taller than the screen below the tracker's top
  local maxH = db.maxHeight or 620
  local top = frame:GetTop()
  if top and top > 200 then maxH = math.min(maxH, top - 70) end
  local step = r.step
  local range = step.from == step.to and tostring(step.from) or (step.from .. "-" .. step.to)
  Add(("Step %d/%d: %s (%s)%s"):format(r.idx, #ns.steps, step.name, range, (r.manual and not r.prep) and " - manual" or ""),
    { font = HEADER_FONT, color = GOLD, bg = MODULE_BG, height = 22, gap = 2,
      tip = "Leveling route step. Use < and > in the header to change step, A for automatic." })
  local goTo = (r.inZone or step.dungeon or step.grind) and "" or ("Go to " .. step.name .. ". ")
  Add(goTo .. step.note, { font = SMALL_FONT, color = GREY, gap = 4 })
  if step.prep then
    Add("|cffff8040Back to the route|r - stop getting ready for " .. step.dungeon, { font = SMALL_FONT, gap = 2,
      tip = "Ends the get-ready route and goes back to the leveling route (/rdr prep off).",
      onClick = function() ns.StopPrep() end })
  elseif step.dungeon and ns.DungeonOn(step.dungeon) then
    Add("|cffffd100Get ready for " .. step.dungeon .. "|r - route every chain and pick-up for it", { font = SMALL_FONT, gap = 2,
      tip = "Plans the quickest route, from where you are, to walk every quest chain and pick up every quest "
        .. step.dungeon .. " has for you. It updates as you go (/rdr prep).",
      onClick = function() ns.StartPrep(step.dungeon) end })
  end
  if step.dungeon and not step.prep then
    local on = ns.DungeonOn(step.dungeon)
    Add(on and ("|cff33ff33Doing " .. step.dungeon .. "|r - click to skip it")
        or ("|cffff8040Not in your route|r - click to add " .. step.dungeon), { font = SMALL_FONT, gap = 2,
      tip = "Choose your dungeons here or in /rdr settings. Skipped dungeons and their quests drop out of the route.",
      onClick = function()
        if on then T.ConfirmSkipDungeon(step.dungeon) else ns.SetDungeon(step.dungeon, true) end
      end })
    Add("|cff66ccffOpen " .. step.dungeon .. " in the Dungeon Journal|r", { font = SMALL_FONT, gap = 4,
      tip = "Where every quest for this dungeon starts, its bosses and map (DungeonJournal addon, /dj).",
      onClick = function() ns.OpenJournal(step) end })
  end

  local shown = 0
  local objShown = {}   -- a quest's progress lines appear once, at its first stop
  for i, s in ipairs(r.stops) do
    if shown >= MAX_STOPS or y > maxH then break end
    shown = shown + 1
    local where = s.away and (" (" .. (ns.MapName(s.map) or "elsewhere") .. ")") or ""
    local detailed = i <= MAX_DETAILED
    local title = ns.StopTitle(s) .. ns.C.DIM .. (" %.0f,%.0f"):format(s.x, s.y) .. where .. "|r"
    if not detailed then
      if #s.actions > 1 then
        title = title .. ns.C.DIM .. " - " .. #s.actions .. " quests|r"
      elseif s.actions[1] then
        title = title .. ns.C.DIM .. " - " .. s.actions[1].row.q.n .. "|r"
      end
    end
    if not detailed then
      for _, a in ipairs(s.actions) do if a.kind ~= "get" then Slot(a.row.id) end end
    end
    Add(title, { font = TITLE_FONT, color = GOLD, badge = s.index, stop = s, gap = 1 })
    if detailed then
      for _, a in ipairs(s.actions) do
        if a.kind ~= "get" then Slot(a.row.id) end
        Add(ns.ActionText(a), { indent = 22, stop = s, color = WHITE })
        if (a.kind == "do" or a.kind == "turn" or a.kind == "go" or a.kind == "dungeon") and not objShown[a.row.id] then
          objShown[a.row.id] = true
          for _, o in ipairs(ns.Objectives(a.row.id)) do
            Add(o.text, { indent = 30, font = SMALL_FONT, color = o.done and GREY or WHITE, check = o.done, stop = s })
          end
        end
      end
      y = y + 3
    end
  end
  local more = #r.stops - shown
  if more > 0 then Add(("+%d more stops"):format(more), { font = SMALL_FONT, color = GREY, indent = 22 }) end

  -- Get-ready route: the dungeon's quests it can't reach yet, and why.
  if r.prep and r.stalled and #r.stalled > 0 and y < maxH then
    Add("Not yet:", { font = SMALL_FONT, color = GREY, indent = 4 })
    for _, s in ipairs(r.stalled) do
      if y > maxH then break end
      local q = ns.quests[s.id]
      Add((q and q.n or ("quest " .. s.id)) .. " - " .. s.why, { font = SMALL_FONT, color = GREY, indent = 12 })
    end
  end

  for _, a in ipairs(r.loose) do
    if y > maxH then break end
    local hint = (a.kind == "do") and (ns.C.DIM .. " - no location in the database, see Questie's map icons|r") or ""
    Add(ns.ActionText(a) .. hint, { indent = 22, color = WHITE })
  end
  -- Dungeon step: every quest for this dungeon and where it stands, like the Dungeon Journal shows it
  -- (its pick-up text, notes and required chains are used when the journal addon is loaded).
  if step.dungeon and y < maxH then
    local S = ns.S
    Add("Dungeon quests", { font = TITLE_FONT, color = GOLD, gap = 1 })
    for _, id in ipairs(step.quests) do
      if y > maxH then Add("...", { color = GREY, indent = 8 }); break end
      local q = ns.quests[id]
      local s = q and ns.Status(id, r.level)
      if q and s ~= S.NA then
        local jq = ns.JournalQuest(id, step.dungeon) or {}
        local text, color, check = q.n, WHITE, false
        if s == S.DONE then color, check = GREY, true
        elseif s == S.READY then text, color = "Hand in: " .. q.n .. ((q.t and q.t[1]) and (" - " .. q.t[1]) or ""), GREEN
        elseif s == S.LOG then
          local have, need = ns.Progress(id)
          text = q.n .. (need > 0 and (" " .. have .. "/" .. need) or "")
        elseif s == S.OPEN then
          local where = jq.pickup
          if not where and q.g and q.g[1] then
            if q.g[1] == "(item drop)" then where = "starts from an item that drops in there"
            else
              local zone = q.g[2] and ns.MapName(q.g[2])
              where = q.g[1] .. (zone and (", " .. zone) or "")
            end
          end
          text = "Get: " .. q.n .. (where and (" - " .. where) or "")
        elseif s == S.LOCKED then
          local need = {}
          for _, c in ipairs(jq.chain or {}) do
            if not ns.IsDone(c.id) and #need < 2 then need[#need + 1] = c.name end
          end
          if #need == 0 then
            for _, p in ipairs(q.pg or q.ps or {}) do
              if p > 0 and not ns.IsDone(p) and #need < 2 then need[#need + 1] = (ns.quests[p] and ns.quests[p].n) or ("quest " .. p) end
            end
          end
          text, color = q.n .. (#need > 0 and (" - needs: " .. table.concat(need, ", ")) or " - needs an earlier quest"), GREY
        elseif s == S.SKIP then text, color = q.n .. " - skipped", GREY
        else text, color = q.n .. " - level " .. (q.r or q.l or "?"), GREY end
        Add(text, { indent = 8, font = SMALL_FONT, color = color, check = check, tip = jq.note or jq.objective })
      end
    end
    y = y + 3
  end

  local c, S = r.counts, ns.S
  if not r.prep then Add(("%d to hand in, %d in log, %d to pick up, %d later, %d locked%s"):format(
    c[S.READY], c[S.LOG], c[S.OPEN], c[S.LATER], c[S.LOCKED],
    (c[S.SKIP] or 0) > 0 and (", " .. c[S.SKIP] .. " skipped") or ""), { font = SMALL_FONT, color = GREY, gap = 6 }) end

  -- Quests in the log outside this step: Blizzard's tracker would have shown them.
  local n = #r.other
  if n > 0 then
    Add(("%s Other Quests (%d)"):format(db.otherOpen and "-" or "+", n), {
      font = HEADER_FONT, color = GOLD, bg = MODULE_BG, height = 22, gap = 2,
      tip = "Quests in your log that aren't part of this step. Click to show or hide.",
      onClick = function() db.otherOpen = not db.otherOpen; Render(ns.route) end })
    if db.otherOpen then
      for _, e in ipairs(r.other) do
        if y > maxH then Add("...", { color = GREY }); break end
        Slot(e.id)
        local id = e.id
        local show = function() if ns.ShowQuestOnMap then ns.ShowQuestOnMap(id) end end
        local tip = "Click: show it on the map (Blizzard's marker and area)."
        Add(("[%s] %s"):format(e.level or "?", e.title or "?"), { font = TITLE_FONT, color = GOLD, indent = 4, onClick = show, tip = tip })
        for _, o in ipairs(ns.Objectives(e.id)) do
          Add(o.text, { indent = 14, font = SMALL_FONT, color = o.done and GREY or WHITE, check = o.done, onClick = show, tip = tip })
        end
      end
    end
  end

  for i = used + 1, #pool do pool[i]:Hide() end
  -- Lines are reused on every update: a tooltip or skip menu opened on one must follow (or go).
  local owner = GameTooltip.IsShown and GameTooltip:IsShown() and GameTooltip.GetOwner and GameTooltip:GetOwner()
  if owner and owner.isRDLine then
    if owner:IsShown() and owner.IsMouseOver and owner:IsMouseOver() then
      local fn = owner:GetScript("OnEnter"); if fn then fn(owner) end
    else GameTooltip:Hide() end
  end
  if T.MenuStale then T.MenuStale(r) end
  body:SetHeight(math.max(1, y))
  frame:SetHeight(TopH() + y + 4)
  if ns.Items then ns.Safe("Items", ns.Items.Place, slots, frame) end
end

---------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------
local function SmallButton(text, tip, onClick)
  local b = CreateFrame("Button", nil, header)
  b:SetSize(16, 16)
  local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  fs:SetPoint("CENTER")
  fs:SetText(text)
  b:SetScript("OnClick", onClick)
  b:SetScript("OnEnter", function(self)
    fs:SetTextColor(1, 1, 1)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:AddLine(tip, 1, 1, 1); GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() fs:SetTextColor(1, 0.82, 0); GameTooltip:Hide() end)
  return b
end

local function Anchor()
  frame:ClearAllPoints()
  local p = ns.db.trackerPos
  if p then
    frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    return
  end
  -- Where Blizzard's tracker actually is on screen. (Its anchor point is relative to a Forever
  -- container frame, so copying that point put us half off the left edge.)
  local otf = ObjectiveTrackerFrame
  local left, top = otf and otf.GetLeft and otf:GetLeft(), otf and otf.GetTop and otf:GetTop()
  if left and top then
    local k = (otf:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
    left, top = left * k, top * k
    local sw, sh = UIParent:GetWidth() or 0, UIParent:GetHeight() or 0
    if left >= 0 and top > 100 and left + WIDTH <= sw + 1 and top <= sh + 1 then
      frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
      return
    end
  end
  frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -90, -260)
end

local function Init()
  HEADER_FONT = ns.Font({ "ObjectiveTrackerHeaderFont", "GameFontNormalMed2", "GameFontNormal" })
  TITLE_FONT = ns.Font({ "ObjectiveTrackerLineFont", "GameFontNormalMed1", "GameFontNormal" })
  LINE_FONT = ns.Font({ "ObjectiveFont", "ObjectiveTrackerLineFont", "GameFontHighlightSmall" })
  SMALL_FONT = ns.Font({ "GameFontHighlightSmall", "ObjectiveFont" })
  if ObjectiveTrackerFrame and ObjectiveTrackerFrame.GetWidth then
    local w = ObjectiveTrackerFrame:GetWidth()
    if w and w > 200 and w < 420 then WIDTH = w end
  end

  frame = CreateFrame("Frame", "RubberDinghyTracker", UIParent)
  frame:SetSize(WIDTH, 40)
  frame:SetFrameStrata("LOW")
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  Anchor()

  header = CreateFrame("Frame", nil, frame)
  header:SetPoint("TOPLEFT"); header:SetPoint("TOPRIGHT")
  header:SetHeight(26)
  header:EnableMouse(true)
  header:RegisterForDrag("LeftButton")
  -- Move it: Shift + drag the header any time, or plain drag after /rdr unlock.
  header:SetScript("OnDragStart", function()
    if ns.db.unlocked or IsShiftKeyDown() then frame:StartMoving() end
  end)
  header:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Leveling Route")
    GameTooltip:AddLine("Shift + drag to move. /rdr reset puts it back.", 1, 1, 1)
    GameTooltip:Show()
  end)
  header:SetScript("OnLeave", function() GameTooltip:Hide() end)
  header:SetScript("OnDragStop", function()
    frame:StopMovingOrSizing()
    local p, _, rp, x, yy = frame:GetPoint(1)
    ns.db.trackerPos = { p, rp, x, yy }
    ns.Queue() -- item buttons follow the tracker
  end)
  local hbg = header:CreateTexture(nil, "BACKGROUND")
  hbg:SetAllPoints()
  ns.SetAtlasOr(hbg, CONTAINER_BG, "Interface\\BUTTONS\\WHITE8X8", 0, 0, 0, 0.5)
  titleFS = header:CreateFontString(nil, "OVERLAY", HEADER_FONT)
  titleFS:SetPoint("LEFT", 8, 0)
  titleFS:SetText("Leveling Route")

  collapseBtn = CreateFrame("Button", nil, header)
  collapseBtn:SetSize(16, 16)
  collapseBtn:SetPoint("RIGHT", -6, 0)
  collapseBtn.tex = collapseBtn:CreateTexture(nil, "ARTWORK")
  collapseBtn.tex:SetAllPoints()
  collapseBtn.fs = collapseBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  collapseBtn.fs:SetPoint("CENTER")
  function collapseBtn:SetCollapsed(c)
    local atlas = ns.SetAtlasOr(self.tex, c and EXPAND or COLLAPSE, nil)
    self.fs:SetText(atlas and "" or (c and "+" or "-"))
  end
  collapseBtn:SetScript("OnClick", function()
    ns.db.collapsed = not ns.db.collapsed
    Render(ns.route)
  end)

  local arrowB = SmallButton("^", "Arrow to the next stop on/off", function() ns.commands.arrow() end)
  arrowB:SetPoint("RIGHT", collapseBtn, "LEFT", -4, 0)
  local mapB = SmallButton("M", "Route on the world map and minimap on/off", function() ns.commands.map() end)
  mapB:SetPoint("RIGHT", arrowB, "LEFT", -2, 0)
  local nextB = SmallButton(">", "Next step", function() ns.Step(1) end)
  nextB:SetPoint("RIGHT", mapB, "LEFT", -4, 0)
  local autoB = SmallButton("A", "Back to the automatic step", function() ns.Auto() end)
  autoB:SetPoint("RIGHT", nextB, "LEFT", -2, 0)
  local prevB = SmallButton("<", "Previous step", function() ns.Step(-1) end)
  prevB:SetPoint("RIGHT", autoB, "LEFT", -2, 0)

  -- XP bar under the header: your XP, a lighter part for XP waiting in finished quests, and a line
  -- with XP/hour and time to level (or "hand-ins level you up!").
  xpwrap = CreateFrame("Frame", nil, frame)
  xpwrap:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 4, -2)
  xpwrap:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", -4, -2)
  xpwrap:SetHeight(XP_H)
  xpbar = CreateFrame("StatusBar", nil, xpwrap)
  xpbar:SetPoint("TOPLEFT"); xpbar:SetPoint("TOPRIGHT")
  xpbar:SetHeight(8)
  xpbar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  xpbar:SetStatusBarColor(0.58, 0.0, 0.55)
  xpbar:SetMinMaxValues(0, 1)
  local xbg = xpbar:CreateTexture(nil, "BACKGROUND")
  xbg:SetAllPoints(); xbg:SetColorTexture(0, 0, 0, 0.55)
  xpbar.banked = xpbar:CreateTexture(nil, "ARTWORK", nil, -1)
  xpbar.banked:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
  xpbar.banked:SetVertexColor(0.45, 0.75, 1, 0.55)
  xpbar.banked:SetPoint("TOP"); xpbar.banked:SetPoint("BOTTOM")
  xpwrap.text = xpwrap:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  xpwrap.text:SetPoint("TOPLEFT", xpbar, "BOTTOMLEFT", 0, -2)
  xpwrap.text:SetPoint("RIGHT", xpwrap, "RIGHT", 0, 0)
  xpwrap.text:SetJustifyH("LEFT")
  xpwrap:EnableMouse(true)
  xpwrap:SetScript("OnEnter", function(self)
    local st = ns.XP and ns.XP.State()
    if not st then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine(("Level %d: %d / %d XP"):format(st.level, st.cur, st.max))
    GameTooltip:AddLine(("Waiting in finished quests: %d XP"):format(st.banked), 0.56, 0.84, 1)
    if st.rate then GameTooltip:AddLine(("%d XP an hour over the last 30 minutes"):format(st.rate), 1, 1, 1) end
    GameTooltip:Show()
  end)
  xpwrap:SetScript("OnLeave", function() GameTooltip:Hide() end)

  body = CreateFrame("Frame", nil, frame)
  body:SetPoint("TOPLEFT", xpwrap, "BOTTOMLEFT", -4, -4)
  body:SetSize(WIDTH, 1)

  -- Move mode overlay: a highlighted box over the whole tracker that you drag, with a Lock button.
  mover = CreateFrame("Frame", nil, frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
  mover:SetAllPoints(frame)
  mover:SetFrameLevel(frame:GetFrameLevel() + 50)
  if mover.SetBackdrop then
    mover:SetBackdrop({ bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                        tile = true, tileSize = 8, edgeSize = 12, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    mover:SetBackdropColor(0.1, 0.6, 1, 0.22)
    mover:SetBackdropBorderColor(0.3, 0.8, 1, 1)
  end
  mover.label = mover:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  mover.label:SetPoint("CENTER", 0, 12)
  mover.label:SetText("Leveling Route\n|cffffffffdrag to move|r")
  mover.lock = CreateFrame("Button", nil, mover, "UIPanelButtonTemplate")
  mover.lock:SetSize(90, 22)
  mover.lock:SetPoint("TOP", mover.label, "BOTTOM", 0, -8)
  mover.lock:SetText("Lock")
  mover.lock:SetScript("OnClick", function() ns.SetMoveMode(false) end)
  mover:EnableMouse(true)
  mover:RegisterForDrag("LeftButton")
  mover:SetScript("OnDragStart", function() frame:StartMoving() end)
  mover:SetScript("OnDragStop", function()
    frame:StopMovingOrSizing()
    local p, _, rp, x, yy = frame:GetPoint(1)
    ns.db.trackerPos = { p, rp, x, yy }
    ns.Queue()
  end)
  mover:Hide()
  T.ApplyScale()
  if ns.db.unlocked then T.SetMoveMode(true) end

  blizzHidden = not ns.db.keepBlizzard and not ns.db.noTracker
  if blizzHidden then SetBlizzHidden(true) end
  if Questie and Questie.db and Questie.db.profile and Questie.db.profile.trackerEnabled and not ns.db.toldQuestie then
    ns.db.toldQuestie = true
    ns.Print("Questie's tracker is also on and sits in the same spot. Turn it off in Questie's options "
      .. "(Tracker tab), or move this one with /rdr unlock and drag its header.")
  end
end

ns.inits.Tracker = Init
ns.listeners.Tracker = Render

function T.ApplyScale()
  if frame then frame:SetScale(ns.db.trackerScale or 1) end
end
function T.SetMoveMode(on)
  if not frame then return end
  if on then frame:Show(); mover:Show() else mover:Hide() end
  Render(ns.route)
end
function T.Refresh() Render(ns.route) end

-- Right-click menu on a stop: skip the whole stop, or one quest at it. The route re-plans at once.
local menu
--- "Are you sure?" before a dungeon drops out of the route (Blizzard's own confirmation popup).
function T.ConfirmSkipDungeon(name)
  if not (StaticPopupDialogs and StaticPopup_Show) then ns.SetDungeon(name, false); return end
  StaticPopupDialogs.RUBBERDINGHY_SKIP_DUNGEON = StaticPopupDialogs.RUBBERDINGHY_SKIP_DUNGEON or {
    text = "Skip %s?\n\nIts step and its quests drop out of your route. You can add it back any time in Choose dungeons (/rdr dungeons).",
    button1 = "Skip it",
    button2 = CANCEL or "Cancel",
    OnAccept = function(self, data) ns.SetDungeon(data, false) end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
  }
  StaticPopup_Show("RUBBERDINGHY_SKIP_DUNGEON", name, nil, name)
end

function T.SkipMenu(stop, anchor)
  if not menu then
    menu = CreateFrame("Frame", "RubberDinghySkipMenu", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    menu:SetFrameStrata("DIALOG")
    menu:SetClampedToScreen(true)
    if menu.SetBackdrop then
      menu:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                         tile = true, tileSize = 16, edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
      menu:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    end
    menu.title = menu:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    menu.title:SetPoint("TOPLEFT", 10, -8)
    menu.items = {}
    tinsert(UISpecialFrames, "RubberDinghySkipMenu")
  end
  for _, it in ipairs(menu.items) do it:Hide() end
  menu.title:SetText(stop.index .. ". " .. ns.StopTitle(stop))
  menu.stopKey = stop.map .. ":" .. tostring(stop.name)
  local entries = {}
  if #stop.actions > 1 then
    entries[#entries + 1] = { text = ("Skip this stop (%d quests)"):format(#stop.actions),
                              ids = ns.StopQuestIDs(stop), label = "stop " .. stop.index }
  end
  for _, a in ipairs(stop.actions) do
    entries[#entries + 1] = { text = "Skip: " .. a.row.q.n, ids = { a.row.id }, label = a.row.q.n }
  end
  entries[#entries + 1] = { text = "|cff999999Cancel|r" }
  local y, width = -28, 200
  for i, e in ipairs(entries) do
    local b = menu.items[i]
    if not b then
      b = CreateFrame("Button", nil, menu)
      b:SetHeight(18)
      b.fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      b.fs:SetPoint("LEFT", 4, 0)
      b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
      menu.items[i] = b
    end
    b.fs:SetText(e.text)
    width = math.max(width, (b.fs:GetStringWidth() or 150) + 24)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", 8, y)
    b:SetPoint("RIGHT", -8, 0)
    b:SetScript("OnClick", function()
      menu:Hide()
      if e.ids then ns.Skip(e.ids, e.label) end
    end)
    b:Show()
    y = y - 18
  end
  menu:SetSize(width, -y + 10)
  menu:ClearAllPoints()
  menu:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -6, 0)
  menu:Show()
end
--- After a re-plan: close the skip menu if its stop is gone (its numbers would be wrong).
function T.MenuStale(r)
  if not (menu and menu:IsShown() and menu.stopKey) then return end
  for _, s in ipairs(r.stops or {}) do
    if (s.map .. ":" .. tostring(s.name)) == menu.stopKey then return end
  end
  menu:Hide()
end
function T.SetKeepBlizzard(keep)
  ns.db.keepBlizzard = keep and true or nil
  blizzHidden = not keep and not ns.db.noTracker
  SetBlizzHidden(blizzHidden)
end

ns.commands.tracker = function()
  ns.db.noTracker = not ns.db.noTracker
  Render(ns.route)
  ns.Print("route tracker " .. (ns.db.noTracker and "hidden" or "shown"))
end
ns.commands.blizzard = function()
  T.SetKeepBlizzard(not ns.db.keepBlizzard)
  ns.Print(ns.db.keepBlizzard and "Blizzard's objective tracker is back." or "Blizzard's objective tracker hidden again.")
end
ns.commands.unlock = function() ns.SetMoveMode(true) end
ns.commands.move = function() ns.SetMoveMode(not ns.db.unlocked) end
ns.commands.lock = function() ns.SetMoveMode(false) end
ns.commands.reset = function()
  ns.db.trackerPos, ns.db.arrowPos, ns.db.rarePos = nil, nil, nil
  ns.db.trackerScale, ns.db.arrowScale = nil, nil
  T.ApplyScale()
  Anchor()
  if ns.Arrow then ns.Arrow.Reset() end
  if ns.Rares and ns.Rares.ResetPos then ns.Safe("Rares", ns.Rares.ResetPos) end
  ns.Queue()
  ns.Print("tracker and arrow are back in their default places and sizes.")
end
