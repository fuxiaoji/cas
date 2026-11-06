[CmdletBinding()]
param(
    [string] $Toolchain,
    [string] $GradleCache,
    [switch] $ReuseNodeModules,
    [switch] $SkipWebBuild,
    [switch] $Offline
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
if (-not $SkipWebBuild) { & (Join-Path $PSScriptRoot 'build.ps1') -WebOnly -ReuseNodeModules:$ReuseNodeModules }

$oldJava = $env:JAVA_HOME
$oldSdk = $env:ANDROID_HOME
$oldGradleCache = $env:GRADLE_USER_HOME
$gradle = (Get-Command gradle.bat -ErrorAction SilentlyContinue).Source
try {
    if ($Toolchain) {
        $kit = (Resolve-Path -LiteralPath $Toolchain).Path
        $env:JAVA_HOME = Join-Path $kit 'jdk-zulu'
        $env:ANDROID_HOME = Join-Path $kit 'sdk'
        $gradle = Join-Path $kit 'gradle/bin/gradle.bat'
    }
    if ($GradleCache) { $env:GRADLE_USER_HOME = (Resolve-Path -LiteralPath $GradleCache).Path }
    if (-not $gradle -or -not (Test-Path -LiteralPath $gradle)) { throw 'Gradle 8.11.1 was not found.' }
    if (-not $env:ANDROID_HOME -or -not (Test-Path -LiteralPath (Join-Path $env:ANDROID_HOME 'platforms/android-35'))) {
        throw 'Set ANDROID_HOME to an Android SDK with API 35 installed.'
    }
    $argv = @('--project-dir', (Join-Path $root 'android'), '--no-daemon', 'assembleDebug')
    if ($Offline) { $argv += '--offline' }
    & $gradle @argv
    if ($LASTEXITCODE -ne 0) { throw "Android build failed with status $LASTEXITCODE" }
} finally {
    $env:JAVA_HOME = $oldJava
    $env:ANDROID_HOME = $oldSdk
    $env:GRADLE_USER_HOME = $oldGradleCache
}

$apk = Join-Path $root 'android/app/build/outputs/apk/debug/app-debug.apk'
$release = Join-Path $root 'release'
New-Item -ItemType Directory -Path $release -Force | Out-Null
$name = 'CAS-Android-0.1.0-preview-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '.apk'
$out = Join-Path $release $name
Copy-Item -LiteralPath $apk -Destination $out
(Get-FileHash -LiteralPath $out -Algorithm SHA256).Hash.ToLowerInvariant() + "  $name" |
    Set-Content -LiteralPath "$out.sha256" -Encoding utf8
Write-Host "Android internal APK (debug signed): $out"
