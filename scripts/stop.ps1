# Stops the model server completely (the engine runs in child processes that can outlive a killed launcher and keep VRAM).
# Matches by command line: only processes running from THIS folder's runtime\ are touched, never another python or another vLLM.
param([switch]$Quiet)
$rt = (Join-Path (Split-Path -Parent $PSScriptRoot) 'runtime')
$serve = Join-Path $PSScriptRoot 'serve.ps1'
for ($pass = 0; $pass -lt 3; $pass++) {
    $procs = Get-CimInstance Win32_Process | Where-Object {
        $c = $_.CommandLine
        $_.ProcessId -ne $PID -and $c -and (($c.IndexOf($rt, [StringComparison]::OrdinalIgnoreCase) -ge 0) -or ($c.IndexOf($serve, [StringComparison]::OrdinalIgnoreCase) -ge 0)) -and $_.Name -notmatch '^opencode'
    }
    if (-not $procs) { break }
    $procs | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Sleep 2
}
if (-not $Quiet) {
    $used = & nvidia-smi.exe --query-gpu=memory.used --format=csv,noheader 2>$null
    Write-Host "Stopped. GPU memory in use now: $used"
}
