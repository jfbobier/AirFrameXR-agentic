# Generates state\opencode.json (model, context, instruction files, permission rules) from config\model.json. Called by start.ps1; can be run alone.
. "$PSScriptRoot\common.ps1"
Initialize-Contained
$m = Get-Model
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
Write-Host "state\opencode.json written"

