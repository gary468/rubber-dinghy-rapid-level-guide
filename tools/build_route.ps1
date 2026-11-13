# Rebuild Data.lua from scratch: decode QuestieDB, build the zone-based data, plan the fastest visit
# order, then build the planned route. Needs Python with Pillow-free stdlib for decode/gen, and a Python
# with the `lupa` package for the planner (pass -LupaPython if it isn't the default python).
param(
  [string]$WoW = "C:\Program Files (x86)\World of Warcraft\_forever_",
  [string]$LupaPython = "python"
)
$ErrorActionPreference = "Stop"
$tools = $PSScriptRoot
$root = Split-Path -Parent $tools
python -I "$tools\decode.py" $WoW "$tools\data.json"
python -I "$tools\gen_route.py" $tools $WoW "$tools\Data_zones.lua"
# Planner settings chosen by comparing variants (see analysis report): all quests, no grinding.
$env:HOP_SAME = "5000"; $env:HOP_OTHER = "14000"; $env:MIN_SHARE = "0.5"; $env:MIN_QUESTS = "10"; $env:RELAX = "1"
Push-Location $tools
& $LupaPython "$tools\plan_route.py" "$tools\Data_zones.lua" $WoW "$tools\plan.json"
Pop-Location
python -I "$tools\gen_route.py" $tools $WoW "$root\Data.lua" "$tools\plan.json"
Write-Output "Data.lua rebuilt from the plan."
