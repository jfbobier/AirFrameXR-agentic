# Installs the assistant INSIDE your AirFrameXR folder (<AirFrameXR>\agentic) and runs the installer. Started by setup.bat.
#   - finds the AirFrameXR folder (the folder setup.bat is in, the active OpenXR runtime, a running streamer, or asks)
#   - downloads this repository (GitHub zip), copies it to <AirFrameXR>\agentic (an update keeps runtime, state, notes, logs, docs-cache and your opencode.user.json)
#   - runs install.ps1 there (the model is ~9 GB), then adds <AirFrameXR>\AirFrameXR-Assistant.bat
param([string]$StartDir = '', [string]$AirFrameXRDir = '', [string]$Ref = 'v0.1.0', [string]$ZipPath = '', [switch]$SkipModel, [switch]$Force, [string]$WheelPath = '')
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
function Say([string]$t) { Write-Host $t }
function Test-Afxr([string]$d) { $d -and (Test-Path -LiteralPath (Join-Path $d 'AirFrameXR.exe')) }

Say ''
Say '=== AirFrameXR assistant (experimental): setup ==='
$afxr = $AirFrameXRDir
if (-not (Test-Afxr $afxr) -and $StartDir) {
    $d = $StartDir.TrimEnd('\')
    if (Test-Afxr $d) { $afxr = $d } elseif (Test-Afxr (Split-Path -Parent $d)) { $afxr = Split-Path -Parent $d }
}
if (-not (Test-Afxr $afxr)) {
    try {
        $rt = (Get-ItemProperty 'HKLM:\SOFTWARE\Khronos\OpenXR\1' -Name ActiveRuntime -ErrorAction Stop).ActiveRuntime
        $d = Split-Path -Parent (Split-Path -Parent $rt)
        if (Test-Afxr $d) { $afxr = $d }
    } catch { }
}
if (-not (Test-Afxr $afxr)) {
    foreach ($n in 'streamer', 'launcher', 'alvr_host') {
        $p = Get-Process -Name $n -ErrorAction SilentlyContinue | Where-Object { $_.Path } | Select-Object -First 1
        if ($p) { $d = Split-Path -Parent (Split-Path -Parent $p.Path); if (Test-Afxr $d) { $afxr = $d; break } }
    }
}
if (-not (Test-Afxr $afxr)) {
    Say 'Your AirFrameXR folder was not found automatically.'
    $afxr = (Read-Host 'Path of the folder that contains AirFrameXR.exe').Trim('"').Trim()
}
if (-not (Test-Afxr $afxr)) { throw "AirFrameXR.exe not found in '$afxr'. Put setup.bat in your AirFrameXR folder, or enter its path." }
Say "AirFrameXR folder: $afxr"

$target = Join-Path $afxr 'agentic'
$tmp = Join-Path $env:TEMP ('afxr-agentic-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force $tmp | Out-Null
try {
    $zip = $ZipPath
    if (-not $zip) {
        $zip = Join-Path $tmp 'repo.zip'
        Say "Downloading the assistant ($Ref)..."
        & curl.exe -L --fail -s -S -o $zip "https://github.com/jfbobier/AirFrameXR-agentic/archive/$Ref.zip"
        if ($LASTEXITCODE -ne 0) { throw 'download failed (network?)' }
    }
    Expand-Archive -Force $zip (Join-Path $tmp 'x')
    $src = Get-ChildItem (Join-Path $tmp 'x') -Directory | Select-Object -First 1
    New-Item -ItemType Directory -Force $target | Out-Null
    # keep the user's installed runtime, state, journal, logs, docs copy and own opencode additions on an update
    & robocopy.exe $src.FullName $target /E /NFL /NDL /NJH /NJS /NP /XD runtime state notes logs docs-cache /XF opencode.user.json | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "copy failed (robocopy $LASTEXITCODE)" }
} finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
Say "Assistant files: $target"

$args2 = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $target 'scripts\install.ps1'), '-AirFrameXRDir', $afxr)
if ($SkipModel) { $args2 += '-SkipModel' }
if ($Force) { $args2 += '-Force' }
if ($WheelPath) { $args2 += @('-WheelPath', $WheelPath) }
& powershell.exe @args2
if ($LASTEXITCODE -ne 0) { throw "install failed ($LASTEXITCODE). Run setup.bat again: finished steps are skipped." }

$launcher = Join-Path $afxr 'AirFrameXR-Assistant.bat'
$bat = "@echo off`r`nrem Starts the AirFrameXR assistant (local model + agent). Close your game first: the model holds ~13 GB of VRAM.`r`ncall `"%~dp0agentic\start.bat`" %*`r`n"
[IO.File]::WriteAllText($launcher, $bat, (New-Object System.Text.ASCIIEncoding))
Say ''
Say "Done. Start the assistant with: $launcher"
Say '(stop it, and free the VRAM, with agentic\stop.bat; remove it all by deleting the agentic folder and that .bat)'
