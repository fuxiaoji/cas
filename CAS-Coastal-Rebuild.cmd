@echo off
setlocal
set "CAS_GODOT=D:\downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"
set "CAS_WORLD3D=1"
set "CAS_COASTAL_V1=1"
set "CAS_SIM_PATH=%~dp0artifacts\coastal-combat-v2-20261116\core\cas-sim.exe"
if not exist "%CAS_GODOT%" (
  echo Godot was not found at the registered location.
  pause
  exit /b 1
)
if not exist "%CAS_SIM_PATH%" (
  echo The new coastal build is not ready. See the delivery notes.
  pause
  exit /b 1
)
if not exist "%~dp0artifacts\coastal-rebuild-20261116\player.json" (
  echo The independent coastal test account is not ready.
  pause
  exit /b 1
)
start "CAS New Coast" "%CAS_GODOT%" --path "%~dp0godot" res://scenes/coastal_play_v1.tscn
endlocal
