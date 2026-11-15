# Shared helpers (dot-sourced by the other scripts). Windows PowerShell 5.1 compatible: no &&, no ternary, ASCII only.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$script:Root = Split-Path -Parent $PSScriptRoot          # the repo folder
$script:RT   = Join-Path $script:Root 'runtime'           # everything installed lives here (delete it to uninstall)
$script:VenvPy  = Join-Path $script:RT 'venv\Scripts\python.exe'
$script:VllmExe = Join-Path $script:RT 'venv\Scripts\vllm.exe'
$script:UvExe   = Join-Path $script:RT 'tools\uv\uv.exe'
$script:OpenCodeExe = Join-Path $script:RT 'tools\opencode\opencode.exe'
$script:StateDir = Join-Path $script:Root 'state'
$script:LogDir   = Join-Path $script:Root 'logs'
$script:Scratch  = Join-Path $script:Root 'scratch'      # the model's own temp folder: it may write here without asking; the code prunes it


# Native programs (uv, curl, python) write progress to stderr. Windows PowerShell 5.1 turns that into terminating errors under
# $ErrorActionPreference = 'Stop', so every native call goes through these two: they judge by the exit code only.
function Invoke-Native([string]$Exe, [string[]]$ArgList) {
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try {
        & $Exe @ArgList 2>&1 | ForEach-Object { $t = $_.ToString(); if ($t -and $t -ne 'System.Management.Automation.RemoteException') { Write-Host ("   " + $t) } }
        return $LASTEXITCODE
    } finally { $ErrorActionPreference = $old }
}
function Get-NativeOutput([string]$Exe, [string[]]$ArgList) {
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { return @(& $Exe @ArgList 2>&1 | ForEach-Object { $_.ToString() }) } finally { $ErrorActionPreference = $old }
}

function Get-Json([string]$Path) { Get-Content -Raw -Encoding UTF8 $Path | ConvertFrom-Json }
function Get-Model  { Get-Json (Join-Path $script:Root 'config\model.json') }
function Get-Wheel  { Get-Json (Join-Path $script:Root 'config\wheel.json') }

function Write-Step([string]$Text) { Write-Host ''; Write-Host "== $Text" -ForegroundColor Cyan }
function Write-Ok([string]$Text)   { Write-Host "   OK  $Text" -ForegroundColor Green }
function Write-Warn2([string]$Text){ Write-Host "   !!  $Text" -ForegroundColor Yellow }

# Every cache and temp folder goes inside runtime\: nothing is written to the user profile, nothing leaks into other tools.
function Initialize-Contained {
    foreach ($d in 'cache\huggingface\hub','cache\vllm','cache\torch','cache\torchinductor','cache\triton','cache\cuda','cache\uv','python','tools','tmp','config\xdg','config\xdg-data','config\xdg-state','cache\xdg') {
        New-Item -ItemType Directory -Force (Join-Path $script:RT $d) | Out-Null
    }
    New-Item -ItemType Directory -Force $script:StateDir, $script:LogDir, $script:Scratch | Out-Null
    $c = Join-Path $script:RT 'cache'
    $e = @{
        HF_HOME = "$c\huggingface"; HF_HUB_CACHE = "$c\huggingface\hub"; HUGGINGFACE_HUB_CACHE = "$c\huggingface\hub"
        VLLM_CACHE_ROOT = "$c\vllm"; VLLM_CONFIG_ROOT = "$($script:RT)\cache\vllm\config"
        TORCH_HOME = "$c\torch"; TORCHINDUCTOR_CACHE_DIR = "$c\torchinductor"; TRITON_CACHE_DIR = "$c\triton"; CUDA_CACHE_PATH = "$c\cuda"
        XDG_CONFIG_HOME = "$($script:RT)\config\xdg"; XDG_DATA_HOME = "$($script:RT)\config\xdg-data"; XDG_STATE_HOME = "$($script:RT)\config\xdg-state"; XDG_CACHE_HOME = "$c\xdg"
        UV_CACHE_DIR = "$c\uv"; UV_PYTHON_INSTALL_DIR = "$($script:RT)\python"; UV_PYTHON_PREFERENCE = 'only-managed'
        PYTHONNOUSERSITE = '1'; TMP = "$($script:RT)\tmp"; TEMP = "$($script:RT)\tmp"
        VLLM_USE_FLASHINFER_SAMPLER = '0'
        OPENCODE_DISABLE_FREE_MODELS = '1'; OPENCODE_DISABLE_MODELS_FETCH = '1'; OPENCODE_DISABLE_AUTOUPDATE = '1'; OPENCODE_DISABLE_CLAUDE_CODE = '1'
    }
    foreach ($k in $e.Keys) { [Environment]::SetEnvironmentVariable($k, $e[$k], 'Process') }
}

