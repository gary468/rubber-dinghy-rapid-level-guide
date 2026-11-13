# Rebuild Data.lua from scratch for the fastest 40-60 (minutes played):
#   1. decode QuestieDB, 2. build the zone data (+ qmeta.json, each quest's objective types),
#   3. greedy plan (plan_route.py) as a starting point, 4. local search over the order of zones and
#   dungeon runs (optimize.py, seeded with the greedy plan and the current plan.json), 5. Data.lua.
# Dungeons come from the DungeonJournal addon if it's installed. The time model's numbers (kill
# time, flight/boat times, dungeon run times) are at the top of the time model in routelib.py.
# Needs a Python with the `lupa` package for steps 3-4 (pass -LupaPython if it isn't the default).
param(
  [string]$WoW = "C:\Program Files (x86)\World of Warcraft\_forever_",
  [string]$LupaPython = "python",
  [double]$Minutes = 20,
  # Dungeons the route must include, comma-separated (e.g. "Sunken Temple,Maraudon").
  [string]$Force = "Sunken Temple"
)
$ErrorActionPreference = "Stop"
$tools = $PSScriptRoot
$root = Split-Path -Parent $tools
python -I "$tools\decode.py" $WoW "$tools\data.json"
python -I "$tools\gen_route.py" $tools $WoW "$tools\Data_zones.lua"
Push-Location $tools
& $LupaPython "$tools\plan_route.py" "$tools\Data_zones.lua" $WoW "$tools\plan_greedy.json" "$tools\qmeta.json"
$seeds = @("$tools\plan_greedy.json")
if (Test-Path "$tools\plan.json") { $seeds += "$tools\plan.json" }
& $LupaPython -u "$tools\optimize.py" "$tools\Data_zones.lua" $WoW "$tools\qmeta.json" "$tools\plan_new.json" @seeds --minutes $Minutes --force $Force
Move-Item -Force "$tools\plan_new.json" "$tools\plan.json"
Pop-Location
python -I "$tools\gen_route.py" $tools $WoW "$root\Data.lua" "$tools\plan.json"
Write-Output "Data.lua rebuilt from the optimised plan."
