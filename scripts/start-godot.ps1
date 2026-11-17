[CmdletBinding()]
param(
    [string] $GodotPath = 'D:\downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe',
    [switch] $Editor,
    [switch] $SkipBuild,
    [switch] $SkipImport,
    [switch] $RunTests,
    [switch] $NoLaunch
)

$ErrorActionPreference = 'Stop'
$workspaceRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$projectPath = Join-Path $workspaceRoot 'godot'
$artifactsPath = Join-Path $workspaceRoot 'artifacts'
$coreManifest = Join-Path $workspaceRoot 'godot\bin\core-current.json'

if ((Test-Path -LiteralPath $GodotPath) -and (Get-Item -LiteralPath $GodotPath).PSIsContainer) {
    $GodotPath = Join-Path $GodotPath 'Godot_v4.7.2-stable_win64.exe'
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot was not found at $GodotPath. Pass -GodotPath with the executable path."
}
$GodotPath = (Resolve-Path -LiteralPath $GodotPath).Path
$consoleName = [IO.Path]::GetFileNameWithoutExtension($GodotPath) + '_console.exe'
$consolePath = Join-Path ([IO.Path]::GetDirectoryName($GodotPath)) $consoleName
if (-not (Test-Path -LiteralPath $consolePath -PathType Leaf)) { $consolePath = $GodotPath }
New-Item -ItemType Directory -Path $artifactsPath -Force | Out-Null

function Invoke-Logged([string] $Executable, [string[]] $Arguments, [string] $LogPath) {
    & $Executable @Arguments 2>&1 | Tee-Object -FilePath $LogPath | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "$Executable failed. See $LogPath" }
    if (Select-String -LiteralPath $LogPath -Pattern '^SCRIPT ERROR:|^ERROR:' -Quiet) {
        throw "Godot reported an error. See $LogPath"
    }
}

Push-Location -LiteralPath $workspaceRoot
try {
    if (-not $SkipBuild) {
        $cargoCommand = Get-Command 'cargo.exe' -ErrorAction SilentlyContinue
        $cargoPath = if ($cargoCommand) { $cargoCommand.Source } else { Join-Path $env:USERPROFILE '.cargo\bin\cargo.exe' }
        if (-not (Test-Path -LiteralPath $cargoPath -PathType Leaf)) {
            throw 'Install Rust using rustup before building the local combat core.'
        }
        & (Join-Path $PSScriptRoot 'prepare-godot-core.ps1')
    }
    if (-not (Test-Path -LiteralPath $coreManifest -PathType Leaf)) {
        throw 'The local combat core is missing. Start without -SkipBuild.'
    }
    $installedCore = Get-Content -LiteralPath $coreManifest -Raw | ConvertFrom-Json
    $env:CAS_SIM_PATH = Join-Path (Join-Path $projectPath 'bin') $installedCore.executable
    if (-not $SkipImport) {
        Invoke-Logged $consolePath @('--headless', '--path', $projectPath, '--editor', '--quit') (Join-Path $artifactsPath 'godot-import.log')
    }
    if ($RunTests) {
        Invoke-Logged $consolePath @('--headless', '--path', $projectPath, '--script', 'tests/economy_audio_test.gd') (Join-Path $artifactsPath 'godot-economy-audio-test.log')
        Invoke-Logged $consolePath @('--headless', '--path', $projectPath, '--script', 'tests/audio_settings_ui_test.gd') (Join-Path $artifactsPath 'godot-audio-settings-ui-test.log')
    }
    if ($NoLaunch) {
        Write-Host 'Godot project and local combat core are ready. No game window was opened.'
        return
    }
    $gameArguments = @('--path', $projectPath)
    if ($Editor) { $gameArguments += '--editor' }
    # This is the visible interactive game/editor, not a background helper.
    & $GodotPath @gameArguments
} finally {
    Pop-Location
}
