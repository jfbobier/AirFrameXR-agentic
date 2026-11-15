# Background job started by start.ps1 while the agent runs: keeps EVERY old version of AirFrameXR's config files, whoever changes them
# (the model's edit tool, our CLI, the user's own windows) and writes a program-made journal entry for each change.
#   - old version archived to  <agentic>\history\<yyyymmdd-HHmmss>\config\<file>   (never overwritten, never pruned by the program)
#   - one line appended to     <agentic>\notes\auto-journal.md                        (the model's own notes stay in changes.md: no shared writer)
#   - a file that stops being valid JSON is put back at once from the archived version and the entry says REVERTED
# Watches config\*.json of the AirFrameXR folder except session.json (compiled at every streamer start). Polls once per second: a handful of small files.
param([Parameter(Mandatory)][string]$AirFrameXRDir, [int]$IntervalMs = 1000)
. "$PSScriptRoot\common.ps1"
$cfg = Join-Path $AirFrameXRDir 'config'
$shadow = Join-Path $script:StateDir 'shadow'
$hist = Join-Path $script:Root 'history'
$auto = Join-Path $script:Root 'notes\auto-journal.md'
New-Item -ItemType Directory -Force $shadow, (Split-Path -Parent $auto) | Out-Null
if (-not (Test-Path $auto)) { Set-Content -Encoding UTF8 $auto "# Auto-journal (written by the program, not by the model)`r`n`r`nOne line per change to AirFrameXR's config files while the assistant ran: time, file, old and new checksum, where the old version is kept.`r`n" }

function Sha([string]$p) { try { (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.Substring(0, 8).ToLower() } catch { $null } }
function Note([string]$t) { try { Add-Content -Encoding UTF8 -Path $auto -Value $t } catch { } }
function Watched { Get-ChildItem -LiteralPath $cfg -Filter *.json -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'session.json' } }

# seed: the state at start is the baseline
foreach ($f in Watched) { Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $shadow $f.Name) -Force }
$known = @{}
foreach ($f in Watched) { $known[$f.Name] = Sha $f.FullName }

while ($true) {
    Start-Sleep -Milliseconds $IntervalMs
    $names = @(Watched | ForEach-Object { $_.Name }) + @($known.Keys) | Select-Object -Unique
    foreach ($n in $names) {
        $live = Join-Path $cfg $n
        $old = Join-Path $shadow $n
        $now = if (Test-Path -LiteralPath $live) { Sha $live } else { 'deleted' }
        if ($null -eq $now) { continue }                                   # locked right now: next tick
        if ($known.ContainsKey($n) -and $known[$n] -eq $now) { continue }
        if (-not $known.ContainsKey($n)) {                                  # a new file
            if ($now -ne 'deleted') { Copy-Item -LiteralPath $live -Destination $old -Force; $known[$n] = $now; Note ("- {0} config\{1} created (sha {2})" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $n, $now) }
            continue
        }
        Start-Sleep -Milliseconds 400                                       # a write in progress: take the settled content
        $now = if (Test-Path -LiteralPath $live) { Sha $live } else { 'deleted' }
        if ($null -eq $now -or $known[$n] -eq $now) { continue }
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $dir = Join-Path $hist "$stamp\config"
        New-Item -ItemType Directory -Force $dir | Out-Null
        if (Test-Path -LiteralPath $old) { Copy-Item -LiteralPath $old -Destination (Join-Path $dir $n) -Force }
        $where = "history\$stamp\config\$n"
        $time = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        if ($now -eq 'deleted') {
            Note ("- {0} config\{1} DELETED (was sha {2}); old version: {3}" -f $time, $n, $known[$n], $where)
            $known.Remove($n)
            continue
        }
        $valid = $true
        try { [void](Get-Content -LiteralPath $live -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { $valid = $false }
        if (-not $valid -and (Test-Path -LiteralPath $old)) {
            Copy-Item -LiteralPath $live -Destination (Join-Path $dir "$n.rejected") -Force        # what was refused, for the user to see
            Copy-Item -LiteralPath $old -Destination $live -Force
            Note ("- {0} config\{1} REVERTED: the new content (sha {2}) was not valid JSON; the previous version (sha {3}) is back in place; the refused content is kept as {4}.rejected" -f $time, $n, $now, $known[$n], $where)
            continue
        }
        Note ("- {0} config\{1} changed: sha {2} -> {3}; old version: {4}" -f $time, $n, $known[$n], $now, $where)
        Copy-Item -LiteralPath $live -Destination $old -Force
        $known[$n] = $now
    }
}
