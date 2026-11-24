@echo off
rem Starts the EPU Discord bot and keeps it running: it restarts after it
rem updates itself and after a crash. Close this window to stop it.
cd /d "%~dp0"
if not exist .venv (
  py -3 -m venv .venv
  .venv\Scripts\python -m pip install -r requirements.txt
)
rem Kept on one line on purpose: the bot can update this file while it runs,
rem and Windows reads a running .bat line by line.
.venv\Scripts\python supervise.py & pause & exit /b
