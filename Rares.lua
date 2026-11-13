-- Rubber Dinghy - rare and named mob alerts.
-- When a rare (or rare elite) or a named quest target comes into view, you get:
--   * a raid-warning style alert and a sound,
--   * a skull on the mob (raid target 8),
--   * a "Target" button (also bindable: Key Bindings > Rubber Dinghy) that targets it in one press.
-- Blizzard doesn't let addons target a mob by themselves: targeting needs a click or key press, which
-- is why the button exists (RareScanner works the same way).
-- Seen via enemy nameplates, mouseover, your target, and minimap vignettes where the client has them.
local ADDON, ns = ...
local R = {}
ns.Rares = R

local SKULL = 8
local REALERT = 300           -- seconds before the same mob alerts again
local SHOW_FOR = 60           -- seconds the Target button stays up
local BUTTON = "RubberDinghyRareButton"

BINDING_HEADER_RUBBERDINGHY = "Rubber Dinghy"
_G["BINDING_NAME_CLICK " .. BUTTON .. ":LeftButton"] = "Target the rare / named mob"

local seen = {}               -- guid or name -> time last alerted
local current                 -- { name=, kind=, at= }
local pending                 -- alert waiting for combat to end before the button can change
local btn

-- Off inside dungeons and raids: there "slain: 0/1" targets are bosses, and the skull would fight the
-- tank's marks (with a raid-warning sound on every pull).
local function InInstance()
  if not IsInInstance then return false end
  local inside, kind = IsInInstance()
  return inside and (kind == "party" or kind == "raid")
end
local function Enabled() return ns.db and not ns.db.noRares and not ns.disabled and not InInstance() end
local function InCombat() return InCombatLockdown and InCombatLockdown() end

