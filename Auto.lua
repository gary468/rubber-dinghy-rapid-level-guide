-- Rubber Dinghy - accept and hand in route quests automatically.
--   * Accepts a quest only when it's on your route (the current step, or a get-ready side route) and
--     you haven't skipped it - never filler, grey quests or ones you chose to skip.
--   * Hands in finished quests the guide knows. When a quest offers a choice of rewards, the pick is
--     left to you.
--   * Picks the route quest straight from a quest giver's chat menu / quest list.
--   * Hold Shift while talking to the NPC to do it yourself. Settings > "Accept and hand in route
--     quests automatically" switches it off.
--   * Stands aside when Questie or Leatrix Plus already automate quests (two addons pressing the same
--     buttons would fight), and says so once.
local ADDON, ns = ...
local A = {}
ns.Auto = A

local function Paused() return IsShiftKeyDown and IsShiftKeyDown() end

-- Another addon already automating quests?
function A.OtherAutomation()
  local qp = Questie and Questie.db and Questie.db.profile
  if qp and (qp.autoaccept or qp.autoAccept or qp.autocomplete or qp.autoComplete) then return "Questie" end
  if LeaPlusDB and (LeaPlusDB.AutomateQuests == "On") then return "Leatrix Plus" end
  return nil
end

local function Enabled()
  local db = ns.db
  if not db or ns.disabled or db.noAuto then return false end
  if A.OtherAutomation() then return false end
  return true
end

-- Quests the route wants you to pick up right now.
local function WantAccept(id)
  if not id or id == 0 then return false end
  if ns.db.skip and ns.db.skip[id] then return false end
  local r = ns.route
  if not r then return false end
  for _, s in ipairs(r.stops or {}) do
    for _, a in ipairs(s.actions or {}) do
      if a.row.id == id and a.kind == "get" then return true end
    end
  end
  for _, a in ipairs(r.loose or {}) do
    if a.row.id == id and a.kind == "get" then return true end
  end
  return false
end

-- Quests the guide knows (any step, the track pool), not skipped: hand them in.
local function WantTurnIn(id)
  if not id or id == 0 then return false end
  if ns.db.skip and ns.db.skip[id] then return false end
  return ns.quests[id] ~= nil
end

local function LogFull()
  local max = (C_QuestLog and C_QuestLog.GetMaxNumQuestsCanAccept and C_QuestLog.GetMaxNumQuestsCanAccept()) or 20
  return #ns.QuestLog() >= max
end

---------------------------------------------------------------------------
-- Quest dialog
---------------------------------------------------------------------------
local function OnDetail()
  local id = GetQuestID and GetQuestID()
  if WantAccept(id) and not LogFull() then AcceptQuest() end
end

local function OnProgress()
  local id = GetQuestID and GetQuestID()
  if WantTurnIn(id) and IsQuestCompletable and IsQuestCompletable() then CompleteQuest() end
end

local function OnComplete()
  local id = GetQuestID and GetQuestID()
  if not WantTurnIn(id) then return end
  local choices = GetNumQuestChoices and GetNumQuestChoices() or 0
  if choices <= 1 then GetQuestReward(choices) end   -- a real choice of rewards: yours to make
end

---------------------------------------------------------------------------
-- Quest givers with several quests: chat menu (gossip) and quest list (greeting)
---------------------------------------------------------------------------
local function OnGossip()
  local G = C_GossipInfo
  if not G then return end
  -- finished quests to hand in first, then route quests to pick up
  for _, q in ipairs((G.GetActiveQuests and G.GetActiveQuests()) or {}) do
    if q.isComplete and WantTurnIn(q.questID) then G.SelectActiveQuest(q.questID); return end
  end
  for _, q in ipairs((G.GetAvailableQuests and G.GetAvailableQuests()) or {}) do
    if WantAccept(q.questID) and not LogFull() then G.SelectAvailableQuest(q.questID); return end
  end
end

local function OnGreeting()
  -- the older quest list: titles only, so match by name against the route
  local function IdByTitle(title, wantFn)
    for id, q in pairs(ns.quests) do
      if q.n == title and wantFn(id) then return id end
    end
  end
  for i = 1, (GetNumActiveQuests and GetNumActiveQuests() or 0) do
    local title, complete = GetActiveTitle(i)
    if complete and IdByTitle(title, WantTurnIn) then SelectActiveQuest(i); return end
  end
  for i = 1, (GetNumAvailableQuests and GetNumAvailableQuests() or 0) do
    local title = GetAvailableTitle(i)
    if IdByTitle(title, WantAccept) and not LogFull() then SelectAvailableQuest(i); return end
  end
end

---------------------------------------------------------------------------
local f = CreateFrame("Frame")
f:SetScript("OnEvent", function(_, event)
  if not Enabled() or Paused() then return end
  if event == "QUEST_DETAIL" then ns.Safe("Auto", OnDetail)
  elseif event == "QUEST_PROGRESS" then ns.Safe("Auto", OnProgress)
  elseif event == "QUEST_COMPLETE" then ns.Safe("Auto", OnComplete)
  elseif event == "GOSSIP_SHOW" then ns.Safe("Auto", OnGossip)
  elseif event == "QUEST_GREETING" then ns.Safe("Auto", OnGreeting)
  end
end)

ns.inits.Auto = function()
  for _, e in ipairs({ "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "GOSSIP_SHOW", "QUEST_GREETING" }) do
    pcall(f.RegisterEvent, f, e)
  end
  local other = A.OtherAutomation()
  if other and not ns.db.noAuto and not ns.db.toldAuto then
    ns.db.toldAuto = true
    ns.Print(other .. " already accepts and hands in quests, so the guide's own auto accept stays off. "
      .. "Turn " .. other .. "'s off if you want the guide's (it only takes route quests).")
  end
end
