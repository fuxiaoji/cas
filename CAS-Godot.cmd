@echo off
setlocal
set "CAS_GODOT_DIR=D:\downloads\Godot_v4.7.2-stable_win64.exe"
set "CAS_GODOT=%CAS_GODOT_DIR%\Godot_v4.7.2-stable_win64.exe"
set "CAS_GODOT_CONSOLE=%CAS_GODOT_DIR%\Godot_v4.7.2-stable_win64_console.exe"
set "CAS_SIM_PATH="
if not exist "%CAS_GODOT%" (
  echo Godot was not found at "%CAS_GODOT%".
  goto failed
)
pushd "%~dp0"
if not exist "%~dp0artifacts" mkdir "%~dp0artifacts"
if exist "%USERPROFILE%\.cargo\bin\cargo.exe" (
  echo Preparing the CAS combat core...
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\prepare-godot-core.ps1" > "%~dp0artifacts\godot-launch-build.log" 2>&1
  if errorlevel 1 goto failed_in_workspace
)
if not exist "%~dp0godot\bin\core-current.json" (
  echo The CAS combat core is missing. Install Rust and run this launcher again.
  goto failed_in_workspace
)
"%CAS_GODOT_CONSOLE%" --headless --path "%~dp0godot" --editor --import --quit > "%~dp0artifacts\godot-launch-import.log" 2>&1
if errorlevel 1 goto failed_in_workspace
findstr /B /C:"SCRIPT ERROR:" /C:"ERROR:" "%~dp0artifacts\godot-launch-import.log" >nul
if not errorlevel 1 goto failed_in_workspace
if /I "%~1"=="--check" (
  echo CAS Godot is ready. No game window was opened.
  popd
  exit /b 0
)
start "CAS Godot" "%CAS_GODOT%" --path "%~dp0godot"
popd
exit /b 0

:failed_in_workspace
popd
:failed
echo Could not start CAS. See artifacts\godot-launch-build.log and godot-launch-import.log.
pause
exit /b 1
