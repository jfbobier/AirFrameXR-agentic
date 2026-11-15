param([string]$Tag,[string]$Obj,[string]$Std="",[switch]$Keep,[switch]$Shim,[string]$Extra="",[switch]$DropPreproc,[switch]$DropCplusplus)
$env:CCACHE_DISABLE='1'
Set-Location D:\vllm-build\vllm\build\temp.win-amd64-cpython-313\Release
$cmd = (& ninja -t commands $Obj | Select-Object -Last 1)
$base = [IO.Path]::GetFileName($Obj)
$cmd = $cmd.Replace($base, ($base -replace '\.obj$',".$Tag.obj"))
if($Std){ $extra = if($Keep){'-keep -keep-dir D:/vllm-build/keep'}else{''}; $cmd = $cmd.Replace('-std=c++20',"-std=$Std $extra") }
if($Shim){ $i=$cmd.IndexOf('nvcc.exe"'); $cmd=$cmd.Insert($i+9,' -I"D:/vllm-build/shim"') }
if($Extra){ $cmd=$cmd.Replace(' -c '," $Extra -c ") }
if($DropPreproc){ $cmd = $cmd.Replace('-Xcompiler=/Zc:preprocessor','') }
if($DropCplusplus){ $cmd = $cmd.Replace('-Xcompiler=/Zc:__cplusplus','') }
$sw=[Diagnostics.Stopwatch]::StartNew()
cmd /c $cmd 2>&1 | Out-File "D:\vllm-build\logs\tv-$Tag.out" -Encoding utf8
"rc=$LASTEXITCODE seconds=$([int]$sw.Elapsed.TotalSeconds)" | Out-File "D:\vllm-build\logs\tv-$Tag.done"
