[CmdletBinding()]
param([string] $PreparedBinary = '', [switch] $RebuildCore, [switch] $VerifiedRelease)
$ErrorActionPreference = 'Stop'
$casWorkspace = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$casBuild = Join-Path $casWorkspace 'target\godot-core-build'
function Get-CasSHA256([string] $LiteralPath) {
    $casHasher = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($casHasher.ComputeHash([IO.File]::ReadAllBytes($LiteralPath))).Replace('-', '').ToLowerInvariant() }
    finally { $casHasher.Dispose() }
}
$casBin = Join-Path $casWorkspace 'godot\bin'
$casManifest = Join-Path $casBin 'core-current.json'
if ($VerifiedRelease -and [string]::IsNullOrEmpty($PreparedBinary)) {
    throw 'A verified release must name the exact already-tested binary.'
}
# Normal play uses the tested runtime. A concurrent feature branch must not
# silently publish its unfinished Rust changes when somebody opens the game.
if ([string]::IsNullOrEmpty($PreparedBinary) -and -not $RebuildCore -and (Test-Path -LiteralPath $casManifest)) {
    $casCurrent = Get-Content -LiteralPath $casManifest -Raw | ConvertFrom-Json
    if ($casCurrent.PSObject.Properties['verified_release'] -and $casCurrent.verified_release) {
        $casRelativeCurrent = [string]$casCurrent.executable
        if (-not $casRelativeCurrent.StartsWith('runtime/') -or $casRelativeCurrent.Contains('..') -or [IO.Path]::IsPathRooted($casRelativeCurrent)) { throw 'The verified runtime path is invalid.' }
        $casVerifiedPath = Join-Path $casBin $casRelativeCurrent
        if (-not (Test-Path -LiteralPath $casVerifiedPath -PathType Leaf) -or (Get-CasSHA256 $casVerifiedPath) -ne $casCurrent.sha256) { throw 'The verified combat core is missing or changed.' }
        Write-Host "Using verified combat core $(([string]$casCurrent.sha256).Substring(0,16)). Use -RebuildCore explicitly for development builds."
        return
    }
}
if ([string]::IsNullOrEmpty($PreparedBinary)) {
    $casCargoCommand = Get-Command cargo.exe -ErrorAction SilentlyContinue
    $casCargo = if ($casCargoCommand) { $casCargoCommand.Source } else { Join-Path $env:USERPROFILE '.cargo\bin\cargo.exe' }
    if (-not (Test-Path -LiteralPath $casCargo -PathType Leaf)) { throw 'The Rust toolchain is not installed.' }
    & $casCargo build --manifest-path (Join-Path $casWorkspace 'Cargo.toml') --target-dir $casBuild --release --locked --bin cas-sim
    if ($LASTEXITCODE -ne 0) { throw 'The combat core build failed.' }
    $PreparedBinary = Join-Path $casBuild 'release\cas-sim.exe'
}
$casPrepared = (Resolve-Path -LiteralPath $PreparedBinary).Path
$casHash = Get-CasSHA256 $casPrepared
$casRelative = 'runtime/' + $casHash.Substring(0, 16) + '/cas-sim.exe'
$casRuntime = Join-Path $casBin $casRelative
New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($casRuntime)) -Force | Out-Null
if (-not (Test-Path -LiteralPath $casRuntime)) {
    Copy-Item -LiteralPath $casPrepared -Destination $casRuntime
}
if ((Get-CasSHA256 $casRuntime) -ne $casHash) {
    throw 'The installed combat core did not match the completed build.'
}
$casNext = Join-Path $casBin 'core-current.json.next'
$casJSON = @{version=1; executable=$casRelative; sha256=$casHash; verified_release=[bool]$VerifiedRelease} | ConvertTo-Json
[IO.File]::WriteAllText($casNext, $casJSON, [Text.UTF8Encoding]::new($false))
Move-Item -LiteralPath $casNext -Destination $casManifest -Force
Write-Host "Installed combat core $($casHash.Substring(0, 16)). Existing game sessions can keep running."
