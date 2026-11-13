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

local function Enabled() return ns.db and not ns.db.noRares and not ns.disabled end
local function InCombat() return InCombatLockdown and InCombatLockdown() end

---------------------------------------------------------------------------
-- Which mobs count: rares, rare elites, world bosses, and named quest targets
-- (a mob whose name is in a "0/1" kill objective of a quest in your log, e.g. "Lord Shalzaru slain: 0/1").
---------------------------------------------------------------------------
local questTargets, questDirty = {}, true
local function QuestTarget(name)
  if questDirty then
    wipe(questTargets)
    for _, q in ipairs(ns.QuestLog()) do
      local objs = (C_QuestLog and C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(q.id)) or ns.Objectives(q.id)
      for _, o in ipairs(objs or {}) do
        -- "0/1 Lord Shalzaru slain" (modern) or "Lord Shalzaru slain: 0/1" (classic)
        local need = o.numRequired or (o.text and tonumber(o.text:match("%d+%s*/%s*(%d+)")))
        local done = o.finished or o.done
        if o.text and not done and need == 1 and (o.type == nil or o.type == "monster") then
          questTargets[#questTargets + 1] = o.text
        end
      end
    end
    questDirty = false
  end
  for _, text in ipairs(questTargets) do
    if text:find(name, 1, true) then return true end
  end
  return false
end

local KIND = { rare = "Rare", rareelite = "Rare elite", worldboss = "Boss" }
function R.Classify(unit)
  if not UnitExists(unit) or UnitIsPlayer(unit) or UnitIsDead(unit) then return end
  if UnitCanAttack and not UnitCanAttack("player", unit) then return end
  local kind = KIND[UnitClassification(unit) or ""]
  if kind then return kind end
  local name = UnitName(unit)
  if name and QuestTarget(name) then return "Quest target" end
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
  local kind = R.Classify(unit)
  if not kind then return end
  local name, guid = UnitName(unit), UnitGUID(unit)
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
  if not info or not info.name or not info.objectGUID then return end
  if not (info.objectGUID:match("^Creature") or info.objectGUID:match("^Vehicle")) then return end -- not treasure
  local now = GetTime()
  if seen[info.name] and now - seen[info.name] < REALERT then return end
  seen[info.name] = now
  Alert(info.name, "Rare")
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
  elseif event == "QUEST_LOG_UPDATE" then questDirty = true
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
                       "QUEST_LOG_UPDATE", "PLAYER_REGEN_ENABLED", "VIGNETTE_MINIMAP_UPDATED" }) do
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
