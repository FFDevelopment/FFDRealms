@echo off
rem The caller receives GODOT_EXE. No engine is bundled or downloaded.
set "GODOT_EXE="
if not "%~1"=="" set "GODOT_EXE=%~1"
if not defined GODOT_EXE if exist "%~dp0..\.godot_path.txt" set /p GODOT_EXE=<"%~dp0..\.godot_path.txt"
if defined GODOT_EXE set "GODOT_EXE=%GODOT_EXE:"=%"
if defined GODOT_EXE if not exist "%GODOT_EXE%" set "GODOT_EXE="
if not defined GODOT_EXE for /f "delims=" %%G in ('where godot.exe 2^>nul') do if not defined GODOT_EXE set "GODOT_EXE=%%G"
if not defined GODOT_EXE (
 echo.
 echo Locate your Godot 4 Standard executable.
 echo Drag the Godot .exe into this window, then press Enter.
 set /p "GODOT_EXE=Godot executable: "
)
set "GODOT_EXE=%GODOT_EXE:"=%"
if not exist "%GODOT_EXE%" (
 echo ERROR: That executable does not exist.
 exit /b 1
)
>"%~dp0..\.godot_path.txt" echo "%GODOT_EXE%"
exit /b 0
