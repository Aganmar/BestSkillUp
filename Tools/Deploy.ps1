# Copies the add-on from this repository into the game's AddOns folder, for testing changes
# between releases. Copies exactly what a release zip contains: the TOC, every file it loads,
# the in-game icon and the licence. Files in the AddOns folder that a release no longer ships
# are removed. Run with WoW closed, or /reload (a full restart if the TOC's file list changed).
#
#   powershell -ExecutionPolicy Bypass -File Tools\Deploy.ps1
param(
    [string]$AddOns = "C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns"
)
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$dest = Join-Path $AddOns "BestSkillUp"

$toc = Join-Path $repo "BestSkillUp.toc"
$files = @("BestSkillUp.toc", "Media\BestSkillUp.tga", "LICENSE")
$files += Get-Content $toc | Where-Object { $_ -notmatch '^\s*#' -and $_.Trim() -ne "" } | ForEach-Object { $_.Trim() }

New-Item -ItemType Directory -Force -Path (Join-Path $dest "Media") | Out-Null
foreach ($f in $files) {
    Copy-Item -Force (Join-Path $repo $f) (Join-Path $dest $f)
}

# Remove anything a release wouldn't contain (old files, dev files).
$keep = $files | ForEach-Object { (Join-Path $dest $_).ToLower() }
Get-ChildItem -Recurse -File $dest | Where-Object { $keep -notcontains $_.FullName.ToLower() } | ForEach-Object {
    Write-Host "Removing $($_.FullName)"
    Remove-Item -Force $_.FullName
}
# The dev-only companion add-on (disenchant recorder) goes in its own folder, which WowUp doesn't manage.
$devSrc = Join-Path $repo "Dev\BestSkillUp_Dev"
$devDest = Join-Path $AddOns "BestSkillUp_Dev"
New-Item -ItemType Directory -Force -Path $devDest | Out-Null
Copy-Item -Force (Join-Path $devSrc "*") $devDest
Write-Host "Deployed BestSkillUp_Dev to $devDest"

$version = (Select-String -Path $toc -Pattern '^## Version:\s*(.+)$').Matches[0].Groups[1].Value
Write-Host "Deployed BestSkillUp $version ($($files.Count) files) to $dest"
