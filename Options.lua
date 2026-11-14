-- Rubber Dinghy - settings window (minimap button left-click, /rdr, or Game Menu > Options > AddOns).
-- Built from Blizzard's own frame/checkbox/button templates so it matches Forever's UI.
local ADDON, ns = ...
local O = {}
ns.Options = O

local win, controls = nil, {}
local W, PAD = 360, 16
local COLX = 0   -- x offset of the column being built (the settings window has two)

local function Apply(what)
  if what == "tracker" and ns.Tracker then ns.Tracker.Refresh()
  elseif what == "blizzard" and ns.Tracker then ns.Tracker.SetKeepBlizzard(ns.db.keepBlizzard)
  elseif what == "trackerScale" and ns.Tracker then ns.Tracker.ApplyScale(); ns.Queue()
  elseif what == "map" and ns.Map then ns.Map.Refresh()
  elseif what == "arrow" and ns.Arrow then ns.Arrow.Refresh()
  elseif what == "minimap" and ns.MinimapButton then ns.MinimapButton.Refresh()
  elseif what == "rares" and ns.Rares then ns.Rares.Refresh()
  elseif what == "xpbar" and ns.XP then ns.XP.RefreshBlizzBar()
  elseif what == "route" then ns.Recompute()
  end
end

-- A checkbox bound to a saved setting. invert = the setting stores "off" (e.g. noMap).
local function Check(parent, y, label, tip, key, invert, apply)
  local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  cb:SetPoint("TOPLEFT", PAD + COLX, y)
  cb:SetSize(26, 26)
  local fs = (type(cb.Text) == "table" and cb.Text) or (type(cb.text) == "table" and cb.text) or nil
  if not fs then fs = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); fs:SetPoint("LEFT", cb, "RIGHT", 2, 0) end
  fs:SetText(label)
  cb.label = fs
  cb:SetScript("OnClick", function(self)
    local v = self:GetChecked() and true or false
    if invert then v = not v end
    ns.db[key] = v or nil
    Apply(apply)
  end)
  cb:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(label); GameTooltip:AddLine(tip, 1, 1, 1, true); GameTooltip:Show()
  end)
  cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
  cb.refresh = function()
    local v = ns.db[key] and true or false
    if invert then v = not v end
    cb:SetChecked(v)
  end
  controls[#controls + 1] = cb
  return cb
end

-- A classic horizontal slider (built by hand so it works on every client).
local function Slider(parent, y, label, key, min, max, step, default, fmt, apply)
  local s = CreateFrame("Slider", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  s:SetOrientation("HORIZONTAL")
  s:SetPoint("TOPLEFT", PAD + 6 + COLX, y)
  s:SetSize(W - 2 * PAD - 70, 16)
  if s.SetBackdrop then
    s:SetBackdrop({ bgFile = "Interface\\Buttons\\UI-SliderBar-Background", edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
                    tile = true, tileSize = 8, edgeSize = 8, insets = { left = 3, right = 3, top = 6, bottom = 6 } })
  end
  s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
  s:SetMinMaxValues(min, max)
  s:SetValueStep(step)
  if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
  s.label = s:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  s.label:SetPoint("BOTTOMLEFT", s, "TOPLEFT", 0, 2)
  s.label:SetText(label)
  s.value = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  s.value:SetPoint("LEFT", s, "RIGHT", 8, 0)
  s:SetScript("OnValueChanged", function(self, v)
    v = math.floor(v / step + 0.5) * step
    self.value:SetText(fmt(v))
    if self.loading then return end
    ns.db[key] = (math.abs(v - default) < step / 2) and nil or v
    Apply(apply)
  end)
  s.refresh = function()
    s.loading = true
    s:SetValue(ns.db[key] or default)
    s.value:SetText(fmt(ns.db[key] or default))
    s.loading = false
  end
  controls[#controls + 1] = s
  return s
end

local function Button(parent, text, w, onClick, tip)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w, 22)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  if tip then
    b:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(tip, 1, 1, 1, true); GameTooltip:Show() end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  return b
end

local function Header(parent, y, text)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  fs:SetPoint("TOPLEFT", PAD + COLX, y)
  fs:SetText(text)
  local line = parent:CreateTexture(nil, "ARTWORK")
  line:SetColorTexture(1, 0.82, 0, 0.35)
  line:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -3)
  line:SetSize(W - 2 * PAD, 1)
end

local pct = function(v) return ("%d%%"):format(math.floor(v * 100 + 0.5)) end
local AREA_MODES = { "next", "all", "off" }
local AREA_TEXT = { next = "Quest areas: next stop only", all = "Quest areas: every stop", off = "Quest areas: off" }

local function Build()
  local ok, f = pcall(CreateFrame, "Frame", "RubberDinghyOptions", UIParent, "BasicFrameTemplateWithInset")
  if not ok or not f then f = CreateFrame("Frame", "RubberDinghyOptions", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil) end
  win = f
  f:SetSize(2 * W, 600)
  f:SetPoint("CENTER")
  f:SetFrameStrata("DIALOG")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  local templTitle = (type(f.TitleText) == "table" and f.TitleText) or (type(f.title) == "table" and f.title) or nil
  if f.SetBackdrop and not templTitle then
    f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                    tile = true, tileSize = 32, edgeSize = 24, insets = { left = 6, right = 6, top = 6, bottom = 6 } })
  end
  local title = templTitle or f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  if not templTitle then title:SetPoint("TOP", 0, -8) end
  title:SetText("Rubber Dinghy Rapid Level Guide")
  tinsert(UISpecialFrames, "RubberDinghyOptions") -- Escape closes it

  local icon = f:CreateTexture(nil, "ARTWORK")
  icon:SetTexture("Interface\\AddOns\\" .. ADDON .. "\\media\\icon")
  icon:SetSize(40, 40)
  icon:SetPoint("TOPLEFT", PAD, -32)
  f.stepText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  f.stepText:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -2)
  f.stepText:SetWidth(2 * W - 2 * PAD - 60)   -- full width: long step names stay on one line
  if f.stepText.SetWordWrap then f.stepText:SetWordWrap(false) end
  f.stepText:SetJustifyH("LEFT")
  local prevB = Button(f, "<", 30, function() ns.Step(-1) end, "Previous step")
  prevB:SetPoint("TOPLEFT", icon, "BOTTOMRIGHT", 10, 16)
  local autoB = Button(f, "Automatic", 90, function() ns.Auto() end, "Back to the step the guide picks for you")
  autoB:SetPoint("LEFT", prevB, "RIGHT", 4, 0)
  local nextB = Button(f, ">", 30, function() ns.Step(1) end, "Next step")
  nextB:SetPoint("LEFT", autoB, "RIGHT", 4, 0)
  f.effText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.effText:SetPoint("LEFT", nextB, "RIGHT", 12, 0)
  f.effText:SetWidth(2 * W - 2 * PAD - 230)
  if f.effText.SetWordWrap then f.effText:SetWordWrap(false) end
  f.effText:SetJustifyH("LEFT")

  COLX = 0
  local y = -92
  Header(f, y, "Route"); y = y - 22
  local pickB = Button(f, "Dungeons & get ready...", 180, function() O.ToggleDungeons() end,
    "No dungeons are in the route until you choose them. Tick one to add it (a side route collects its quests first), or click Get ready for that side route alone.")
  pickB:SetPoint("TOPLEFT", PAD + 4, y)
  local journalB = Button(f, "Dungeon Journal", 140, function() if ns.Journal then ns.Journal.Toggle() end end,
    "Every dungeon: where its quests start, its bosses, and a log of your runs (time and XP).")
  journalB:SetPoint("LEFT", pickB, "RIGHT", 8, 0)
  y = y - 32
  f.skipText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.skipText:SetPoint("TOPLEFT", PAD + 4, y - 5)
  local unskipB = Button(f, "Un-skip all", 100, function() ns.UnskipAll(); O.Refresh() end,
    "Brings every quest you skipped (right-click a stop > Skip) back into the route.")
  unskipB:SetPoint("TOPLEFT", PAD + 170, y)
  y = y - 30
  Check(f, y, "Learn quest counts, flights and locations", "Notes each quest's real objective counts, how long flights take, and - for quests no database has a location for (some Forever-only mobs and objects) - where you are when their progress goes up. The route planner then uses real numbers and puts those quests on the map. Only facts about the game - never your pace. Stays on your PC.",
    "noLearn", true, "route"); y = y - 22
  f.learnText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.learnText:SetPoint("TOPLEFT", PAD + 30, y)
  y = y - 22
  Header(f, y, "Tracker"); y = y - 22
  Check(f, y, "Show the route tracker", "The step and its stops, where Blizzard's objective tracker normally sits.", "noTracker", true, "tracker"); y = y - 26
  Check(f, y, "Show quest XP on Blizzard's XP bar", "A light blue stretch on your XP bar for the XP waiting in finished quests, and XP per hour and time to level when you hover the bar.", "noXPOverlay", true, "xpbar"); y = y - 26
  Check(f, y, "Also an XP bar in the tracker", "The same, as a bar at the top of the route tracker.", "trackerXP", false, "tracker"); y = y - 26
  Check(f, y, "Hide Blizzard's objective tracker", "The route tracker replaces it. Untick to get Blizzard's back.", "keepBlizzard", true, "blizzard"); y = y - 40
  Slider(f, y, "Tracker size", "trackerScale", 0.7, 1.5, 0.05, 1, pct, "trackerScale"); y = y - 34

  Header(f, y, "Map"); y = y - 22
  Check(f, y, "Show the route on the map and minimap", "Numbered stops, the route line and quest areas.", "noMap", true, "map"); y = y - 26
  Check(f, y, "Hide Blizzard's quest markers on the map", "While the route is on, its numbered stops replace Blizzard's quest markers.", "keepBlizzMap", true, "map"); y = y - 26
  Check(f, y, "Quest icons like Questie", "Quest givers (!), hand-ins (?), every spawn of the mobs your quests need, and patrol paths of NPCs that walk - for quests that aren't route stops (those keep their gold numbers). Shift-click an icon to hide that quest.", "noOtherPins", true, "map"); y = y - 26
  local unhideB = Button(f, "Show hidden quests again", 170, function()
    ns.db.hiddenQuests = nil
    if ns.Map and ns.Map.MarkDirty then ns.Map.MarkDirty() end
    ns.Print("hidden quest icons are back on the map.")
  end, "Brings back the map icons of every quest you shift-clicked to hide.")
  unhideB:SetPoint("TOPLEFT", PAD + 24, y)
  y = y - 28
  Check(f, y, "Route on the minimap", "The next stops, numbered (stop 1 rides the edge when far away), plus the same quest icons as the world map for quests near you. Blizzard's own minimap quest arrow and areas are hidden while it's on. Questie's minimap icons are Questie's: turn them off in Questie > Icons > Minimap icons.", "noMiniPins", true, "map"); y = y - 30
  local areaB = Button(f, "", 220, function(self)
    local cur = ns.db.areaMode or "next"
    local i = 1
    for k, m in ipairs(AREA_MODES) do if m == cur then i = k end end
    local nxt = AREA_MODES[i % #AREA_MODES + 1]
    ns.db.areaMode = (nxt ~= "next") and nxt or nil
    self:SetText(AREA_TEXT[nxt])
    Apply("map")
  end, "Which stops get a shaded quest area on the map. Click to change.")
  areaB:SetPoint("TOPLEFT", PAD, y)
  areaB.refresh = function() areaB:SetText(AREA_TEXT[ns.db.areaMode or "next"]) end
  controls[#controls + 1] = areaB
  y = y - 40
  Slider(f, y, "Quest area strength", "areaAlpha", 0.05, 0.6, 0.05, 0.2, pct, "map"); y = y - 34

  -- Second column: arrow, rare alerts, minimap button, positions.
  local leftY = y
  COLX, y = W, -92
  Header(f, y, "Arrow"); y = y - 22
  Check(f, y, "Show the arrow to the next stop", "Points at stop 1 with the distance in yards. Never sets a map marker.", "noArrow", true, "arrow"); y = y - 40
  Slider(f, y, "Arrow size", "arrowScale", 0.6, 2, 0.05, 1, pct, "arrow"); y = y - 34

  Header(f, y, "Rare & named mobs"); y = y - 22
  Check(f, y, "Alert me when one is nearby", "Rares, rare elites and named quest targets (\"... slain: 0/1\"). Seen on enemy nameplates, mouseover and your target, so turn enemy nameplates on (V) to spot them sooner.", "noRares", true, "rares"); y = y - 26
  Check(f, y, "Play a sound", "The raid warning sound.", "noRareSound", true, "rares"); y = y - 30
  local testB = Button(f, "Test alert", 110, function() if ns.commands.raretest then ns.commands.raretest() end end,
    "Shows a sample alert and the Target button. Shift + drag the button to move it. Bind a key to it under Key Bindings > Rubber Dinghy.")
  testB:SetPoint("TOPLEFT", PAD + COLX, y)
  y = y - 34

  Header(f, y, "Minimap button"); y = y - 22
  local mm = Check(f, y, "Show the minimap button", "Left-click: this window. Right-click: show or hide the tracker.", "minimapHide", true, "minimap")
  y = y - 30

  -- Automation: the jobs Leatrix Plus does. A job Leatrix still has on is left to it (and says so).
  Header(f, y, "Automation"); y = y - 22
  for _, ft in ipairs((ns.Automation and ns.Automation.FEATURES) or {}) do
    local cb = Check(f, y, ft.label, ft.tip .. " A job Leatrix Plus still does is left to it: turn it off there (/ltp > Automation) and /reload.", ft.db, true)
    local base = cb.refresh
    local fs = cb.label
    cb.refresh = function()
      base()
      if fs and fs.SetText then
        local lea = ns.Automation.Leatrix(ft.key) and not ns.db[ft.db]
        fs:SetText(ft.label .. (lea and "  |cffff8040(Leatrix Plus is doing it)|r" or ""))
      end
    end
    y = y - 24
  end
  y = y - 12

  local moveB = Button(f, "", 150, function() ns.SetMoveMode(not ns.db.unlocked) end,
    "Move the tracker and the arrow: drag them, then click Lock. Shift + drag on the tracker header also works any time.")
  moveB:SetPoint("TOPLEFT", PAD + COLX, y)
  moveB.refresh = function() moveB:SetText(ns.db.unlocked and "Lock positions" or "Move tracker & arrow") end
  controls[#controls + 1] = moveB
  local resetB = Button(f, "Reset positions", 150, function() ns.commands.reset() end,
    "Puts the tracker and arrow back in their default places and sizes.")
  resetB:SetPoint("LEFT", moveB, "RIGHT", 10, 0)

  f:SetHeight(math.max(-leftY, -y) + 42)
  COLX = 0
  f:SetScript("OnShow", function() O.Refresh() end)
  f:Hide()
end

function O.Refresh()
  if not win then return end
  for _, c in ipairs(controls) do if c.refresh then c.refresh() end end
  local n = ns.SkipCount()
  win.skipText:SetText(n > 0 and (n .. (n == 1 and " quest skipped" or " quests skipped")) or "No quests skipped")
  if win.learnText and ns.Learn then win.learnText:SetText(ns.db.noLearn and "Off." or ns.Learn.Summary()) end
  local r = ns.route
  if r and r.step then
    win.stepText:SetText(("|cffffd100Step %d/%d:|r %s (%d-%d)%s"):format(r.idx, #ns.steps, r.step.name,
      r.step.from, r.step.to, r.manual and " |cffff8040manual|r" or ""))
    if win.effText and ns.EfficiencyShort then win.effText:SetText(ns.EfficiencyShort(r.step, UnitLevel("player"))) end
  end
end

function O.Toggle()
  if not win then return end
  if win:IsShown() then win:Hide() else win:Show(); win:Raise() end   -- in front of the journal
end

-- Also list it under Game Menu > Options > AddOns, with a button that opens this window.
local function RegisterBlizzardPanel()
  local panel = CreateFrame("Frame")
  panel.name = "Rubber Dinghy"
  local t = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  t:SetPoint("TOPLEFT", 16, -16)
  t:SetText("Rubber Dinghy Rapid Level Guide")
  local b = Button(panel, "Open settings", 160, function()
    if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
    if win then win:Show() end
  end)
  b:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -12)
  if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
    local cat = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(cat)
  elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
  end
end

ns.inits.Options = function()
  Build()
  ns.Safe("OptionsPanel", RegisterBlizzardPanel)
end
ns.listeners.Options = function() if win and win:IsShown() then O.Refresh() end end
ns.commands.skipdungeons = function()   -- every dungeon out of the route (they're opt-in)
  ns.db.dungeons, ns.db.prep, ns.db.skipDungeons = {}, nil, nil
  ns.Print("no dungeons in the route. Choose them in Dungeons (settings).")
  ns.Recompute()
  O.RefreshDungeons()
end
ns.commands.options = function() O.Toggle() end
ns.commands.settings = ns.commands.options
ns.commands.config = ns.commands.options

-- "Choose dungeons": one tick box per dungeon on the route. The planner's picks start ticked (*),
-- the rest are optional steps placed where they cost least time.
local dwin, dcontrols = nil, {}
local function BuildDungeons()
  local ok, f = pcall(CreateFrame, "Frame", "RubberDinghyDungeons", UIParent, "BasicFrameTemplateWithInset")
  if not ok or not f then f = CreateFrame("Frame", "RubberDinghyDungeons", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil) end
  dwin = f
  local DW = 800
  f:SetSize(DW, 200)
  f:SetFrameStrata("DIALOG")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local x, y = self:GetLeft(), self:GetTop()
    if x and y then ns.db.dungeonsPos = { x, y } end
  end)
  local templTitle = (type(f.TitleText) == "table" and f.TitleText) or nil
  if f.SetBackdrop and not templTitle then
    f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                    tile = true, tileSize = 32, edgeSize = 24, insets = { left = 6, right = 6, top = 6, bottom = 6 } })
  end
  local title = templTitle or f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  if not templTitle then title:SetPoint("TOP", 0, -8) end
  title:SetText("Dungeons")
  tinsert(UISpecialFrames, "RubberDinghyDungeons")
  local help = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  help:SetPoint("TOPLEFT", PAD, -32)
  help:SetWidth(DW - 2 * PAD)
  help:SetJustifyH("LEFT")
  help:SetText("Tick = in your route, at the level shown (* = the planner's pick). Get ready = a route that walks every chain and picks up every quest for that dungeon, from where you are.")
  local y = -64
  local seen, list = {}, {}
  for _, st in ipairs(ns.steps or {}) do
    if st.dungeon and not seen[st.dungeon] then seen[st.dungeon] = true; list[#list + 1] = st end
  end
  table.sort(list, function(a, b) return a.from < b.from end)
  local col = 0
  for _, st in ipairs(list) do
    local name = st.dungeon
    local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", PAD + col * 390, y)
    cb:SetSize(22, 22)
    local fs = (type(cb.Text) == "table" and cb.Text) or (type(cb.text) == "table" and cb.text) or nil
    if not fs then fs = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); fs:SetPoint("LEFT", cb, "RIGHT", 1, 0) end
    fs:SetText(("%s (%d)%s"):format(name, st.from, st.optional and "" or " *"))
    if fs.SetWidth then fs:SetWidth(200); fs:SetJustifyH("LEFT") end
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    cb:SetScript("OnClick", function(self) ns.SetDungeon(name, self:GetChecked() and true or false) end)
    cb:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine(name)
      GameTooltip:AddLine(("At about level %d in the route. %s"):format(st.from, st.optional
        and (("Optional: adds about %d min to your time to 60 (good group), but it's fun and the gear helps."):format(st.cost or 0))
        or "Picked by the planner for the fastest route."), 1, 1, 1, true)
      GameTooltip:Show()
    end)
    cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    cb.refresh = function() cb:SetChecked(ns.DungeonOn(name)) end
    dcontrols[#dcontrols + 1] = cb
    -- "Get ready": route every chain and pick-up for this dungeon (or "Stop" if that's the one running).
    local rb = Button(f, "Get ready", 82, function()
      if ns.db.prep == name then ns.StopPrep() else ns.StartPrep(name) end
      O.RefreshDungeons()
    end, "Plan the quickest route, from where you are, through every quest chain and pick-up for " .. name
      .. ". The tracker follows it until you click Stop (or Back to the route).")
    rb:SetPoint("TOPLEFT", PAD + col * 390 + 222, y)
    rb.refresh = function() rb:SetText(ns.db.prep == name and "Stop" or "Get ready") end
    dcontrols[#dcontrols + 1] = rb
    -- "Journal": this dungeon's page in our Dungeon Journal (quests, bosses, runs)
    local jb = Button(f, "Journal", 66, function() if ns.Journal then ns.Journal.OpenDungeon(name) end end,
      "Open " .. name .. " in the Dungeon Journal: where every quest starts, its bosses and your runs.")
    jb:SetPoint("TOPLEFT", PAD + col * 390 + 306, y)
    col = col + 1
    if col == 2 then col = 0; y = y - 24 end
  end
  if col ~= 0 then y = y - 24 end
  f:SetHeight(-y + 20)
  f:SetScript("OnShow", function() for _, c in ipairs(dcontrols) do c.refresh() end end)
  f:Hide()
end

-- Where it opens: where you last dragged it; else beside the settings window when that's open;
-- else on the left of the screen, clear of the tracker, chat and action bars.
local function PlaceDungeons()
  dwin:ClearAllPoints()
  local p = ns.db.dungeonsPos
  if p then
    dwin:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p[1], p[2])
  elseif win and win:IsShown() then
    -- beside the settings window, on whichever side has room (never on top of it)
    local sw = UIParent:GetWidth() or 1920
    local wr, wl = win:GetRight() or 0, win:GetLeft() or 0
    local dw = dwin:GetWidth() or 660
    if wr + 6 + dw <= sw then dwin:SetPoint("TOPLEFT", win, "TOPRIGHT", 6, 0)
    elseif wl - 6 - dw >= 0 then dwin:SetPoint("TOPRIGHT", win, "TOPLEFT", -6, 0)
    else dwin:SetPoint("TOP", win, "BOTTOM", 0, -6) end
  else
    dwin:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 40, -140)
  end
end

function O.ToggleDungeons()
  if not dwin then BuildDungeons() end
  if dwin:IsShown() then dwin:Hide() else PlaceDungeons(); dwin:Show(); dwin:Raise() end
end
function O.RefreshDungeons()
  if dwin and dwin:IsShown() then for _, c in ipairs(dcontrols) do c.refresh() end end
end
ns.commands.dungeons = function() O.ToggleDungeons() end