# Build the addon zip by hand (no GitHub needed) and optionally install it.
#   powershell -File tools\build_local.ps1 -Version 1.0.0            -> dist\RubberDinghyRapidLevelGuide-1.0.0.zip
#   powershell -File tools\build_local.ps1 -Version 1.0.0 -Install   -> also copies it into the Forever AddOns folder
# Needs a local Libs\ folder (LibStub, CallbackHandler-1.0, HereBeDragons); releases fetch them via .pkgmeta.
param(
  [string]$Version = "dev",
  [switch]$Install,
  [string]$WoW = "C:\Program Files (x86)\World of Warcraft\_forever_"
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$name = "RubberDinghyRapidLevelGuide"
$dist = Join-Path $root "dist"
$out = Join-Path $dist $name

foreach ($lib in "LibStub\LibStub.lua", "CallbackHandler-1.0\CallbackHandler-1.0.lua",
                 "HereBeDragons\HereBeDragons-2.0.lua", "HereBeDragons\HereBeDragons-Pins-2.0.lua") {
  if (-not (Test-Path (Join-Path $root "Libs\$lib"))) { throw "Missing Libs\$lib - copy the libraries in first." }
}

if (Test-Path $out) { Remove-Item $out -Recurse -Force }
New-Item -ItemType Directory -Force $out | Out-Null
Copy-Item (Join-Path $root "*.lua") $out
Copy-Item (Join-Path $root "LICENSE.md"), (Join-Path $root "README.md"), (Join-Path $root "CHANGELOG.md") $out
Copy-Item (Join-Path $root "Libs") (Join-Path $out "Libs") -Recurse

# The packager replaces @project-version@; do the same here. Write without a byte-order mark.
$toc = [IO.File]::ReadAllText((Join-Path $root "$name.toc")).Replace("@project-version@", $Version)
[IO.File]::WriteAllText((Join-Path $out "$name.toc"), $toc, (New-Object Text.UTF8Encoding($false)))

$zip = Join-Path $dist "$name-$Version.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
# Not Compress-Archive: on Windows PowerShell 5.1 it writes "\" in entry names, which Mac/Linux
# unzippers and some addon managers don't treat as folders. Zip entries must use "/".
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::Open($zip, [IO.Compression.ZipArchiveMode]::Create)
try {
  Get-ChildItem $out -Recurse -File | ForEach-Object {
    $entry = $name + "/" + $_.FullName.Substring($out.Length + 1).Replace("\", "/")
    [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $_.FullName, $entry)
  }
} finally { $archive.Dispose() }
Write-Output "Built $zip"

if ($Install) {
  $dest = Join-Path $WoW "Interface\AddOns\$name"
  if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
  Copy-Item $out $dest -Recurse
  Write-Output "Installed to $dest - type /reload in game."
}