---------------------------------------------------------------------------
-- Which mobs count: rares (QuestieDB's rare / rare-elite mobs) and named quest targets (a mob with
-- 1-3 spawns that a quest in your log needs killed, e.g. Lord Shalzaru). Matched by the NPC ID in
-- the unit's GUID: this client can hide a unit's name and classification from addons ("secret
-- values"), but not its GUID - the same way RareScanner does it.
---------------------------------------------------------------------------
local function Secret(v) return issecretvalue and v ~= nil and issecretvalue(v) end

local function NpcId(unit)
  local guid = UnitGUID(unit)
  if not guid or Secret(guid) then return nil end
  local kind, _, _, _, _, id = strsplit("-", guid)
  if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
  return tonumber(id), guid
end

local KIND = { rare = "Rare", rareelite = "Rare elite", worldboss = "Boss" }
--- kind, name, guid for a unit worth an alert (or nil)
function R.Classify(unit)
  if not UnitExists(unit) then return end
  local dead = UnitIsDead(unit)
  if dead and not Secret(dead) then return end
  local id, guid = NpcId(unit)
  if not id then return end
  local hostile = UnitCanAttack and UnitCanAttack("player", unit)
  if hostile == false then return end            -- friendly (a "rare" NPC you talk to)
  local name = UnitName(unit)
  if not name or Secret(name) or name == UNKNOWNOBJECT then name = nil end
  if ns.rareNpcs and ns.rareNpcs[id] then return "Rare", name or ns.rareNpcs[id], guid end
  local named = ns.namedNpcs and ns.namedNpcs[id]
  if named then
    for _, qid in ipairs(named[2] or {}) do
      if ns.LogIndex(qid) > 0 and not ns.IsReady(qid) then return "Quest target", name or named[1], guid end
    end
  end
  -- not in our lists: fall back to the game's classification when it isn't hidden
  local cls = UnitClassification(unit)
  if cls and not Secret(cls) and KIND[cls] then
    local hostile = UnitCanAttack and UnitCanAttack("player", unit)
    if hostile == nil or Secret(hostile) or hostile then return KIND[cls], name or "Rare", guid end
  end
end
---------------------------------------------------------------------------
-- The Target button (secure: can only change outside combat)
---------------------------------------------------------------------------
local function SavePos()
  local x, y = btn:GetCenter()
  local s, ux, uy = btn:GetEffectiveScale(), UIParent:GetCenter()
  local us = UIParent:GetEffectiveScale()
  ns.db.rarePos = { x * s / us - ux, y * s / us - uy }
end

local function Place()
  btn:ClearAllPoints()
  local p = ns.db.rarePos
  if p then btn:SetPoint("CENTER", UIParent, "CENTER", p[1], p[2])
  else btn:SetPoint("TOP", UIParent, "TOP", 0, -190) end
end

local function Build()
  btn = CreateFrame("Button", BUTTON, UIParent, "SecureActionButtonTemplate" .. (BackdropTemplateMixin and ",BackdropTemplate" or ""))
  btn:SetSize(250, 46)
  btn:SetFrameStrata("HIGH")
  btn:SetClampedToScreen(true)
  btn:RegisterForClicks("AnyUp", "AnyDown") -- key bindings fire on key down on this client
  btn:SetAttribute("type", "macro")
  if btn.SetBackdrop then
    btn:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                      tile = true, tileSize = 16, edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    btn:SetBackdropColor(0.05, 0.05, 0.08, 0.92)
    btn:SetBackdropBorderColor(1, 0.82, 0, 1)
  end
  btn.icon = btn:CreateTexture(nil, "ARTWORK")
  btn.icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")
  btn.icon:SetSize(30, 30)
  btn.icon:SetPoint("LEFT", 8, 0)
  btn.title = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  btn.title:SetPoint("TOPLEFT", btn.icon, "TOPRIGHT", 8, -1)
  btn.title:SetPoint("RIGHT", -24, 0)
  btn.title:SetJustifyH("LEFT")
  btn.sub = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  btn.sub:SetPoint("BOTTOMLEFT", btn.icon, "BOTTOMRIGHT", 8, 1)
  btn.sub:SetPoint("RIGHT", -24, 0)
  btn.sub:SetJustifyH("LEFT")
  btn.hl = btn:CreateTexture(nil, "HIGHLIGHT")
  btn.hl:SetAllPoints()
  btn.hl:SetColorTexture(1, 0.82, 0, 0.12)

  -- Close: a plain child button (works out of combat; in combat the button hides when combat ends).
  local close = CreateFrame("Button", nil, btn, "UIPanelCloseButton")
  close:SetSize(22, 22)
  close:SetPoint("TOPRIGHT", 0, 0)
  close:SetScript("OnClick", function() R.Hide() end)

  -- Shift + drag to move it.
  btn:SetMovable(true)
  btn:RegisterForDrag("LeftButton")
  btn:SetScript("OnDragStart", function(self) if IsShiftKeyDown() and not InCombat() then self:StartMoving() end end)
  btn:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SavePos() end)
  btn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("Rubber Dinghy - rare / named mob")
    GameTooltip:AddLine("Click (or your key binding) to target it.", 1, 1, 1, true)
    GameTooltip:AddLine("Bind a key: Key Bindings > Rubber Dinghy.", 0.7, 0.7, 0.7, true)
    GameTooltip:AddLine("Shift + drag to move.", 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
  end)
  btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  Place()
  btn:Hide()
end

local function ShowButton(a)
  if not btn then return end
  if InCombat() then pending = a; return end
  pending = nil
  btn:SetAttribute("macrotext", "/cleartarget\n/targetexact " .. a.name)
  btn.title:SetText("Target: " .. a.name)
  local key = GetBindingKey and GetBindingKey("CLICK " .. BUTTON .. ":LeftButton")
  btn.sub:SetText(a.kind .. (key and (" - press " .. key) or " - click to target"))
  btn:Show()
end

function R.Hide()
  current = nil
  if not btn then return end
  if InCombat() then pending = "hide"; return end
  pending = nil
  btn:Hide()
end

---------------------------------------------------------------------------
-- Alerts
---------------------------------------------------------------------------
local function Mark(unit)
  if ns.db.noRareSkull or not unit or not SetRaidTarget then return end
  if GetRaidTargetIndex and GetRaidTargetIndex(unit) == SKULL then return end -- setting it again would clear it
  pcall(SetRaidTarget, unit, SKULL)
end

