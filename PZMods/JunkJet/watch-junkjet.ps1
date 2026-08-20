# Copy the mod into the game's mods folder whenever it changes.
#
# Replaces what `pzstudio watch` used to do. Run it in its own PowerShell
# window while working; Ctrl+C to stop.
#
#     powershell -ExecutionPolicy Bypass -File .\watch-junkjet.ps1

$src = Split-Path -Parent $MyInvocation.MyCommand.Path
$dst = Join-Path $env:USERPROFILE "Zomboid\mods\JunkJet"

Write-Host "Watching $src"
Write-Host "     -> $dst"
Write-Host "Restart the game or server to pick changes up; Lua is not hot-loaded."
Write-Host ""

while ($true) {
    # /MIR mirrors, so deletions propagate too. The script and any docs are
    # excluded: the game has no use for them.
    robocopy $src $dst /MIR /NFL /NDL /NJH /NJS /NC /NS `
        /XF "watch-junkjet.ps1" "README.md" | Out-Null

    if ($LASTEXITCODE -ge 8) {
        Write-Host "robocopy reported a problem (exit $LASTEXITCODE)" -ForegroundColor Red
    }
    Start-Sleep -Seconds 2
}
