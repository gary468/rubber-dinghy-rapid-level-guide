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

local frame, header, titleFS, collapseBtn, body
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
  b.text = b:CreateFontString(nil, "OVERLAY", LINE_FONT)
  b.text:SetJustifyH("LEFT")
  b.text:SetWordWrap(true)
  b:SetScript("OnEnter", function(self)
    if self.stop then
      self.text:SetTextColor(1, 1, 1)
      ns.StopTooltip(self, self.stop)
    elseif self.tip then
      GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:AddLine(self.tip, 1, 1, 1, true); GameTooltip:Show()
    end
  end)
  b:SetScript("OnLeave", function(self)
    GameTooltip:Hide()
    if self.baseColor then self.text:SetTextColor(unpack(self.baseColor)) end
  end)
  b:SetScript("OnClick", function(self)
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

local function Render(r)
  if not frame then return end
  used, y = 0, 0
  local db = ns.db
  frame:SetShown(not db.noTracker)
  collapseBtn:SetCollapsed(db.collapsed)
  local slots = {} -- where quest item buttons go: {qid=, y=pixels below the tracker top}
  local function Slot(qid) slots[#slots + 1] = { qid = qid, y = header:GetHeight() + 4 + y } end
  if db.collapsed or db.noTracker then
    for i = 1, #pool do pool[i]:Hide() end
    body:SetHeight(1); frame:SetHeight(header:GetHeight())
    if ns.Items then ns.Safe("Items", ns.Items.Place, slots, frame) end
    return
  end
  local maxH = db.maxHeight or 620
  local step = r.step
  local range = step.from == step.to and tostring(step.from) or (step.from .. "-" .. step.to)
  Add(("Step %d/%d: %s (%s)%s"):format(r.idx, #ns.steps, step.name, range, r.manual and " - manual" or ""),
    { font = HEADER_FONT, color = GOLD, bg = MODULE_BG, height = 22, gap = 2,
      tip = "Leveling route step. Use < and > in the header to change step, A for automatic." })
  Add((r.inZone and "" or ("Go to " .. step.name .. ". ")) .. step.note, { font = SMALL_FONT, color = GREY, gap = 4 })

  local shown = 0
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
        if a.kind == "do" or a.kind == "turn" or a.kind == "go" then
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

  for _, a in ipairs(r.loose) do
    if y > maxH then break end
    local hint = (a.kind == "do") and (ns.C.DIM .. " - no location in the database, see Questie's map icons|r") or ""
    Add(ns.ActionText(a) .. hint, { indent = 22, color = WHITE })
  end
  local c, S = r.counts, ns.S
  Add(("%d to hand in, %d in log, %d to pick up, %d later, %d locked"):format(
    c[S.READY], c[S.LOG], c[S.OPEN], c[S.LATER], c[S.LOCKED]), { font = SMALL_FONT, color = GREY, gap = 6 })

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
        Add(("[%s] %s"):format(e.level or "?", e.title or "?"), { font = TITLE_FONT, color = GOLD, indent = 4 })
        for _, o in ipairs(ns.Objectives(e.id)) do
          Add(o.text, { indent = 14, font = SMALL_FONT, color = o.done and GREY or WHITE, check = o.done })
        end
      end
    end
  end

  for i = used + 1, #pool do pool[i]:Hide() end
  body:SetHeight(math.max(1, y))
  frame:SetHeight(header:GetHeight() + y + 4)
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
  local otf = ObjectiveTrackerFrame
  local point, rel, relPoint, x, yy
  if otf and otf.GetPoint then point, rel, relPoint, x, yy = otf:GetPoint(1) end
  if point then
    frame:SetPoint(point, rel or UIParent, relPoint or point, x or 0, yy or 0)
  else
    frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -90, -260)
  end
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
  header:SetScript("OnDragStart", function() if ns.db.unlocked then frame:StartMoving() end end)
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

  body = CreateFrame("Frame", nil, frame)
  body:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
  body:SetSize(WIDTH, 1)

  if not ns.db.keepBlizzard then SetBlizzHidden(true) end
  if Questie and Questie.db and Questie.db.profile and Questie.db.profile.trackerEnabled and not ns.db.toldQuestie then
    ns.db.toldQuestie = true
    ns.Print("Questie's tracker is also on and sits in the same spot. Turn it off in Questie's options "
      .. "(Tracker tab), or move this one with /rdr unlock and drag its header.")
  end
end

ns.inits.Tracker = Init
ns.listeners.Tracker = Render

ns.commands.tracker = function()
  ns.db.noTracker = not ns.db.noTracker
  Render(ns.route)
  ns.Print("route tracker " .. (ns.db.noTracker and "hidden" or "shown"))
end
ns.commands.blizzard = function()
  ns.db.keepBlizzard = not ns.db.keepBlizzard
  SetBlizzHidden(not ns.db.keepBlizzard)
  ns.Print(ns.db.keepBlizzard and "Blizzard's objective tracker is back." or "Blizzard's objective tracker hidden again.")
end
ns.commands.unlock = function()
  ns.db.unlocked = not ns.db.unlocked
  ns.Print(ns.db.unlocked and "unlocked - drag the tracker header or the arrow to move them; /rdr unlock again to lock."
    or "locked.")
  if ns.Arrow then ns.Arrow.SetUnlocked(ns.db.unlocked) end
end
ns.commands.reset = function()
  ns.db.trackerPos, ns.db.arrowPos = nil, nil
  Anchor()
  if ns.Arrow then ns.Arrow.Reset() end
  ns.Print("tracker and arrow moved back to their default places.")
end