local function Alert(name, kind)
  current = { name = name, kind = kind, at = GetTime() }
  local text = ("%s: %s"):format(kind, name)
  if not ns.db.noRareSound and PlaySound then
    pcall(PlaySound, (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959, "Master")
  end
  if RaidNotice_AddMessage and RaidWarningFrame then
    pcall(RaidNotice_AddMessage, RaidWarningFrame, "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8:0|t " .. text,
      (ChatTypeInfo and ChatTypeInfo.RAID_WARNING) or { r = 1, g = 0.3, b = 0.1 })
  end
  if FlashClientIcon then pcall(FlashClientIcon) end
  ns.Print(text .. " nearby - click the Target button to target it.")
  ShowButton(current)
end

function R.CheckUnit(unit)
  if not Enabled() then return end
  local kind, name, guid = R.Classify(unit)
  if not kind then return end
  Mark(unit)
  local key = guid or name
  local now = GetTime()
  if seen[key] and now - seen[key] < REALERT then return end
  -- A vignette may already have alerted this mob by name.
  if seen[name] and now - seen[name] < REALERT and current and current.name == name then seen[key] = now; return end
  seen[key], seen[name] = now, now
  Alert(name, kind)
end

local function CheckVignette(id)
  if not Enabled() or not (C_VignetteInfo and C_VignetteInfo.GetVignetteInfo) then return end
  local info = C_VignetteInfo.GetVignetteInfo(id)
  if not info or not info.objectGUID or Secret(info.objectGUID) then return end
  if not (info.objectGUID:match("^Creature") or info.objectGUID:match("^Vehicle")) then return end -- not treasure
  if not info.name or Secret(info.name) then
    local _, _, _, _, _, nid = strsplit("-", info.objectGUID)
    info = { name = ns.rareNpcs and ns.rareNpcs[tonumber(nid)] or "Rare", objectGUID = info.objectGUID }
  end
  local now = GetTime()
  if seen[info.name] and now - seen[info.name] < REALERT then return end
  seen[info.name] = now
  Alert(info.name, "Rare")
end

--- "Reset positions": the Target button back to its default spot.
function R.ResetPos()
  if btn and not InCombat() then Place() end
end

function R.Refresh()
  if not Enabled() then R.Hide() end
end

-- /rdr raretest shows a sample alert so you can see it and move the button.
function R.Test()
  local name = UnitExists("target") and UnitName("target") or "Lord Shalzaru"
  Alert(name, "Test")
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event, arg1, arg2)
  if event == "NAME_PLATE_UNIT_ADDED" then R.CheckUnit(arg1)
  elseif event == "UPDATE_MOUSEOVER_UNIT" then R.CheckUnit("mouseover")
  elseif event == "PLAYER_TARGET_CHANGED" then R.CheckUnit("target")
  elseif event == "VIGNETTE_MINIMAP_UPDATED" then if arg2 then CheckVignette(arg1) end
  elseif event == "VIGNETTES_UPDATED" then
    -- every rare marker the game knows about right now (throttled)
    local now = GetTime()
    if not R.lastVig or now - R.lastVig > 5 then
      R.lastVig = now
      if C_VignetteInfo and C_VignetteInfo.GetVignettes then
        for _, vid in ipairs(C_VignetteInfo.GetVignettes() or {}) do
          local info = C_VignetteInfo.GetVignetteInfo(vid)
          if info and (info.onMinimap or info.onWorldMap) then CheckVignette(vid) end
        end
      end
    end
  elseif event == "PLAYER_REGEN_ENABLED" then
    if pending == "hide" then R.Hide() elseif pending then ShowButton(pending) end
  end
end)

local ticker = 0
ev:SetScript("OnUpdate", function(_, dt)
  ticker = ticker + dt
  if ticker < 1 then return end
  ticker = 0
  if btn and btn:IsShown() and current and GetTime() - current.at > SHOW_FOR then R.Hide() end
end)

ns.inits.Rares = function()
  Build()
  for _, e in ipairs({ "NAME_PLATE_UNIT_ADDED", "UPDATE_MOUSEOVER_UNIT", "PLAYER_TARGET_CHANGED",
                       "QUEST_LOG_UPDATE", "PLAYER_REGEN_ENABLED", "VIGNETTE_MINIMAP_UPDATED", "VIGNETTES_UPDATED" }) do
    pcall(ev.RegisterEvent, ev, e) -- not every client has every event
  end
end

ns.commands.rares = function()
  ns.db.noRares = not ns.db.noRares or nil
  R.Refresh()
  ns.Print("rare and named mob alerts " .. (ns.db.noRares and "off" or "on"))
end
ns.commands.raretest = function()
  if not Enabled() then ns.Print("rare alerts are off (/rdr rares turns them on)."); return end
  R.Test()
end
