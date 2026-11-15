# One-time install. Everything goes into .\runtime (Python, venv, vLLM, opencode, model cache). Re-run it any time: finished steps are skipped.
#   install.bat                      full install (asks nothing unless AirFrameXR cannot be found)
#   install.bat -SkipModel           everything but the ~10 GB model download
#   install.bat -WheelPath C:\x.whl  use a local vLLM wheel instead of downloading it (checksum still verified)
#   install.bat -AirFrameXRDir D:\_VR\AirFrameXR
param(
    [string]$AirFrameXRDir = '',
    [string]$WheelPath = '',
    [switch]$SkipModel,
    [switch]$Force          # install on a GPU/driver the preflight rejects (it will probably not run)
)
. "$PSScriptRoot\common.ps1"
Initialize-Contained
$wheel = Get-Wheel
$model = Get-Model
$sw = [Diagnostics.Stopwatch]::StartNew()

Write-Step '1/8 Preflight'
$gpu = Get-GpuInfo
if (-not $gpu) { throw 'nvidia-smi not found: this needs an NVIDIA GPU and its driver.' }
Write-Host ("   GPU {0}, {1:N1} GB, driver {2}, compute capability {3}" -f $gpu.Name, ($gpu.TotalMB / 1024), $gpu.Driver, $gpu.Cap)
$problems = @()
if ($gpu.Cap -lt 12.0) { $problems += "compute capability $($gpu.Cap): the bundled vLLM carries native Blackwell (SM120, RTX 50 series) kernels only" }
if ([double]($gpu.Driver -replace '^(\d+)\..*', '$1') -lt 580) { $problems += "driver $($gpu.Driver) is older than 580 (needed for CUDA 13)" }
if ($gpu.TotalMB -lt 15000) { $problems += ("only {0:N1} GB of VRAM: the model needs about {1} GB, a 16 GB card is the floor" -f ($gpu.TotalMB / 1024), $model.targetVramGB) }
$free = (Get-PSDrive -Name ($script:Root.Substring(0, 1))).Free / 1GB
if ($free -lt 30) { $problems += ("{0:N0} GB free on this drive, 30 needed (torch 3 GB, vLLM env 4 GB, model 10 GB, caches)" -f $free) }
if (-not [Environment]::Is64BitOperatingSystem) { $problems += '64-bit Windows required' }
if ($problems.Count -gt 0) {
    $problems | ForEach-Object { Write-Warn2 $_ }
    if (-not $Force) { throw 'Preflight failed (see above). -Force installs anyway.' }
}
if ($gpu.UsedMB -gt 3000) { Write-Warn2 ("{0:N1} GB of VRAM is already in use (a game or another model?): the install is fine, serving will not fit until it is closed" -f ($gpu.UsedMB / 1024)) }
Write-Ok 'preflight'

Write-Step '2/8 uv (Python installer)'
if (-not (Test-Path $script:UvExe)) {
    $zip = Join-Path $script:RT 'tmp\uv.zip'
    Get-File "https://github.com/astral-sh/uv/releases/download/$($wheel.uvVersion)/uv-x86_64-pc-windows-msvc.zip" $zip
    Expand-Archive -Force $zip (Join-Path $script:RT 'tools\uv')
    Remove-Item $zip
}
if ((Invoke-Native $script:UvExe @('--version')) -ne 0) { throw 'uv does not run' }

Write-Step "3/8 Python $($wheel.python) + environment"
if (-not (Test-Path $script:VenvPy)) {
    if ((Invoke-Native $script:UvExe @('venv', '--python', $wheel.python, (Join-Path $script:RT 'venv'))) -ne 0) { throw 'uv venv failed' }
}
[void](Invoke-Native $script:VenvPy @('--version'))

Write-Step '4/8 torch (CUDA 13) and the pinned dependencies'
$have = Get-NativeOutput $script:UvExe @('pip', 'freeze', '--python', $script:VenvPy) | Select-String -Pattern '^torch==2\.14\.0\+cu130$'
if (-not $have) {
    $rc = Invoke-Native $script:UvExe @('pip', 'install', '--python', $script:VenvPy, '--index-strategy', 'unsafe-best-match', '--extra-index-url', $wheel.torchIndex, '-r', (Join-Path $script:Root 'requirements.lock.txt'))
    if ($rc -ne 0) { throw 'dependency install failed' }
} else { Write-Ok 'already installed' }

