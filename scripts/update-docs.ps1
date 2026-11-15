# Copies the AirFrameXR project docs into docs-cache\ so the agent can read them offline. Safe to re-run (an old copy is kept when a download fails).
. "$PSScriptRoot\common.ps1"
Initialize-Contained
$base = 'https://raw.githubusercontent.com/jfbobier/AirFrameXR/main'
$files = @(
    'README.md',
    'docs/INSTALL.md', 'docs/EXPERIMENTAL_SWITCHES.md', 'docs/PERFORMANCE_KNOBS.md', 'docs/PERFORMANCE_FINDINGS.md',
    'docs/FRAME_GENERATION.md', 'docs/FRAME_GENERATION_UNCAPPED.md', 'docs/HMD_PROFILES.md', 'docs/AVP_FOV.md',
    'docs/FOV_CALIBRATION.md', 'docs/ARCHITECTURE.md', 'docs/progress.md'
)
$dest = Join-Path $script:Root 'docs-cache'
New-Item -ItemType Directory -Force $dest | Out-Null
$ok = 0; $bad = 0
foreach ($f in $files) {
    $name = Split-Path -Leaf $f
    $tmp = Join-Path $script:RT "tmp\$name"
    $rc = Invoke-Native 'curl.exe' @('-sL', '--fail', '--retry', '2', '-o', $tmp, "$base/$f")
    if ($rc -eq 0 -and (Test-Path $tmp) -and (Get-Item $tmp).Length -gt 200) {
        Move-Item -Force $tmp (Join-Path $dest $name); $ok++
    } else { Write-Warn2 "could not fetch $f (kept the old copy if any)"; $bad++; Remove-Item -Force $tmp -ErrorAction SilentlyContinue }
}
if ($ok -gt 0) { Set-Content -Encoding ASCII (Join-Path $script:RT 'cache\docs_fetched.txt') (Get-Date -Format 'yyyy-MM-dd HH:mm') }
Write-Ok "docs-cache: $ok files updated, $bad failed"
