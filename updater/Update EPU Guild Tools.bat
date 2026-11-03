@echo off
rem Double-click to install or update EPU Guild Tools for WoW: Forever.
rem Add "startup" after the file name to also update automatically when Windows starts.
if /i "%~1"=="startup" (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Update-EPU.ps1" -Startup
) else if /i "%~1"=="nostartup" (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Update-EPU.ps1" -NoStartup
) else if /i "%~1"=="folder" (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Update-EPU.ps1" -ChooseFolder
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Update-EPU.ps1"
)
