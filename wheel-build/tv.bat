@echo off
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" -vcvars_ver=14.43
set ROOT=D:\vllm-build
set CUDA_HOME=C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v13.5
set CUDA_PATH=%CUDA_HOME%
set PATH=%ROOT%\venv\Scripts;%CUDA_HOME%\bin;C:\Program Files\Git\cmd;%USERPROFILE%\.cargo\bin;C:\Strawberry\perl\bin;%LOCALAPPDATA%\Microsoft\WinGet\Links;%PATH%;C:\Program Files\Git\usr\bin
set GIT_CONFIG_COUNT=1
set GIT_CONFIG_KEY_0=safe.directory
set GIT_CONFIG_VALUE_0=*
set TORCH_CUDA_ARCH_LIST=12.0a
set VLLM_TARGET_DEVICE=cuda
set CMAKE_BUILD_TYPE=Release
set VLLM_DISABLE_SCCACHE=1
set SETUPTOOLS_SCM_PRETEND_VERSION=0.33.0
set MAX_JOBS=8
set NVCC_THREADS=2
set VLLM_RS_BUILD_VERSION=0.33.0
set OPENSSL_SRC_PERL=C:\Strawberry\perl\bin\perl.exe
for /f "delims=" %%i in ('where protoc 2^>nul') do set PROTOC=%%i
powershell -NoProfile -ExecutionPolicy Bypass -File D:\vllm-build\tv.ps1 %*
