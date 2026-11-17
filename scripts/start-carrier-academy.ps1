[CmdletBinding()]
param([string]$GodotPath='D:\downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe',[switch]$Rebuild)
$ErrorActionPreference='Stop'
$carrierRoot=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$carrierCore=Join-Path $carrierRoot 'target-carrier\release\cas-sim.exe'
if ($Rebuild -or -not (Test-Path -LiteralPath $carrierCore)) {
    $env:CARGO_TARGET_DIR=Join-Path $carrierRoot 'target-carrier'
    Push-Location -LiteralPath $carrierRoot
    try { & "$env:USERPROFILE\.cargo\bin\cargo.exe" build --release --locked --bin cas-sim; if($LASTEXITCODE -ne 0){throw '航母练习核心构建失败'} } finally { Pop-Location }
}
$env:CAS_SIM_PATH=$carrierCore
& $GodotPath --path (Join-Path $carrierRoot 'godot') --script res://scripts/carrier_academy.gd
