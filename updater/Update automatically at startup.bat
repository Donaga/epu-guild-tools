@echo off
rem Double-click once: EPU Guild Tools will then update itself every time Windows starts.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Update-EPU.ps1" -Startup
