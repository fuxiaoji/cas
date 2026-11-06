[CmdletBinding()]
param(
    [switch] $WebOnly,
    [switch] $ReuseNodeModules,
    [switch] $NoArchive,
    [string] $NuGetSource
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$client = Join-Path $root 'client'
$manifest = Join-Path $root 'Cargo.toml'
$target = Join-Path $root 'target'

function Invoke-Checked([string] $Exe, [string[]] $Argv) {
    & $Exe @Argv
    if ($LASTEXITCODE -ne 0) { throw "$Exe exited with status $LASTEXITCODE" }
}

$cargo = (Get-Command cargo.exe -ErrorAction SilentlyContinue).Source
if (-not $cargo) { $cargo = Join-Path $env:USERPROFILE '.cargo/bin/cargo.exe' }
if (-not (Test-Path -LiteralPath $cargo)) { throw 'Install Rust with rustup, then add the wasm32-unknown-unknown target.' }

Invoke-Checked $cargo @('build', '--manifest-path', $manifest, '--target-dir', $target, '--target', 'wasm32-unknown-unknown', '--release', '--locked', '--lib')
$wasm = Join-Path $target 'wasm32-unknown-unknown/release/cas_core.wasm'
Copy-Item -LiteralPath $wasm -Destination (Join-Path $client 'public/cas_core.wasm') -Force

Push-Location -LiteralPath $client
try {
    if (-not $ReuseNodeModules) { Invoke-Checked 'npm.cmd' @('ci', '--no-audit', '--no-fund') }
    Invoke-Checked 'npm.cmd' @('run', 'build')
} finally { Pop-Location }

$web = Join-Path $client 'dist'
if ($WebOnly) {
    Write-Host "Web bundle: $web"
    return
}
if (Get-ChildItem -LiteralPath $web -Recurse -File -Filter '*.pdf') { throw 'Do not put original rulebooks in the game bundle.' }

$dotnetProject = Join-Path $root 'desktop/Cas.Windows.csproj'
$release = Join-Path $root 'release'
$run = 'CAS-Stage0-win-x64-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff')
$publish = Join-Path $target "publish/$run"
$dest = Join-Path $release $run

$restoreArgs = @('restore', $dotnetProject, '--runtime', 'win-x64', '-p:SelfContained=true', '--locked-mode')
if ($NuGetSource) { $restoreArgs += @('--source', $NuGetSource) }
Invoke-Checked 'dotnet' $restoreArgs
Invoke-Checked 'dotnet' @('publish', $dotnetProject, '--configuration', 'Release', '--runtime', 'win-x64', '--self-contained', '--no-restore', '--output', $publish, '-p:DebugType=None')

Copy-Item -LiteralPath $web -Destination (Join-Path $publish 'web') -Recurse
Copy-Item -LiteralPath (Join-Path $root 'desktop/PLAYTEST.txt') -Destination $publish
New-Item -ItemType Directory -Path $release -Force | Out-Null
if (Test-Path -LiteralPath $dest) { throw "Output already exists: $dest" }
$sourcePath = (Resolve-Path -LiteralPath $publish).Path
$releasePath = (Resolve-Path -LiteralPath $release).Path
$destPath = [IO.Path]::GetFullPath((Join-Path $releasePath $run))
$rootPrefix = $root.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
$releasePrefix = $releasePath.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
if ((Get-Item -LiteralPath $release).LinkType -or (Get-Item -LiteralPath $publish).LinkType -or
    -not $sourcePath.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase) -or
    -not $releasePath.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase) -or
    -not $destPath.StartsWith($releasePrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'The Windows release folder must be inside the CAS workspace.'
}
Move-Item -LiteralPath $sourcePath -Destination $destPath
if (-not $NoArchive) {
    $zip = Join-Path $release "$run.zip"
    Compress-Archive -LiteralPath $dest -DestinationPath $zip -CompressionLevel Optimal
    (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant() + "  $run.zip" |
        Set-Content -LiteralPath "$zip.sha256" -Encoding utf8
    Write-Host "Windows archive: $zip"
}
Write-Host "Windows app: $(Join-Path $dest 'CAS.exe')"