# curl.exe ships with Windows 10 1803+; it resumes (-C -) and does not crawl like Invoke-WebRequest on big files.
function Get-File([string]$Url, [string]$Dest, [string]$Sha256 = '') {
    if ((Test-Path $Dest) -and $Sha256) {
        if ((Get-FileHash $Dest -Algorithm SHA256).Hash -ieq $Sha256) { Write-Ok "$(Split-Path -Leaf $Dest) already here, checksum matches"; return }
    }
    New-Item -ItemType Directory -Force (Split-Path -Parent $Dest) | Out-Null
    Write-Host "   downloading $Url"
    $rc = Invoke-Native 'curl.exe' @('-L', '--fail', '--silent', '--show-error', '--retry', '3', '-C', '-', '-o', $Dest, $Url)
    if ($rc -ne 0) { throw "download failed ($rc): $Url" }
    if ($Sha256) {
        $h = (Get-FileHash $Dest -Algorithm SHA256).Hash
        if ($h -ine $Sha256) { throw "checksum mismatch for $Dest`n expected $Sha256`n got      $h" }
        Write-Ok "checksum verified"
    }
}

function Get-GpuInfo {
    $nv = Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue
    if (-not $nv) { return $null }
    $o = Get-NativeOutput 'nvidia-smi.exe' @('--query-gpu=name,memory.total,memory.used,driver_version,compute_cap', '--format=csv,noheader,nounits')
    if (-not $o) { return $null }
    $f = ($o | Select-Object -First 1).Split(',') | ForEach-Object { $_.Trim() }
    [pscustomobject]@{ Name = $f[0]; TotalMB = [int]$f[1]; UsedMB = [int]$f[2]; Driver = $f[3]; Cap = [double]$f[4] }
}

# Where is AirFrameXR? Remembered choice, then the active OpenXR runtime (the launcher's "Switch to AirFrameXR" points it at <folder>\bin),
# then a running AirFrameXR process. Returns $null when unknown: the installer then asks.
function Find-AirFrameXR {
    $remember = Join-Path $script:StateDir 'airframexr_dir.txt'
    if (Test-Path $remember) {
        $d = (Get-Content -Raw $remember).Trim()
        if ($d -and (Test-Path (Join-Path $d 'AirFrameXR.exe'))) { return $d }
    }
    # installed inside the AirFrameXR folder (<AirFrameXR>\agentic)? then the parent is it
    $par = Split-Path -Parent $script:Root
    if ($par -and (Test-Path (Join-Path $par 'AirFrameXR.exe'))) { return $par }
    try {
        $rt = (Get-ItemProperty 'HKLM:\SOFTWARE\Khronos\OpenXR\1' -Name ActiveRuntime -ErrorAction Stop).ActiveRuntime
        if ($rt) {
            $d = Split-Path -Parent (Split-Path -Parent $rt)
            if (Test-Path (Join-Path $d 'AirFrameXR.exe')) { return $d }
        }
    } catch { }
    foreach ($n in 'streamer','launcher','alvr_host','configure') {
        $p = Get-Process -Name $n -ErrorAction SilentlyContinue | Where-Object { $_.Path } | Select-Object -First 1
        if ($p) {
            $d = Split-Path -Parent (Split-Path -Parent $p.Path)
            if (Test-Path (Join-Path $d 'AirFrameXR.exe')) { return $d }
        }
    }
    return $null
}

function Test-Api([int]$Port = 8000) {
    try { Invoke-RestMethod "http://127.0.0.1:$Port/v1/models" -TimeoutSec 2 | Out-Null; return $true } catch { return $false }
}
