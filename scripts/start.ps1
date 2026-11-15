# Starts the model server (hidden), waits until it answers, writes the per-PC facts, generates the opencode config and opens the agent.
#   start.bat                 normal
#   start.bat -KeepRunning    leave the model server up after the agent exits (it holds ~12 GB of VRAM until stop.bat)
#   start.bat -Eager          start the server without CUDA graphs (fallback when it runs out of memory at startup)
param([switch]$KeepRunning, [switch]$Eager, [double]$TargetGB = 0, [int]$TimeoutSec = 900)
. "$PSScriptRoot\common.ps1"
Initialize-Contained
$m = Get-Model
foreach ($need in $script:VllmExe, $script:OpenCodeExe) { if (-not (Test-Path $need)) { throw "Not installed ($need). Run install.bat first." } }

# 0. the model's scratch folder: the code (not the model) removes what is older than 7 days
Get-ChildItem $script:Scratch -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } | Remove-Item -Force -ErrorAction SilentlyContinue

# 1. server
if (Test-Api) { Write-Host 'Model server already running.' }
else {
    & "$PSScriptRoot\stop.ps1" -Quiet | Out-Null      # a stale engine process can still hold VRAM
    $argl = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSScriptRoot\serve.ps1`"")
    if ($Eager) { $argl += '-Eager' }
    if ($TargetGB -gt 0) { $argl += @('-TargetGB', "$TargetGB") }
    $p = Start-Process powershell.exe -ArgumentList $argl -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput (Join-Path $script:LogDir 'server.log') -RedirectStandardError (Join-Path $script:LogDir 'server.err')
    Write-Host 'Starting the model server (first start after boot: 1-3 minutes, compiling kernels the first time takes longer)...'
    $t = [Diagnostics.Stopwatch]::StartNew()
    while (-not (Test-Api)) {
        if ($p.HasExited -or $t.Elapsed.TotalSeconds -gt $TimeoutSec) {
            Write-Host "The model server did not start. Last lines of logs\server.err:" -ForegroundColor Red
            Get-Content (Join-Path $script:LogDir 'server.err') -Tail 15 -ErrorAction SilentlyContinue
            Write-Host 'Common causes: VRAM already in use (close the game), or too little free VRAM: try start.bat -Eager. See README, Known problems.'
            & "$PSScriptRoot\stop.ps1" -Quiet | Out-Null
            exit 1
        }
        Start-Sleep 3
    }
    Write-Host ("Ready in {0:N0} s." -f $t.Elapsed.TotalSeconds)
}

# 2. per-PC facts + docs freshness
& "$PSScriptRoot\probe.ps1" | Out-Null

# 3. opencode config (see make-config.ps1)
& "$PSScriptRoot\make-config.ps1" | Out-Null
$afxr = Find-AirFrameXR
$env:OPENCODE_CONFIG = Join-Path $script:StateDir 'opencode.json'

# 4. agent
New-Item -ItemType Directory -Force (Join-Path $script:Root 'notes') | Out-Null
$notes = Join-Path $script:Root 'notes\changes.md'
if (-not (Test-Path $notes)) { Set-Content -Encoding UTF8 $notes "# Change journal`r`n`r`nOne entry per change: date, file, key, old -> new, why, how to verify, result once known.`r`n" }
$work = $script:Root
if ($afxr) { $work = $afxr }
Set-Location $work
Write-Host "Agent working folder: $work"
$job = $null
if ($afxr) { $job = Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSScriptRoot\config-journal.ps1`"", '-AirFrameXRDir', "`"$afxr`"") -WindowStyle Hidden -PassThru }
& $script:OpenCodeExe
if ($job) {
    Stop-Process -Id $job.Id -Force -ErrorAction SilentlyContinue
    $auto = Join-Path $script:Root 'notes\auto-journal.md'
    if (Test-Path $auto) {
        $new = @(Get-Content $auto | Where-Object { $_ -like "- $((Get-Date).ToString('yyyy-MM-dd'))*" })
        if ($new.Count -gt 0) { Write-Host ''; Write-Host "Config changes recorded today (old versions are in $($script:Root)\history):" -ForegroundColor Cyan; $new | Select-Object -Last 8 | ForEach-Object { Write-Host "  $_" } }
    }
}
if (-not $KeepRunning) { & "$PSScriptRoot\stop.ps1" -Quiet | Out-Null; Write-Host 'Model server stopped, VRAM released.' }
