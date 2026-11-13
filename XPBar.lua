-- Rubber Dinghy - XP numbers for the tracker's XP bar:
--   * XP waiting in finished quests (hand them in: is it a level?);
--   * XP per hour over the last 30 minutes of this session, and the time to your next level.
local ADDON, ns = ...
local X = {}
ns.XP = X

local WINDOW = 1800          -- XP/hour over the last 30 minutes
local samples = {}           -- { t = GetTime(), total = XP gained this session }
local total, lastXP, lastMax, lastLevel = 0, nil, nil, nil

local function OnXP()
  local cur, max, lvl = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
  if lastXP then
    if lvl > lastLevel then total = total + (lastMax - lastXP) + cur   -- levelled: rest of the old level + new
    elseif cur > lastXP then total = total + (cur - lastXP) end
  end
  lastXP, lastMax, lastLevel = cur, max, lvl
  local now = GetTime()
  samples[#samples + 1] = { t = now, total = total }
  while #samples > 2 and samples[2].t < now - WINDOW do table.remove(samples, 1) end
end

--- XP per hour (nil until there's a few minutes of play to go on).
function X.Rate()
  local first, last = samples[1], samples[#samples]
  if not first or not last then return nil end
  local now = GetTime()
  local span = now - first.t
  if span < 180 or last.total - first.total <= 0 then return nil end
  return (last.total - first.total) / span * 3600
end

--- XP from quests in your log that are finished (ready to hand in).
function X.Banked()
  local sum = 0
  for _, e in ipairs(ns.QuestLog()) do
    if ns.IsReady(e.id) then
      local xp
      if GetQuestLogRewardXP then
        local ok, v = pcall(GetQuestLogRewardXP, e.id); if ok then xp = v end
      end
      if (not xp or xp == 0) and C_QuestLog and C_QuestLog.GetQuestLogRewardXP then
        local ok, v = pcall(C_QuestLog.GetQuestLogRewardXP, e.id); if ok then xp = v end
      end
      sum = sum + (tonumber(xp) or 0)
    end
  end
  return sum
end

--- Everything the bar shows: cur, max, banked, rate, seconds to level, dings (hand-ins level you up).
function X.State()
  local lvl = UnitLevel("player") or 1
  local maxLevel = (GetMaxPlayerLevel and GetMaxPlayerLevel()) or 60
  if lvl >= maxLevel then return nil end
  local cur, max = UnitXP("player") or 0, UnitXPMax("player") or 1
  if max <= 0 then return nil end
  local banked = X.Banked()
  local rate = X.Rate()
  local left = max - cur
  return { level = lvl, cur = cur, max = max, banked = banked, rate = rate,
           secs = rate and (left / rate * 3600) or nil, dings = banked >= left }
end

local function Short(n)
  if n >= 1000 then return ("%.0fk"):format(n / 1000) end
  return tostring(math.floor(n))
end
local function Dur(s)
  if s >= 3600 then return ("%dh %02dm"):format(math.floor(s / 3600), math.floor(s % 3600 / 60)) end
  return ("%dm"):format(math.max(1, math.floor(s / 60)))
end

--- "45% (+18% to hand in) - 52k XP/h - 1h 10m to 51"
function X.Text(st)
  local parts = { ("%d%%"):format(math.floor(st.cur / st.max * 100)) }
  if st.banked > 0 then
    parts[1] = parts[1] .. (" |cff8fd6ff(+%d%% to hand in)|r"):format(math.floor(st.banked / st.max * 100 + 0.5))
  end
  if st.dings then
    parts[#parts + 1] = "|cff33ff33hand-ins level you up!|r"
  elseif st.rate then
    parts[#parts + 1] = Short(st.rate) .. " XP/h"
    parts[#parts + 1] = Dur(st.secs) .. " to " .. (st.level + 1)
  end
  return table.concat(parts, "  -  ")
end

---------------------------------------------------------------------------
-- Blizzard's own XP bar: a light blue stretch from your XP to where your finished quests take you,
-- and our lines in its tooltip. Works with the classic bar (MainMenuExpBar) and the newer status
-- tracking bars (StatusTrackingBarManager / MainStatusTrackingBarContainer).
---------------------------------------------------------------------------
local blizzBar, overlay, hooked

local function FindBlizzBar()
  if MainMenuExpBar and MainMenuExpBar.GetMinMaxValues then return MainMenuExpBar end
  for _, holder in ipairs({ _G.MainStatusTrackingBarContainer, _G.StatusTrackingBarManager }) do
    if holder and type(holder.bars) == "table" then
      for _, b in pairs(holder.bars) do
        -- the experience bar is the one with the rested-XP fill
        if type(b) == "table" and b.StatusBar and (b.ExhaustionLevelFillBar or b.ExhaustionTick) then return b.StatusBar end
      end
    end
  end
  return nil
end

function X.RefreshBlizzBar()
  if ns.db and ns.db.noXPOverlay then if overlay then overlay:Hide() end; return end
  blizzBar = blizzBar or FindBlizzBar()
  if not blizzBar then return end
  if not overlay then
    overlay = blizzBar:CreateTexture(nil, "ARTWORK", nil, 7)
    overlay:SetTexture("Interface\\Buttons\\WHITE8X8")
    overlay:SetVertexColor(0.45, 0.8, 1, 0.45)
  end
  if not hooked then
    hooked = true
    if blizzBar.HookScript then
      blizzBar:HookScript("OnSizeChanged", function() ns.Safe("XP", X.RefreshBlizzBar) end)
      -- add our lines to Blizzard's tooltip for the bar (the bar or its parent shows it)
      local tipFrame = (blizzBar:GetScript("OnEnter") and blizzBar) or blizzBar:GetParent() or blizzBar
      if tipFrame and tipFrame.HookScript then
        tipFrame:HookScript("OnEnter", function()
          local st = X.State()
          if not st or ns.db.noXPOverlay then return end
          if not GameTooltip:IsShown() then GameTooltip:SetOwner(tipFrame, "ANCHOR_TOP") end
          GameTooltip:AddLine(" ")
          GameTooltip:AddLine("Rubber Dinghy", 0.4, 0.8, 1)
          GameTooltip:AddLine(("Waiting in finished quests: %d XP (+%d%%)"):format(st.banked, math.floor(st.banked / st.max * 100 + 0.5)), 0.56, 0.84, 1)
          if st.dings then GameTooltip:AddLine("Your hand-ins level you up!", 0.2, 1, 0.2)
          elseif st.rate then
            GameTooltip:AddLine(("%d XP an hour (last 30 min) - next level in about %d min"):format(st.rate, math.floor(st.secs / 60)), 1, 1, 1)
          end
          GameTooltip:Show()
        end)
      end
    end
  end
  local st = X.State()
  local w = blizzBar:GetWidth()
  if not st or not w or w == 0 or st.banked <= 0 then overlay:Hide(); return end
  local from = st.cur / st.max
  local to = math.min(1, (st.cur + st.banked) / st.max)
  overlay:ClearAllPoints()
  overlay:SetPoint("TOPLEFT", blizzBar, "TOPLEFT", from * w, 0)
  overlay:SetPoint("BOTTOMLEFT", blizzBar, "BOTTOMLEFT", from * w, 0)
  overlay:SetWidth(math.max(1, (to - from) * w))
  overlay:Show()
end

local pendingBar = false
local function QueueBar()
  if pendingBar then return end
  pendingBar = true
  C_Timer.After(0.5, function() pendingBar = false; ns.Safe("XP", X.RefreshBlizzBar) end)
end

local f = CreateFrame("Frame")
f:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_XP_UPDATE" or event == "PLAYER_LEVEL_UP" then ns.Safe("XP", OnXP) end
  if ns.Tracker and ns.Tracker.RefreshXP then ns.Safe("Tracker", ns.Tracker.RefreshXP) end
  QueueBar()
end)
ns.inits.XP = function()
  for _, e in ipairs({ "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "QUEST_LOG_UPDATE", "UPDATE_EXHAUSTION" }) do
    pcall(f.RegisterEvent, f, e)
  end
  OnXP()
  QueueBar()
end