Write-Step "5/8 vLLM $($wheel.version) (native Windows, SM120 kernels)"
$wheelFile = $WheelPath
if (-not $wheelFile) {
    $wheelFile = Join-Path $script:RT "tmp\$($wheel.file)"
    Get-File $wheel.url $wheelFile $wheel.sha256
} else {
    if ((Get-FileHash $wheelFile -Algorithm SHA256).Hash -ine $wheel.sha256) { throw "$wheelFile does not match the pinned checksum in config\wheel.json" }
    Write-Ok 'local wheel, checksum matches'
}
if ((Invoke-Native $script:UvExe @('pip', 'install', '--python', $script:VenvPy, '--no-deps', '--reinstall', $wheelFile)) -ne 0) { throw 'wheel install failed' }
Write-Host '   smoke test (GPU kernels: matmul, FP8, NVFP4)...'
$smoke = Get-NativeOutput $script:VenvPy @((Join-Path $PSScriptRoot 'smoke.py'))
$smoke | ForEach-Object { Write-Host "   $_" }
if ($smoke | Select-String -Pattern 'FAIL|err |Traceback|Error' -Quiet) {
    throw "smoke test failed. If the error is 0xC000001D, Windows hides AVX-512 from the CPU: see README, 'Known problems'."
}

Write-Step '6/8 opencode (the agent shell)'
if (-not (Test-Path $script:OpenCodeExe)) {
    $zip = Join-Path $script:RT 'tmp\opencode.zip'
    Get-File "https://github.com/anomalyco/opencode/releases/download/v$($wheel.opencodeVersion)/opencode-windows-x64.zip" $zip
    Expand-Archive -Force $zip (Join-Path $script:RT 'tools\opencode')
    Remove-Item $zip
}
[void](Invoke-Native $script:OpenCodeExe @('--version'))

Write-Step "7/8 Model: $($model.displayName)"
if ($SkipModel) { Write-Warn2 'skipped (-SkipModel): run install.bat again later, it only downloads what is missing' }
else {
    Write-Host "   $($model.repo) @ $($model.revision.Substring(0, 8))  (resumable; weights are never part of this repo)"
    $py = "from huggingface_hub import snapshot_download; p = snapshot_download('$($model.repo)', revision='$($model.revision)'); print(p)"
    if ((Invoke-Native $script:VenvPy @('-c', $py)) -ne 0) { throw 'model download failed (network? disk?) - run install.bat again to resume' }
    Write-Ok 'model in runtime\cache\huggingface'
}

Write-Step '8/8 AirFrameXR and the docs the agent reads'
if (-not $AirFrameXRDir) { $AirFrameXRDir = Find-AirFrameXR }
if (-not $AirFrameXRDir) {
    Write-Warn2 'AirFrameXR was not found automatically (it is found through the active OpenXR runtime or a running streamer).'
    $AirFrameXRDir = (Read-Host 'Path of your AirFrameXR folder (the one with AirFrameXR.exe), or Enter to set it later').Trim('"').Trim()
}
if ($AirFrameXRDir -and (Test-Path (Join-Path $AirFrameXRDir 'AirFrameXR.exe'))) {
    Set-Content -Encoding ASCII (Join-Path $script:StateDir 'airframexr_dir.txt') $AirFrameXRDir
    Write-Ok "AirFrameXR: $AirFrameXRDir"
} else {
    Write-Warn2 'AirFrameXR folder not set: the agent can still answer from the docs. Re-run install.bat -AirFrameXRDir <folder> to set it.'
}
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'update-docs.ps1')

Write-Host ''
Write-Host ("Installed in {0:N0} s. Start the agent with start.bat (stop it with stop.bat)." -f $sw.Elapsed.TotalSeconds) -ForegroundColor Green
if (-not $model.measured) { Write-Warn2 'config\model.json says "measured": false - the VRAM and speed figures for this model are not verified yet (README, Status).' }
