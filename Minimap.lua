-- Rubber Dinghy - minimap button (LibDataBroker + LibDBIcon, the standard addon button: drag it
-- around the minimap). Left-click: settings. Right-click: show/hide the tracker.
local ADDON, ns = ...
local M = {}
ns.MinimapButton = M

local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
local DBI = LibStub and LibStub("LibDBIcon-1.0", true)
local NAME = "RubberDinghy"

function M.Refresh()
  if not DBI then return end
  ns.db.minimap = ns.db.minimap or {}
  ns.db.minimap.hide = ns.db.minimapHide and true or false
  if ns.db.minimapHide then DBI:Hide(NAME) else DBI:Show(NAME) end
end

ns.inits.Minimap = function()
  if not (LDB and DBI) then return end
  ns.db.minimap = ns.db.minimap or {}
  local obj = LDB:NewDataObject(NAME, {
    type = "launcher",
    text = "Rubber Dinghy",
    icon = "Interface\\AddOns\\" .. ADDON .. "\\media\\icon",
    OnClick = function(_, button)
      if button == "RightButton" then ns.commands.tracker()
      elseif ns.Options then ns.Options.Toggle() end
    end,
    OnTooltipShow = function(tt)
      tt:AddLine("Rubber Dinghy Rapid Level Guide")
      local r = ns.route
      if r and r.step then
        tt:AddLine(("Step %d/%d: %s"):format(r.idx, #ns.steps, r.step.name), 1, 1, 1)
        local s = r.stops and r.stops[1]
        if s then tt:AddLine("Next: " .. s.index .. ". " .. ns.StopTitle(s), 0.8, 0.8, 0.8) end
      end
      tt:AddLine(" ")
      tt:AddLine("Left-click: settings", 0.4, 0.8, 1)
      tt:AddLine("Right-click: show/hide the tracker", 0.4, 0.8, 1)
      tt:AddLine("Drag: move this button", 0.4, 0.8, 1)
    end,
  })
  DBI:Register(NAME, obj, ns.db.minimap)
  M.Refresh()
end

ns.commands.minimap = function()
  ns.db.minimapHide = not ns.db.minimapHide or nil
  M.Refresh()
  ns.Print("minimap button " .. (ns.db.minimapHide and "hidden (/rdr minimap to bring it back)" or "shown"))
end
