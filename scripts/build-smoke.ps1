[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Executable,
    [string] $Evidence
)

$ErrorActionPreference = 'Stop'
$exe = (Resolve-Path -LiteralPath $Executable).Path
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
if (-not $Evidence) {
    $id = (Get-Date -Format 'yyyyMMdd-HHmmss-fff')
    $Evidence = Join-Path $root "artifacts/windows-smoke-$id.json"
}
$path = [IO.Path]::GetFullPath($Evidence)
if (Test-Path -LiteralPath $path) { throw "Evidence path already exists: $path" }
$arguments = '--smoke "' + $path + '"'
$p = Start-Process -FilePath $exe -ArgumentList $arguments -WorkingDirectory (Split-Path -LiteralPath $exe) -PassThru -WindowStyle Hidden
if (-not $p.WaitForExit(35000)) {
    Stop-Process -Id $p.Id -ErrorAction SilentlyContinue
    throw 'Desktop host did not exit within 35 seconds.'
}
if (Test-Path -LiteralPath $path) { Get-Content -LiteralPath $path -Raw -Encoding UTF8 }
if ($p.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $path)) {
    throw "Native WebView2 smoke failed (exit $($p.ExitCode))."
}
Write-Host "Windows evidence: $path"
