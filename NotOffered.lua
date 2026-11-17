-- When you talk to a quest giver and the quest the route wants from them isn't in their list, the route
-- skips it and says so: Forever's new zones have givers who only offer a quest after something the
-- databases don't record (Mirt and Hnaz in Mount Hyjal, 16 Nov 2026). If that giver offers it later,
-- it goes straight back on the route. Turn it off in the settings ("Skip quests a giver doesn't offer").
local _, ns = ...
local N = {}
ns.NotOffered = N

local function Secret(v) return v ~= nil and issecretvalue and issecretvalue(v) end

local function NpcName()
  if not UnitExists("npc") then return nil end
  if UnitIsPlayer and UnitIsPlayer("npc") then return nil end
  local ok, name = pcall(UnitName, "npc")
  if not ok or not name or Secret(name) then return nil end
  return name
end

local function InLog(id) return ns.LogIndex and (ns.LogIndex(id) or 0) > 0 end
local function Done(id)
  if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then return C_QuestLog.IsQuestFlaggedCompleted(id) and true or false end
  if IsQuestFlaggedCompleted then return IsQuestFlaggedCompleted(id) and true or false end
  return false
end

--- What the open window offers: {ids = {[id]=true}, titles = {[title]=true}, pending = a finished quest
--- is waiting to be handed in (a follow-up may only appear after it, so don't judge yet).
local function Offered(event)
  local ids, titles, pending = {}, {}, false
  if event == "GOSSIP_SHOW" then
    local G = C_GossipInfo
    if not G then return nil end
    for _, q in ipairs(G.GetAvailableQuests and G.GetAvailableQuests() or {}) do
      if q.questID then ids[q.questID] = true end
      if q.title then titles[q.title] = true end
    end
    for _, q in ipairs(G.GetActiveQuests and G.GetActiveQuests() or {}) do
      if q.questID then ids[q.questID] = true end
      if q.title then titles[q.title] = true end
      if q.isComplete then pending = true end
    end
  elseif event == "QUEST_GREETING" then
    for i = 1, (GetNumAvailableQuests and GetNumAvailableQuests() or 0) do
      local t = GetAvailableTitle(i); if t then titles[t] = true end
    end
    for i = 1, (GetNumActiveQuests and GetNumActiveQuests() or 0) do
      local t, complete = GetActiveTitle(i)
      if t then titles[t] = true end
      if complete then pending = true end
    end
  elseif event == "QUEST_DETAIL" then
    -- the giver had exactly one quest and opened it straight away
    local id = GetQuestID and GetQuestID()
    if id and id ~= 0 then ids[id] = true end
    local t = GetTitleText and GetTitleText()
    if t then titles[t] = true end
  elseif event == "QUEST_PROGRESS" then
    -- the giver's only business was a quest you're handing in
    pending = true
  end
  return { ids = ids, titles = titles, pending = pending }
end

local function IsOffered(o, id, q)
  return o.ids[id] or (q and q.n and o.titles[q.n]) or false
end

--- The quests the route is sending you to this giver for right now (pick-ups on the current stops).
function N.Expected(name)
  local out, seen = {}, {}
  local r = ns.route
  for _, s in ipairs(r and r.stops or {}) do
    for _, a in ipairs(s.actions or {}) do
      local id = a.row and a.row.id
      local q = id and ns.quests and ns.quests[id]
      if a.kind == "get" and q and q.g and q.g[1] == name and not seen[id] then
        seen[id] = true
        out[#out + 1] = id
      end
    end
  end
  return out
end

local lastUI, lastTurnIn = 0, -100
function N.Check(event)
  local now = GetTime()
  local prev = lastUI
  lastUI = now
  if not ns.db then return end
  -- a quest window opened from a list you just saw (or a hand-in's reward page) is not the giver's list
  if (event == "QUEST_DETAIL" or event == "QUEST_PROGRESS") and now - prev < 3 then return end
  local name = NpcName()
  if not name then return end
  local o = Offered(event)
  if not o then return end
  local db = ns.db

  -- skipped earlier because this giver didn't offer it, and now they do: back on the route
  local back = {}
  for id in pairs(db.notOffered or {}) do
    local q = ns.quests and ns.quests[id]
    if q and q.g and q.g[1] == name and IsOffered(o, id, q) then back[#back + 1] = id end
  end
  for _, id in ipairs(back) do
    db.notOffered[id] = nil
    if db.skip then db.skip[id] = nil end
    ns.Print(("%s offers %s now: it's back on the route."):format(name, ns.quests[id].n))
  end

  -- just handed something in: its follow-up may not be on offer for a moment yet (Gary 17 Nov:
  -- "Elder Mistpaw doesn't offer Deal Dread to Deadwood" a second before he took it)
  if db.noGiverSkip or o.pending or now - lastTurnIn < 5 then
    if #back > 0 then ns.Recompute() end
    return
  end
  local level = UnitLevel("player") or 0
  local skipped = {}
  for _, id in ipairs(N.Expected(name)) do
    local q = ns.quests[id]
    if not IsOffered(o, id, q) and not InLog(id) and not Done(id) and level >= (q.r or 0)
      and not (db.skip and db.skip[id]) then
      db.skip = db.skip or {}
      db.skip[id] = true
      db.notOffered = db.notOffered or {}
      db.notOffered[id] = true
      skipped[#skipped + 1] = q.n
    end
  end
  if #skipped > 0 then
    local one = #skipped == 1
    ns.Print(("%s doesn't offer %s yet, so the route skips %s. %s back when they offer %s (or /rdr unskip)."):format(
      name, table.concat(skipped, ", "), one and "it" or "them", one and "It comes" or "They come", one and "it" or "them"))
  end
  if #skipped > 0 or #back > 0 then ns.Recompute() end
end

local f = CreateFrame("Frame")
for _, e in ipairs({ "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE" }) do
  f:RegisterEvent(e)
end
f:SetScript("OnEvent", function(_, event)
  if event == "QUEST_COMPLETE" then lastUI = GetTime(); lastTurnIn = GetTime(); return end
  ns.Safe("NotOffered", N.Check, event)
end)
