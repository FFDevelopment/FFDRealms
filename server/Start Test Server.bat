@echo off
setlocal
cd /d "%~dp0"
if not exist ".venv\Scripts\python.exe" (
  py -3 -m venv .venv || goto :error
  .venv\Scripts\python.exe -m pip install --upgrade pip || goto :error
  .venv\Scripts\python.exe -m pip install -r requirements.txt || goto :error
)
if "%FFDREALMS_ADMIN_KEY%"=="" set "FFDREALMS_ADMIN_KEY=change-this-before-internet-use"
echo.
echo FFDRealms test backend starting on http://127.0.0.1:8765
echo Admin panel: http://127.0.0.1:8765/admin?key=%FFDREALMS_ADMIN_KEY%
echo Keep this window open while testing multiplayer.
echo.
.venv\Scripts\python.exe server.py
goto :eof
:error
echo Server setup failed. Confirm Python 3 is installed and available as 'py'.
pause
