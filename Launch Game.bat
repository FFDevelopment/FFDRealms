@echo off
setlocal
call "%~dp0tools\find_godot.bat" "%~1"
if errorlevel 1 goto failed
pushd "%~dp0"
"%GODOT_EXE%" --editor --headless --audio-driver Dummy --path . --quit
if errorlevel 1 goto failed_pop
"%GODOT_EXE%" --path .
if errorlevel 1 goto failed_pop
popd
exit /b 0
:failed_pop
popd
:failed
echo.
echo Launch failed. Import project.godot in Godot 4.3 or newer and inspect the Output panel.
pause
exit /b 1
