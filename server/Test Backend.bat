@echo off
setlocal
cd /d "%~dp0"
if not exist ".venv\Scripts\python.exe" (
  echo Run Start Test Server.bat once first so the Python dependencies are installed.
  pause
  exit /b 1
)
.venv\Scripts\python.exe test_backend.py
pause
