@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\update-docs.ps1" %*
pause
