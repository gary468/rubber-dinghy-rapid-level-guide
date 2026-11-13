-- Rubber Dinghy - quest item buttons beside the tracker (like Questie's): click to use the item the
-- quest needs (e.g. an Ultra-Shrinker on giants). Secure action buttons, so - exactly as Questie does -
-- they live on UIParent, are only created/moved/changed out of combat, and changes made during combat
-- wait for it to end.
local ADDON, ns = ...
local Items = {}
ns.Items = Items

local SIZE, MAX_BUTTONS = 24, 10
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local pool = {}
local pendingSlots, pendingTracker, waiting

local function Count(id)
  if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(id, nil, true) or 0 end
  if GetItemCount then return GetItemCount(id, nil, true) or 0 end
  return 0
end
local function Icon(id)
  if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(id) end
  if GetItemIcon then return GetItemIcon(id) end
end
local function Usable(id)
  if C_Item and C_Item.GetItemSpell then return C_Item.GetItemSpell(id) ~= nil end
  if GetItemSpell then return GetItemSpell(id) ~= nil end
  return false
end
local function Cooldown(id)
  local f = (C_Container and C_Container.GetItemCooldown) or (C_Item and C_Item.GetItemCooldown) or GetItemCooldown
  if not f then return nil end
  local start, duration, enabled = f(id)
  return start, duration, (enabled == 1 or enabled == true)
end

--- The item to show for a quest in the log, or nil. Blizzard's own quest item first, then the
--- database candidates that are in your bags and have a "Use:" effect.
function Items.ForQuest(qid)
  local idx = ns.LogIndex(qid)
  if idx == 0 then return nil end
  if GetQuestLogSpecialItemInfo then
    local link = GetQuestLogSpecialItemInfo(idx)
    local native = link and tonumber(link:match("item:(%d+)"))
    if native and Count(native) > 0 then return native end
  end
  local q = ns.quests[qid]
  if q and q.it then
    for _, id in ipairs(q.it) do
      if Count(id) > 0 and Usable(id) then return id end
    end
  end
  return nil
end

local function UpdateButtonState(b)
  local n = Count(b.itemId)
  b.count:SetText(n > 1 and n or "")
  local start, duration, enabled = Cooldown(b.itemId)
  if start and enabled and duration and duration > 0 then b.cd:SetCooldown(start, duration); b.cd:Show() else b.cd:Hide() end
end

local function NewButton(i)
  local b = CreateFrame("Button", "RubberDinghyItem" .. i, UIParent, "SecureActionButtonTemplate")
  b:SetSize(SIZE, SIZE)
  b:SetFrameStrata("MEDIUM")
  b:RegisterForClicks("AnyUp", "AnyDown")
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetAllPoints()
  b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
  b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
  b.cd:SetAllPoints()
  b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
  b.count:SetPoint("BOTTOMRIGHT", -1, 1)
  b:SetScript("OnEnter", function(self)
    if not self.itemId then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetHyperlink("item:" .. self.itemId)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:Hide()
  return b
end

local retried = false
local function Apply()
  local slots, tracker = pendingSlots or {}, pendingTracker
  local left, top = tracker and tracker:IsShown() and tracker:GetLeft(), tracker and tracker:GetTop()
  -- Right after login the tracker may not have a screen position yet: try again shortly.
  if tracker and tracker:IsShown() and (not left or not top) and not retried then
    retried = true
    C_Timer.After(0.5, function() retried = false; if not InCombatLockdown() then ns.Safe("Items", Apply) end end)
    return
  end
  local n = 0
  local lastY, dx = nil, 0
  if left and top then
    local seen = {}
    for _, slot in ipairs(slots) do
      if n >= MAX_BUTTONS then break end
      local id = not seen[slot.qid] and Items.ForQuest(slot.qid)
      seen[slot.qid] = true
      if id then
        n = n + 1
        local b = pool[n] or NewButton(n)
        pool[n] = b
        b.itemId = id
        b:SetAttribute("type1", "item")
        b:SetAttribute("item1", "item:" .. id)
        b.icon:SetTexture(Icon(id) or QUESTION)
        UpdateButtonState(b)
        b:ClearAllPoints()
        -- Left of the tracker, level with the quest's line; two items on one line sit side by side.
        -- Anchored to UIParent, not the tracker, so the tracker itself never becomes protected.
        if slot.y == lastY then dx = dx + SIZE + 2 else dx = 0 end
        lastY = slot.y
        -- The tracker may be scaled; convert its coordinates to UIParent's.
        local k = (tracker:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
        b:SetSize(SIZE * k, SIZE * k)
        -- Tracker docked at the left edge: put the buttons on its right instead (no room on the left).
        local right = tracker:GetRight()
        if left * k < (SIZE + 6) * k * 2 and right then
          b:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", right * k + 4 + dx * k, (top - slot.y) * k)
        else
          b:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", left * k - 4 - dx * k, (top - slot.y) * k)
        end
        b:Show()
      end
    end
  end
  for i = n + 1, #pool do
    local b = pool[i]
    b:Hide()
    b:SetAttribute("item1", nil)
    b.itemId = nil
  end
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_REGEN_ENABLED" then
    ev:UnregisterEvent("PLAYER_REGEN_ENABLED")
    waiting = false
    ns.Safe("Items", Apply)
  elseif event == "BAG_UPDATE_COOLDOWN" then
    for _, b in ipairs(pool) do if b.itemId and b:IsShown() then UpdateButtonState(b) end end
  elseif event == "BAG_UPDATE_DELAYED" or event == "BAG_UPDATE" then
    if ns.db and not ns.disabled then ns.Queue() end -- an item may have appeared or run out
  end
end)
ev:RegisterEvent("BAG_UPDATE_COOLDOWN")
ev:RegisterEvent("BAG_UPDATE_DELAYED")

--- Called by the tracker after every render with {qid=, y=} (y = pixels below the tracker's top).
function Items.Place(slots, tracker)
  pendingSlots, pendingTracker = slots, tracker
  if InCombatLockdown() then
    if not waiting then waiting = true; ev:RegisterEvent("PLAYER_REGEN_ENABLED") end
    return
  end
  Apply()
end
