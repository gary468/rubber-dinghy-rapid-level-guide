-- Rubber Dinghy - "/rdr report": everything needed to look into a problem, ready to copy into a
-- GitHub issue (an addon can't send anything itself). Gary 23 Nov: "I need a way for people to
-- report issues or bugs, or routing issues".
-- The window shows the report already selected (Ctrl+C copies it) and the link to paste it into.
local ADDON, ns = ...
local R = {}
ns.Report = R

R.URL = "https://github.com/gary468/rubber-dinghy-rapid-level-guide/issues/new/choose"

local function Version()
  local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or rawget(_G, "GetAddOnMetadata")
  local v = get and get(ADDON, "Version")
  if not v or v == "" or v:find("@", 1, true) then v = "dev" end
  return v
end

local function Plain(s)
  return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

local function XY(s)
  local x, y = s.cx or s.x, s.cy or s.y
  if not x or not y then return "?" end
  if x <= 1 and y <= 1 then x, y = x * 100, y * 100 end
  return ("%.1f,%.1f"):format(x, y)
end

-- Your quest log: {id, level, title}, headers left out.
local function LogQuests()
  local out = {}
  if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
    for i = 1, C_QuestLog.GetNumQuestLogEntries() or 0 do
      local info = C_QuestLog.GetInfo(i)
      if info and not info.isHeader and info.questID and info.questID > 0 then
        out[#out + 1] = { id = info.questID, level = info.level, title = info.title }
      end
    end
  elseif GetNumQuestLogEntries and GetQuestLogTitle then
    for i = 1, (GetNumQuestLogEntries()) or 0 do
      local title, level, _, header, _, _, _, id = GetQuestLogTitle(i)
      if not header and id then out[#out + 1] = { id = id, level = level, title = title } end
    end
  end
  return out
end

local STATUS_NAME
local function StatusName(s)
  if not STATUS_NAME then
    STATUS_NAME = {}
    for k, v in pairs(ns.S or {}) do STATUS_NAME[v] = k:lower() end
  end
  return STATUS_NAME[s] or tostring(s)
end

--- The report as plain text (what the window shows).
function R.Text()
  local L = {}
  local function add(s) L[#L + 1] = s end
  local level = UnitLevel and UnitLevel("player") or 0
  local _, race = UnitRace and UnitRace("player")
  local _, class = UnitClass and UnitClass("player")
  local faction = UnitFactionGroup and UnitFactionGroup("player")
  local build = GetBuildInfo and select(2, GetBuildInfo())
  add("```")
  add(("Rubber Dinghy %s | game build %s | %s"):format(Version(), tostring(build or "?"), date and date("%Y-%m-%d %H:%M") or ""))
  add(("Level %s %s %s %s"):format(level, faction or "?", race or "?", class or "?"))
  local m, x, y = ns.PlayerPos and ns.PlayerPos()
  local mapName = m and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(m)
  add(("Where: %s (map %s) at %s"):format(mapName and mapName.name or "?", tostring(m or "?"),
    x and ("%.1f,%.1f"):format(x, y) or "?"))
  local r = ns.route or {}
  local st = r.step
  if st then
    add(("Step: %s (%s-%s)%s"):format(Plain(st.name), tostring(st.from or "?"), tostring(st.to or "?"),
      r.manual and " - picked by hand" or " - automatic"))
  else
    add("Step: none")
  end
  local stops = r.stops or {}
  add(("Next stops (%d):"):format(#stops))
  for i = 1, math.min(#stops, 8) do
    local s = stops[i]
    local acts = {}
    for _, a in ipairs(s.actions or {}) do
      local ok, t = pcall(ns.ActionText, a)
      acts[#acts + 1] = Plain(ok and t or (a.row and a.row.q and a.row.q.n)) .. (a.row and a.row.id and (" #" .. a.row.id) or "")
    end
    add(("  %d. %s @ %s - %s"):format(i, Plain(ns.StopTitle and ns.StopTitle(s) or s.name), XY(s), table.concat(acts, "; ")))
  end
  local log = LogQuests()
  add(("Quest log (%d):"):format(#log))
  for _, q in ipairs(log) do
    local s = ns.Status and ns.Status(q.id, level)
    add(("  #%d [%s] %s - %s"):format(q.id, tostring(q.level or "?"), Plain(q.title), StatusName(s)))
  end
  local db = ns.db or {}
  local skipped = 0
  for _ in pairs(db.skip or {}) do skipped = skipped + 1 end
  local A = ns.Automation
  add(("Settings: skipped %d | route quests only %s | auto quests %s%s | dungeons %s"):format(skipped,
    db.routeQuestsOnly and "on" or "off", (A and A.On and A.On("quests")) and "on" or "off",
    (A and A.Leatrix and A.Leatrix("quests")) and " (Leatrix Plus does it)" or "",
    db.skipDungeons and "all off" or "chosen"))
  local errs = {}
  for name, err in pairs(ns.errors or {}) do errs[#errs + 1] = "  " .. name .. ": " .. Plain(err) end
  if #errs > 0 then
    add("Errors:")
    table.sort(errs)
    for _, e in ipairs(errs) do add(e) end
  else
    add("Errors: none")
  end
  add("```")
  return table.concat(L, "\n")
end

local frame
local function ReadOnly(box, get)
  box:SetScript("OnTextChanged", function(self, user)
    if user then self:SetText(get()); self:HighlightText() end
  end)
  box:SetScript("OnEscapePressed", function() frame:Hide() end)
  box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
end

local function Build()
  local f = CreateFrame("Frame", "RubberDinghyReport", UIParent, "BackdropTemplate")
  f:SetSize(600, 460)
  f:SetPoint("CENTER")
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  if f.SetBackdrop then
    f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                    tile = true, tileSize = 32, edgeSize = 24, insets = { left = 6, right = 6, top = 6, bottom = 6 } })
  end
  tinsert(UISpecialFrames, "RubberDinghyReport")   -- Escape closes it

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", 0, -16)
  title:SetText("Report a problem")
  local help = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  help:SetPoint("TOPLEFT", 22, -42)
  help:SetWidth(556)
  help:SetJustifyH("LEFT")
  help:SetText("1. Press Ctrl+C - the report below is already selected.\n"
    .. "2. Open the link at the bottom in your browser, pick Route problem or Bug, and paste it in.\n"
    .. "3. Say what went wrong, and add a screenshot of the map and tracker if you can.")

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -4, -4)

  local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
  sf:SetPoint("TOPLEFT", 22, -100)
  sf:SetPoint("BOTTOMRIGHT", -40, 74)
  local eb = CreateFrame("EditBox", nil, sf)
  eb:SetMultiLine(true)
  eb:SetAutoFocus(false)
  eb:SetFontObject(ChatFontNormal)
  eb:SetWidth(530)
  sf:SetScrollChild(eb)
  ReadOnly(eb, function() return f.text or "" end)
  f.box = eb

  local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  label:SetPoint("BOTTOMLEFT", 22, 50)
  label:SetText("Paste it here (click the link, Ctrl+C, then paste it in your browser):")
  local url = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  url:SetSize(540, 22)
  url:SetPoint("BOTTOMLEFT", 28, 22)
  url:SetAutoFocus(false)
  url:SetText(R.URL)
  ReadOnly(url, function() return R.URL end)
  f.url = url
  return f
end

--- Open the report window with a fresh report, selected for copying.
function R.Show()
  frame = frame or Build()
  frame.text = R.Text()
  frame.box:SetText(frame.text)
  frame.url:SetText(R.URL)
  frame:Show()
  frame.box:SetFocus()
  frame.box:HighlightText()
end

ns.commands.report = function() ns.Safe("Report", R.Show) end
ns.commands.bug = ns.commands.report
