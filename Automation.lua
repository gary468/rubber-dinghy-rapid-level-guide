-- Rubber Dinghy - automation, the same jobs Leatrix Plus does, so it can do them instead:
--   quests   accept, hand in (when there's no choice of reward) and pick them from a quest giver's list
--   gossip   skip the chat of vendors, flight masters, trainers, bankers... (any NPC: hold Alt)
--   summon   accept a summon after 10 seconds (Shift cancels)     res      accept a resurrection
--   pvp      release in battlegrounds                              junk     sell grey items
--   repair   repair all, from guild funds when you're allowed       loot     faster auto loot
-- Each one is a tick box in settings (all on by default). Hold Shift at an NPC or vendor to do it
-- yourself. A job Leatrix Plus still has switched on is left to Leatrix (two addons pressing the
-- same buttons fight), and the settings say so, so you can turn it off there and /reload.
--
-- Built to never lock you in place: every handler is a few cheap calls (no route or quest-log
-- scans), and a quest giver's quest is picked at most once per visit, so a quest the game won't
-- give you can't loop the chat window.
local ADDON, ns = ...
local A = {}
ns.Automation = A

-- key, saved "off" setting, Leatrix Plus setting, label, tooltip
A.FEATURES = {
  { key = "quests", db = "noAutoQuests", lea = "AutomateQuests", label = "Accept and hand in quests",
    tip = "Accepts quests, hands in finished ones (when there's a choice of reward the pick is yours) and picks them from a quest giver's list. Never a quest you skipped, or one that costs gold or reagents. Hold Shift to do it yourself." },
  { key = "gossip", db = "noAutoGossip", lea = "AutomateGossip", label = "Skip gossip",
    tip = "Vendors, flight masters, trainers, bankers and stable masters with a single chat option open straight away. Any other NPC: hold Alt as you talk to them. Hold Shift to stop it." },
  { key = "summon", db = "noAutoSummon", lea = "AutoAcceptSummon", label = "Accept summons",
    tip = "Accepts a summon after 10 seconds (out of combat). Hold Shift as it fires, or decline it, to stay." },
  { key = "res", db = "noAutoRes", lea = "AutoAcceptRes", label = "Accept resurrection",
    tip = "Accepts a resurrection, unless the player casting it is in combat." },
  { key = "pvp", db = "noAutoPvP", lea = "AutoReleasePvP", label = "Release in battlegrounds",
    tip = "Releases your spirit when you die in a battleground. Hold Shift to stay." },
  { key = "junk", db = "noAutoJunk", lea = "AutoSellJunk", label = "Sell junk",
    tip = "Sells grey items when you open a vendor, and says what they fetched. Hold Shift to skip." },
  { key = "repair", db = "noAutoRepair", lea = "AutoRepairGear", label = "Repair",
    tip = "Repairs everything at a vendor who can, from guild funds when you're allowed (else your own gold). Hold Shift to skip." },
  { key = "loot", db = "noAutoLoot", lea = "FasterLooting", label = "Faster auto loot",
    tip = "Takes everything the moment the loot window opens (with auto loot on, or the auto-loot key held)." },
}
local BY_KEY = {}
for _, f in ipairs(A.FEATURES) do BY_KEY[f.key] = f end

--- Leatrix Plus has this job switched on (read from its saved settings: they're live at login).
function A.Leatrix(key)
  local f = BY_KEY[key]
  local lea = rawget(_G, "LeaPlusDB")
  return f and type(lea) == "table" and lea[f.lea] == "On" or false
end

--- This job is ours right now.
function A.On(key)
  local db = ns.db
  if not db or ns.disabled then return false end
  local f = BY_KEY[key]
  return f and not db[f.db] and not A.Leatrix(key) or false
end

local function Shift() return IsShiftKeyDown and IsShiftKeyDown() end

-- NPC ID of the NPC you're talking to (nil when the game hides it from addons).
local function NpcId()
  local g = UnitGUID and UnitGUID("npc")
  if not g or (issecretvalue and issecretvalue(g)) or (canaccessvalue and not canaccessvalue(g)) then return nil end
  local _, _, _, _, _, id = strsplit("-", g)
  return tonumber(id), g
end

---------------------------------------------------------------------------
-- Quests (ported from Leatrix Plus "Automate quests", with its safety checks)
---------------------------------------------------------------------------
-- NPCs whose quests have consequences (heirloom curators, reputation trade-ins...): leave alone.
local BLOCKED = { [15192] = true, [6566] = true, [45400] = true, [6294] = true, [55402] = true }
-- ...and ones whose quests you only pick yourself (reputation turn-ins that eat items).
local BLOCKED_SELECT = { [12944] = true, [10307] = true }

local function Blocked(action)
  local id = NpcId()
  if not id then return false end
  return BLOCKED[id] or (action == "select" and BLOCKED_SELECT[id]) or false
end

local function Skipped(id)
  return id and id ~= 0 and ns.db and ns.db.skip and ns.db.skip[id] or false
end

local function LogFull()
  local max = (C_QuestLog and C_QuestLog.GetMaxNumQuestsCanAccept and C_QuestLog.GetMaxNumQuestsCanAccept()) or 20
  local n
  if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
    local _, quests = C_QuestLog.GetNumQuestLogEntries(); n = quests
  elseif GetNumQuestLogEntries then
    local _, quests = GetNumQuestLogEntries(); n = quests
  end
  return n and n >= max or false
end

local function NeedsGold()
  local g = GetQuestMoneyToGet and GetQuestMoneyToGet()
  return g and g > 0 or false
end

-- The hand-in asks for currency or a crafting reagent: yours to decide.
local function NeedsReagents()
  for i = 1, 6 do
    local item = _G["QuestProgressItem" .. i]
    if item and item:IsShown() and item.type == "required" then
      if item.objectType == "currency" then return true end
      if item.objectType == "item" and GetQuestItemInfo and C_Item and C_Item.GetItemInfo then
        local _, _, _, _, _, itemID = GetQuestItemInfo("required", i)
        if itemID then
          local reagent = select(17, C_Item.GetItemInfo(itemID))
          if reagent then return true end
        end
      end
    end
  end
  return false
end

-- Quests picked from this NPC's list during this visit: each at most once, so a quest the game
-- refuses (log full, requirements) can't bounce the window back and forth.
local visit = { guid = nil, t = 0, picked = {} }
local function Visit()
  local _, g = NpcId()
  local now = GetTime()
  if g ~= visit.guid or now - visit.t > 30 then visit.guid, visit.picked = g, {} end
  visit.t = now
  return visit.picked
end

local function OnDetail()
  local id = GetQuestID and GetQuestID()
  if Skipped(id) or Blocked("accept") then return end
  if QuestGetAutoAccept and QuestGetAutoAccept() then
    CloseQuest()        -- the game already accepted it
  elseif not LogFull() then
    AcceptQuest()
  end
end

local function OnAcceptConfirm()
  -- an escort or shared quest someone started: join in
  if ConfirmAcceptQuest then ConfirmAcceptQuest() end
  if StaticPopup_Hide then StaticPopup_Hide("QUEST_ACCEPT") end
end

local function OnProgress()
  local id = GetQuestID and GetQuestID()
  if Skipped(id) or Blocked("complete") then return end
  if IsQuestCompletable and IsQuestCompletable() and not NeedsGold() and not NeedsReagents() then CompleteQuest() end
end

local function OnComplete()
  local id = GetQuestID and GetQuestID()
  if Skipped(id) or Blocked("complete") or NeedsGold() or NeedsReagents() then return end
  local choices = GetNumQuestChoices and GetNumQuestChoices() or 0
  if choices <= 1 then GetQuestReward(choices) end   -- a real choice of rewards: yours to make
end

local function OnAutoComplete(questID)
  if not (C_QuestLog and C_QuestLog.GetLogIndexForQuestID and ShowQuestComplete) then return end
  local index = C_QuestLog.GetLogIndexForQuestID(questID)
  local info = index and C_QuestLog.GetInfo and C_QuestLog.GetInfo(index)
  if info and info.isAutoComplete then
    if C_QuestLog.SetSelectedQuest then C_QuestLog.SetSelectedQuest(questID) end
    ShowQuestComplete(questID)
  end
end

-- A chat option in colour or "<...>" is a special choice (skip ahead, start an event): hands off.
local function SpecialOption()
  local opts = C_GossipInfo and C_GossipInfo.GetOptions and C_GossipInfo.GetOptions() or {}
  for _, o in ipairs(opts) do
    local t = o.name
    if t and (t:upper():find("|C", 1, true) or t:find("<", 1, true)) then return true end
  end
  return false
end

local function OnGossipQuests()
  if not (UnitExists("npc") or (QuestFrameGreetingPanel and QuestFrameGreetingPanel:IsShown())) then return end
  if SpecialOption() or Blocked("select") then return end
  local G, picked = C_GossipInfo, Visit()
  for _, q in ipairs(G.GetActiveQuests and G.GetActiveQuests() or {}) do
    if q.isComplete and q.questID and not picked[q.questID] and not Skipped(q.questID) then
      picked[q.questID] = true
      return G.SelectActiveQuest(q.questID)
    end
  end
  if LogFull() then return end
  for _, q in ipairs(G.GetAvailableQuests and G.GetAvailableQuests() or {}) do
    if q.questID and not picked[q.questID] and not Skipped(q.questID) then
      picked[q.questID] = true
      return G.SelectAvailableQuest(q.questID)
    end
  end
end

-- The older quest list (titles only).
local function OnGreeting()
  if Blocked("select") then return end
  local picked = Visit()
  for i = 1, (GetNumActiveQuests and GetNumActiveQuests() or 0) do
    local title, complete = GetActiveTitle(i)
    if title and complete and not picked["a" .. title] then
      picked["a" .. title] = true
      return SelectActiveQuest(i)
    end
  end
  if LogFull() then return end
  for i = 1, (GetNumAvailableQuests and GetNumAvailableQuests() or 0) do
    local title = GetAvailableTitle(i)
    if title and not picked["o" .. title] then
      picked["o" .. title] = true
      return SelectAvailableQuest(i)
    end
  end
end

---------------------------------------------------------------------------
-- Gossip
---------------------------------------------------------------------------
local service
local function IsService(id)
  if not service then
    service = {}
    for n in tostring(ns.serviceNpcs or ""):gmatch("%d+") do service[tonumber(n)] = true end
  end
  return id and service[id] or false
end

local function OnGossipSkip()
  local G = C_GossipInfo
  if not (G and G.GetOptions) then return end
  local opts = G.GetOptions() or {}
  if #opts ~= 1 or (G.GetNumAvailableQuests and G.GetNumAvailableQuests() or 0) > 0
    or (G.GetNumActiveQuests and G.GetNumActiveQuests() or 0) > 0 then return end
  if not (IsAltKeyDown() or IsService(NpcId())) then return end
  local o = opts[1]
  if o.gossipOptionID and G.SelectOption then
    G.SelectOption(o.gossipOptionID)
  elseif GossipFrame and GossipFrame:IsShown() and GossipFrame.SelectGossipOption then
    GossipFrame:SelectGossipOption(1)
  end
end

---------------------------------------------------------------------------
-- Summon, resurrection, battleground release
---------------------------------------------------------------------------
local function OnSummon()
  if UnitAffectingCombat("player") or not C_SummonInfo then return end
  local who, where = C_SummonInfo.GetSummonConfirmSummoner(), C_SummonInfo.GetSummonConfirmAreaName()
  if not who then return end
  ns.Print(("accepting the summon from %s (%s) in 10 seconds - hold Shift or decline it to stay."):format(who, where or "?"))
  C_Timer.After(10, function()
    if not A.On("summon") or Shift() then return end
    if C_SummonInfo.GetSummonConfirmSummoner() == who and C_SummonInfo.GetSummonConfirmAreaName() == where then
      C_SummonInfo.ConfirmSummon()
      if StaticPopup_Hide then StaticPopup_Hide("CONFIRM_SUMMON") end
    end
  end)
end

local function OnResurrect(caster)
  if caster and UnitAffectingCombat(caster) then return end
  AcceptResurrect()
  if StaticPopup_Hide then
    StaticPopup_Hide("RESURRECT"); StaticPopup_Hide("RESURRECT_NO_SICKNESS"); StaticPopup_Hide("RESURRECT_NO_TIMER")
  end
end

local function ReleaseInPvP(which)
  if which ~= "DEATH" or not A.On("pvp") then return end
  if C_DeathInfo and C_DeathInfo.GetSelfResurrectOptions then
    local o = C_DeathInfo.GetSelfResurrectOptions()
    if o and #o > 0 then return end   -- a soulstone or similar: your call
  end
  local inInstance, kind = IsInInstance()
  if not (inInstance and kind == "pvp") then return end
  C_Timer.After(0.2, function()
    local dialog = StaticPopup_Visible and StaticPopup_Visible("DEATH")
    if not dialog then return end
    if Shift() then ns.Print("automatic release cancelled."); return end
    StaticPopup_OnClick(_G[dialog], 1)
  end)
end

---------------------------------------------------------------------------
-- Vendor: sell junk, repair
---------------------------------------------------------------------------
local sellTicker, sold, earned, passes
local SELL_PASSES = 8
local function StopSelling()
  if sellTicker then sellTicker:Cancel(); sellTicker = nil end
  if earned and earned > 0 then
    local coins = (C_CurrencyInfo and C_CurrencyInfo.GetCoinText and C_CurrencyInfo.GetCoinText(earned)) or GetCoinTextureString(earned)
    ns.Print("sold junk for " .. coins .. ".")
  end
  earned = nil
end

local function SellPass()
  if not (MerchantFrame and MerchantFrame:IsShown()) then StopSelling(); return end
  local n = 0
  for bag = 0, 4 do
    for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.quality == 0 and not info.hasNoValue and not info.isLocked and info.hyperlink then
        local price = select(11, C_Item.GetItemInfo(info.hyperlink))
        if price and price > 0 then
          local k = bag * 100 + slot
          if not sold[k] then sold[k] = true; earned = earned + price * (info.stackCount or 1) end
          C_Container.UseContainerItem(bag, slot)
          n = n + 1
        end
      end
    end
  end
  passes = passes + 1
  if n == 0 or passes >= SELL_PASSES then StopSelling() end
end

local function SellJunk()
  StopSelling()
  sold, earned, passes = {}, 0, 0
  SellPass()
  if earned and C_Timer.NewTicker then sellTicker = C_Timer.NewTicker(0.3, SellPass, SELL_PASSES) end
end

local function Repair()
  if not (CanMerchantRepair and CanMerchantRepair()) then return end
  local cost, can = GetRepairAllCost()
  if not can or not cost or cost <= 0 then return end
  if IsInGuild() and CanGuildBankRepair and CanGuildBankRepair() then
    RepairAllItems(true)   -- guild funds, then your own for what the daily limit doesn't cover
  end
  RepairAllItems()
  local coins = (C_CurrencyInfo and C_CurrencyInfo.GetCoinText and C_CurrencyInfo.GetCoinText(cost)) or GetCoinTextureString(cost)
  ns.Print("repaired for " .. coins .. ".")
end

---------------------------------------------------------------------------
-- Faster loot
---------------------------------------------------------------------------
local lastLoot = 0
local function FastLoot()
  if GetTime() - lastLoot < 0.3 then return end
  lastLoot = GetTime()
  if GetCVarBool("autoLootDefault") ~= IsModifiedClick("AUTOLOOTTOGGLE") then
    for i = GetNumLootItems(), 1, -1 do LootSlot(i) end
  end
end

---------------------------------------------------------------------------
local QUEST_EVENTS = { QUEST_DETAIL = true, QUEST_ACCEPT_CONFIRM = true, QUEST_PROGRESS = true, QUEST_COMPLETE = true,
                       QUEST_AUTOCOMPLETE = true, QUEST_GREETING = true }
local f = CreateFrame("Frame")
f:SetScript("OnEvent", function(_, event, arg1, arg2)
  if QUEST_EVENTS[event] then
    if not A.On("quests") or Shift() then return end
    if event == "QUEST_DETAIL" then ns.Safe("Automation", OnDetail)
    elseif event == "QUEST_ACCEPT_CONFIRM" then ns.Safe("Automation", OnAcceptConfirm)
    elseif event == "QUEST_PROGRESS" then ns.Safe("Automation", OnProgress)
    elseif event == "QUEST_COMPLETE" then ns.Safe("Automation", OnComplete)
    elseif event == "QUEST_AUTOCOMPLETE" then ns.Safe("Automation", OnAutoComplete, arg1)
    elseif event == "QUEST_GREETING" then ns.Safe("Automation", OnGreeting)
    end
  elseif event == "GOSSIP_SHOW" then
    if Shift() then return end
    if A.On("quests") then ns.Safe("Automation", OnGossipQuests) end
    if A.On("gossip") then ns.Safe("Automation", OnGossipSkip) end
  elseif event == "CONFIRM_SUMMON" then
    if A.On("summon") then ns.Safe("Automation", OnSummon) end
  elseif event == "RESURRECT_REQUEST" then
    if A.On("res") then ns.Safe("Automation", OnResurrect, arg1) end
  elseif event == "MERCHANT_SHOW" then
    if Shift() then return end
    if A.On("repair") then ns.Safe("Automation", Repair) end
    if A.On("junk") then ns.Safe("Automation", SellJunk) end
  elseif event == "MERCHANT_CLOSED" then
    StopSelling()
  elseif event == "UI_ERROR_MESSAGE" then
    if sellTicker and (arg1 == ERR_VENDOR_DOESNT_BUY or arg2 == ERR_VENDOR_DOESNT_BUY) then StopSelling() end
  elseif event == "LOOT_READY" then
    if A.On("loot") then ns.Safe("Automation", FastLoot) end
  end
end)

--- Jobs Leatrix Plus still has on (labels), for the settings and the one-time note.
function A.LeatrixList()
  local t = {}
  for _, ft in ipairs(A.FEATURES) do
    if not ns.db[ft.db] and A.Leatrix(ft.key) then t[#t + 1] = ft.label:lower() end
  end
  return t
end

ns.inits.Automation = function()
  for _, e in ipairs({ "QUEST_DETAIL", "QUEST_ACCEPT_CONFIRM", "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_AUTOCOMPLETE",
                       "QUEST_GREETING", "GOSSIP_SHOW", "CONFIRM_SUMMON", "RESURRECT_REQUEST", "MERCHANT_SHOW",
                       "MERCHANT_CLOSED", "UI_ERROR_MESSAGE", "LOOT_READY" }) do
    pcall(f.RegisterEvent, f, e)
  end
  pcall(hooksecurefunc, "StaticPopup_Show", function(which) ns.Safe("Automation", ReleaseInPvP, which) end)
  local lea = A.LeatrixList()
  if #lea > 0 and not ns.disabled then
    ns.Print("Leatrix Plus is still doing: " .. table.concat(lea, ", ") .. ". I'm leaving those to it. "
      .. "To let this addon do them, turn them off in Leatrix Plus (/ltp > Automation) and /reload.")
  end
end
