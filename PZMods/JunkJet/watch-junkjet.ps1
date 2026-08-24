# Copy the mod into every Project Zomboid install you are testing, whenever it
# changes. Run it in its own PowerShell window while working; Ctrl+C to stop.
#
#     powershell -ExecutionPolicy Bypass -File .\watch-junkjet.ps1
#
# Destinations that do not exist are skipped, so you can leave both listed and
# only have one build installed. See TESTING.md for setting the second one up.

$src = Split-Path -Parent $MyInvocation.MyCommand.Path

$targets = @(
    # Build 42 - the default Steam branch, using the normal user folder.
    (Join-Path $env:USERPROFILE "Zomboid\mods\JunkJet"),

    # Build 41 - a second install run with -cachedir=C:\PZ41Data, so its saves
    # and logs stay out of the way of Build 42's. Edit this if you put it
    # somewhere else.
    "C:\PZ41Data\mods\JunkJet"
)

Write-Host "Watching $src"
foreach ($t in $targets) {
    $parent = Split-Path -Parent (Split-Path -Parent $t)
    if (Test-Path $parent) {
        Write-Host "     -> $t"
    } else {
        Write-Host "     -> $t   (not installed, skipping)" -ForegroundColor DarkGray
    }
}
Write-Host "Restart the game to pick changes up; Lua is not hot-loaded."
Write-Host ""

while ($true) {
    foreach ($dst in $targets) {
        # Only mirror where the install actually exists. The check is on the
        # grandparent (the user folder), not the mod folder itself, which
        # robocopy would happily create in the middle of nowhere.
        $parent = Split-Path -Parent (Split-Path -Parent $dst)
        if (-not (Test-Path $parent)) { continue }

        # /MIR mirrors, so deletions propagate too. Notes and tests are
        # excluded: the game has no use for them.
        robocopy $src $dst /MIR /NFL /NDL /NJH /NJS /NC /NS `
            /XF "watch-junkjet.ps1" "README.md" "TESTING.md" `
            /XD "tests" | Out-Null

        if ($LASTEXITCODE -ge 8) {
            Write-Host "robocopy problem on $dst (exit $LASTEXITCODE)" -ForegroundColor Red
        }
    }
    Start-Sleep -Seconds 2
}
