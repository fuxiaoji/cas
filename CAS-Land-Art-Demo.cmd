@echo off
setlocal
set "CAS_DEMO_DIR=%~dp0demos\land-art-3d"
set "CAS_GODOT=D:\downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"
if not exist "%CAS_GODOT%" (
  echo Godot executable was not found at the registered location.
  pause
  exit /b 1
)
start "CAS Coastal Art Demo" "%CAS_GODOT%" --path "%CAS_DEMO_DIR%"
endlocal
