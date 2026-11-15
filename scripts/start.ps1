# Starts the model server (hidden), waits until it answers, writes the per-PC facts, generates the opencode config and opens the agent.
#   start.bat                 normal
#   start.bat -KeepRunning    leave the model server up after the agent exits (it holds ~12 GB of VRAM until stop.bat)
#   start.bat -Eager          start the server without CUDA graphs (fallback when it runs out of memory at startup)
param([switch]$KeepRunning, [switch]$Eager, [double]$TargetGB = 0, [int]$TimeoutSec = 900)
. "$PSScriptRoot\common.ps1"
Initialize-Contained
$m = Get-Model
foreach ($need in $script:VllmExe, $script:OpenCodeExe) { if (-not (Test-Path $need)) { throw "Not installed ($need). Run install.bat first." } }

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

# 3. opencode config. Generated every start, so the model, context and paths always match config\model.json.
#    Your own additions go in config\opencode.user.json (keys are merged on top; its "permissions" are appended LAST, so they win).
$afxr = Find-AirFrameXR
$rootS = $script:Root.Replace('\', '/')
$perm = New-Object System.Collections.Generic.List[object]
function Add-Perm([string]$a, [string]$r, [string]$e) { $perm.Add([ordered]@{ action = $a; resource = $r; effect = $e }) }
Add-Perm '*' '*' 'ask'                                    # nothing happens silently unless allowed below
Add-Perm 'question' '*' 'allow'
foreach ($a in 'read', 'glob', 'grep') { Add-Perm $a '*' 'allow' }
Add-Perm 'read' '*.env' 'ask'; Add-Perm 'read' '*/.ssh/*' 'deny'; Add-Perm 'read' '*id_rsa*' 'deny'; Add-Perm 'read' '*id_ed25519*' 'deny'
Add-Perm 'external_directory' '*' 'ask'
Add-Perm 'external_directory' "$rootS/*" 'allow'
if ($afxr) { Add-Perm 'external_directory' ($afxr.Replace('\', '/') + '/*') 'allow' }
Add-Perm 'edit' '*' 'ask'                                 # every config change shows its diff and waits for you
Add-Perm 'edit' "$rootS/notes/*" 'allow'                  # the change journal
Add-Perm 'webfetch' '*' 'ask'
Add-Perm 'webfetch' 'https://raw.githubusercontent.com/jfbobier/*' 'allow'
Add-Perm 'webfetch' 'https://github.com/jfbobier/*' 'allow'
Add-Perm 'websearch' '*' 'ask'
Add-Perm 'shell' '*' 'ask'
foreach ($c in 'Get-Content *', 'Get-ChildItem *', 'Get-Item *', 'Select-String *', 'Test-Path *', 'Get-Date', 'Measure-Object *', 'Select-Object *',
               'Sort-Object *', 'Where-Object *', 'ForEach-Object *', 'Get-FileHash *', 'nvidia-smi *', 'nvidia-smi', 'findstr *', 'type *', 'dir *') { Add-Perm 'shell' $c 'allow' }
foreach ($c in 'Remove-Item *', 'rm *', 'del *', 'rmdir *', 'git push *', 'git reset *') { Add-Perm 'shell' $c 'ask' }

$cfg = [ordered]@{
    '$schema'    = 'https://opencode.ai/config.json'
    update       = 'disable'
    model        = "vllm/$($m.servedName)"
    instructions = @("$rootS/agent/AGENTS.md", "$rootS/state/machine.md")
    providers    = [ordered]@{ vllm = [ordered]@{
        name     = 'vLLM (local, AirFrameXR-agentic)'
        settings = [ordered]@{ baseURL = 'http://127.0.0.1:8000/v1' }
        models   = [ordered]@{ ([string]$m.servedName) = [ordered]@{
            name = [string]$m.displayName
            capabilities = [ordered]@{ tools = $true; input = @('text'); output = @('text') }
            limit = [ordered]@{ context = [int]$m.contextTokens; output = [int]$m.outputTokens } } } } }
    permissions  = $perm
}
$userCfg = Join-Path $script:Root 'config\opencode.user.json'
if (Test-Path $userCfg) {
    $u = Get-Json $userCfg
    foreach ($prop in $u.PSObject.Properties) {
        if ($prop.Name -eq 'permissions') { foreach ($r in $prop.Value) { $perm.Add($r) } }
        elseif ($prop.Name -notin 'providers', 'instructions') { $cfg[$prop.Name] = $prop.Value }
        elseif ($prop.Name -eq 'instructions') { $cfg.instructions = @($cfg.instructions) + @($prop.Value) }
    }
}
$cfgPath = Join-Path $script:StateDir 'opencode.json'
$enc = New-Object System.Text.UTF8Encoding $false
[IO.File]::WriteAllText($cfgPath, ($cfg | ConvertTo-Json -Depth 12), $enc)
$env:OPENCODE_CONFIG = $cfgPath

# 4. agent
New-Item -ItemType Directory -Force (Join-Path $script:Root 'notes') | Out-Null
$notes = Join-Path $script:Root 'notes\changes.md'
if (-not (Test-Path $notes)) { Set-Content -Encoding UTF8 $notes "# Change journal`r`n`r`nOne entry per change: date, file, key, old -> new, why, how to verify, result once known.`r`n" }
$work = $script:Root
if ($afxr) { $work = $afxr }
Set-Location $work
Write-Host "Agent working folder: $work"
& $script:OpenCodeExe
if (-not $KeepRunning) { & "$PSScriptRoot\stop.ps1" -Quiet | Out-Null; Write-Host 'Model server stopped, VRAM released.' }
