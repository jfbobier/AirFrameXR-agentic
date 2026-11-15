@echo off
rem AirFrameXR assistant: one-click setup. Put this file in your AirFrameXR folder (next to AirFrameXR.exe) and double-click it.
setlocal
if exist "%~dp0scripts\install.ps1" (
  call "%~dp0install.bat" %*
  exit /b %errorlevel%
)
set "BS=%TEMP%\afxr-agentic-bootstrap.ps1"
curl.exe -L --fail -s -S -o "%BS%" https://raw.githubusercontent.com/jfbobier/AirFrameXR-agentic/v0.1.1/scripts/bootstrap.ps1
if errorlevel 1 (
  echo Download failed. Check your internet connection.
  pause
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%BS%" -StartDir "%~dp0." %*
if errorlevel 1 echo Setup stopped, see the message above. Run setup.bat again to resume.
pause
