-- Rubber Dinghy - items in your bags that start a quest ("This Item Begins a Quest": A Mangled
-- Journal, Message in a Bottle...). They're looted from mobs or picked up from objects, so no quest
-- giver ever shows them. Whenever your bags change, any such item for a quest you haven't done and
-- don't have is listed at the top of the tracker, with one chat note when it first turns up.
-- Opening it (right-click in your bags) shows the quest; "Accept and hand in quests" accepts it.
local ADDON, ns = ...
local S = {}
ns.Starters = S

local list = {}          -- { {bag, slot, itemID, item, questID, quest} }
local told = {}          -- questID -> true (chat note once per session)

local function QuestInfo(bag, slot)
  if C_Container and C_Container.GetContainerItemQuestInfo then
    local ok, info = pcall(C_Container.GetContainerItemQuestInfo, bag, slot)
    if ok and type(info) == "table" then return info.questID, info.isActive end
  end
  if GetContainerItemQuestInfo then
    local ok, _, questID, isActive = pcall(GetContainerItemQuestInfo, bag, slot)
    if ok then return questID, isActive end
  end
end

local function Done(id)
  return (C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(id)) or false
end

local function QuestName(id)
  local q = ns.quests and ns.quests[id]
  if q and q.n then return q.n end
  if C_QuestLog and C_QuestLog.GetTitleForQuestID then
    local ok, t = pcall(C_QuestLog.GetTitleForQuestID, id)
    if ok and t then return t end
  end
  return "a quest"
end

function S.Scan()
  local out = {}
  if not (C_Container and C_Container.GetContainerNumSlots) then list = out; return out end
  for bag = 0, 4 do
    for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
      local questID, isActive = QuestInfo(bag, slot)
      if questID and questID > 0 and not isActive and not Done(questID) and ns.LogIndex(questID) == 0
        and not (ns.db and ns.db.skip and ns.db.skip[questID]) then
        local info = C_Container.GetContainerItemInfo and C_Container.GetContainerItemInfo(bag, slot)
        local name = info and (info.itemName or (info.hyperlink and info.hyperlink:match("%[(.-)%]"))) or "an item"
        out[#out + 1] = { bag = bag, slot = slot, itemID = info and info.itemID, item = name,
                          questID = questID, quest = QuestName(questID) }
        if not told[questID] then
          told[questID] = true
          ns.Print(("%s starts a quest: %s. Right-click it in your bags."):format(name, QuestName(questID)))
        end
      end
    end
  end
  list = out
  return out
end

--- Items in your bags that start a quest you can take.
function S.List() return list end

local f = CreateFrame("Frame")
local pending = false
f:SetScript("OnEvent", function()
  if pending then return end
  pending = true
  C_Timer.After(0.5, function()
    pending = false
    if not ns.db or ns.disabled then return end
    local before = #list
    ns.Safe("Starters", S.Scan)
    if #list ~= before then ns.Queue() end
  end)
end)

ns.inits.Starters = function()
  for _, e in ipairs({ "BAG_UPDATE_DELAYED", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN" }) do
    pcall(f.RegisterEvent, f, e)
  end
  ns.Safe("Starters", S.Scan)
end
