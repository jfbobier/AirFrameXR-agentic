# The model server, foreground. Normally started by start.ps1. The VRAM budget is a size, not a fraction:
# vLLM wants a fraction of the card, so it is computed (targetVramGB / total VRAM) and printed.
param(
    [double]$TargetGB = 0,        # 0 = config\model.json
    [int]$Ctx = 0,                # 0 = config\model.json
    [int]$Port = 8000,
    [switch]$Online,              # allow Hugging Face lookups (default: offline, the model was fetched by install.bat)
    [switch]$Eager,               # no CUDA graphs (less VRAM, slower); a fallback when startup runs out of memory
    [string]$Extra = ''           # extra vllm arguments separated by '|'
)
. "$PSScriptRoot\common.ps1"
Initialize-Contained
$m = Get-Model
$gpu = Get-GpuInfo
if (-not $gpu) { throw 'nvidia-smi not found' }
if ($TargetGB -le 0) { $TargetGB = [double]$m.targetVramGB }
if ($Ctx -le 0) { $Ctx = [int]$m.contextTokens }
$util = [math]::Round([math]::Min(0.92, [math]::Max(0.30, ($TargetGB * 1024.0) / $gpu.TotalMB)), 2)
if (-not $Online) { $env:HF_HUB_OFFLINE = '1' }
$env:PATH = (Join-Path $script:RT 'venv\Scripts') + ';' + $env:PATH

$a = @('serve', $m.repo, '--revision', $m.revision, '--host', '127.0.0.1', '--port', "$Port",
    '--served-model-name', $m.servedName,
    '--max-model-len', "$Ctx", '--gpu-memory-utilization', "$util", '--kv-cache-dtype', $m.kvCacheDtype,
    '--max-num-batched-tokens', "$($m.maxNumBatchedTokens)", '--max-num-seqs', "$($m.maxNumSeqs)",
    '--enable-prefix-caching',
    '--reasoning-parser', $m.reasoningParser, '--enable-auto-tool-choice', '--tool-call-parser', $m.toolParser)
foreach ($x in $m.extraServeArgs) { $a += $x }
if ($Eager) { $a += '--enforce-eager' }
if ($Extra) { $a += $Extra.Split('|') }
Write-Host ("Model {0}: budget {1} GB of {2:N1} GB -> gpu-memory-utilization {3}, context {4}" -f $m.displayName, $TargetGB, ($gpu.TotalMB / 1024), $util, $Ctx)
Write-Host ("vllm " + ($a -join ' '))
& $script:VllmExe @a
