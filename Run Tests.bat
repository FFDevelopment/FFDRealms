@echo off
setlocal
call "%~dp0tools\find_godot.bat" "%~1"
if errorlevel 1 goto failed
pushd "%~dp0"
set "LOG=%~dp0test-results.log"
>"%LOG%" echo FFDRealms v0.4.0 local Godot test run
"%GODOT_EXE%" --version >>"%LOG%" 2>&1
echo Importing the project...
"%GODOT_EXE%" --editor --headless --audio-driver Dummy --path . --quit >>"%LOG%" 2>&1
if errorlevel 1 goto failed_pop
findstr /C:"SCRIPT ERROR:" /C:"Parse Error:" /C:"ERROR:" "%LOG%" >nul
if not errorlevel 1 goto failed_pop
echo Running simulation regression tests...
"%GODOT_EXE%" --headless --audio-driver Dummy --path . --script res://tests/test_runner.gd >>"%LOG%" 2>&1
if errorlevel 1 goto failed_pop
findstr /C:"SCRIPT ERROR:" /C:"Parse Error:" /C:"ERROR:" "%LOG%" >nul
if not errorlevel 1 goto failed_pop
echo Running Northreach and moving-combat regression tests...
"%GODOT_EXE%" --headless --audio-driver Dummy --path . --script res://tests/frontier_runner.gd >>"%LOG%" 2>&1
if errorlevel 1 goto failed_pop
findstr /C:"SCRIPT ERROR:" /C:"Parse Error:" /C:"ERROR:" "%LOG%" >nul
if not errorlevel 1 goto failed_pop
echo Checking character appearance and protected town boundaries...
"%GODOT_EXE%" --headless --audio-driver Dummy --path . --script res://tests/appearance_runner.gd >>"%LOG%" 2>&1
if errorlevel 1 goto failed_pop
findstr /C:"SCRIPT ERROR:" /C:"Parse Error:" /C:"ERROR:" "%LOG%" >nul
if not errorlevel 1 goto failed_pop
echo Checking dodge timing, committed strikes and proximity engagement...
"%GODOT_EXE%" --headless --audio-driver Dummy --path . --script res://tests/combat_runner.gd >>"%LOG%" 2>&1
if errorlevel 1 goto failed_pop
findstr /C:"SCRIPT ERROR:" /C:"Parse Error:" /C:"ERROR:" "%LOG%" >nul
if not errorlevel 1 goto failed_pop
echo Checking texture imports, material isolation and collision consistency across texture settings...
"%GODOT_EXE%" --headless --audio-driver Dummy --path . --script res://tests/texture_runner.gd >>"%LOG%" 2>&1
if errorlevel 1 goto failed_pop
findstr /C:"SCRIPT ERROR:" /C:"Parse Error:" /C:"ERROR:" "%LOG%" >nul
if not errorlevel 1 goto failed_pop
echo Checking actual terrain, click raycasts, map alignment and sloped warnings...
"%GODOT_EXE%" --headless --audio-driver Dummy --path . --script res://tests/terrain_runner.gd >>"%LOG%" 2>&1
if errorlevel 1 goto failed_pop
findstr /C:"SCRIPT ERROR:" /C:"Parse Error:" /C:"ERROR:" "%LOG%" >nul
if not errorlevel 1 goto failed_pop
echo Checking scene and UI initialization...
"%GODOT_EXE%" --headless --audio-driver Dummy --path . --script res://tests/smoke_runner.gd >>"%LOG%" 2>&1
if errorlevel 1 goto failed_pop
findstr /C:"SCRIPT ERROR:" /C:"Parse Error:" /C:"ERROR:" "%LOG%" >nul
if not errorlevel 1 goto failed_pop
type "%LOG%"
echo.
echo All local checks completed without reported errors.
echo Visual appearance, controls and performance still require a manual playtest.
popd
pause
exit /b 0
:failed_pop
echo.
echo TEST FAILURE. See test-results.log in the project folder.
if exist "%LOG%" type "%LOG%"
popd
:failed
pause
exit /b 1
