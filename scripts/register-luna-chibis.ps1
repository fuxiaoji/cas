param(
    [Parameter(Mandatory=$true)][string]$ManifestPath,
    [string]$TargetDir = "godot/assets/characters/chibis-generated-2026-11-12-v3"
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$manifestFile = Join-Path $root $ManifestPath
$catalogFile = Join-Path $root "godot/data/ships.json"
$ledgerFile = Join-Path $root "godot/assets/characters/ledger.json"
$targetRoot = Join-Path $root $TargetDir
$manifest = Get-Content -LiteralPath $manifestFile -Raw | ConvertFrom-Json
$jobs = @($manifest.jobs)
if ($jobs.Count -eq 0) { throw "Manifest has no assets." }
$ids = @($jobs | ForEach-Object identity)
if (($ids | Sort-Object -Unique).Count -ne $ids.Count) { throw "Manifest repeats an identity." }

function Get-Sha256([string]$Path) {
    (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}
function Write-Json([string]$Path, $Value) {
    $Value | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $Path -Encoding utf8
}

$catalog = Get-Content -LiteralPath $catalogFile -Raw | ConvertFrom-Json
$ledger = Get-Content -LiteralPath $ledgerFile -Raw | ConvertFrom-Json
New-Item -ItemType Directory -Force -Path $targetRoot | Out-Null
$newRecords = @()
foreach ($job in $jobs) {
    $identity = [string]$job.identity
    if ($identity -notmatch '^IBS-U-[A-Z0-9-]+$') { throw "Invalid identity: $identity" }
    $ship = @($catalog.ships | Where-Object id -eq $identity)
    if ($ship.Count -ne 1) { throw "Expected one catalogue entry for $identity; found $($ship.Count)." }
    $portrait = Join-Path $root "godot/assets/characters/portraits/$($identity.ToLowerInvariant()).webp"
    if (!(Test-Path -LiteralPath $portrait)) { throw "Missing source portrait for $($identity): $portrait" }
    $expectedPortrait = (Resolve-Path $portrait).Path
    if ([string]$job.portrait_source -ne $expectedPortrait) { throw "Portrait source does not match stable identity $identity." }
    $generated = (Resolve-Path -LiteralPath ([string]$job.generated_source)).Path
    if ($generated -eq $expectedPortrait) { throw "Generated image cannot be the source portrait for $identity." }
    $leaf = "$($identity.ToLowerInvariant()).png"
    $target = Join-Path $targetRoot $leaf
    $sourceSha = Get-Sha256 $generated
    if (Test-Path -LiteralPath $target) {
        if ((Get-Sha256 $target) -ne $sourceSha) {
            throw "Refusing to overwrite non-matching versioned asset: $target"
        }
    } else {
        Copy-Item -LiteralPath $generated -Destination $target
    }
    $portraitSha = Get-Sha256 $portrait
    if ($job.portrait_sha256 -and [string]$job.portrait_sha256 -ne $portraitSha) { throw "Portrait checksum mismatch for $identity." }
    $sha = Get-Sha256 $target
    Add-Type -AssemblyName System.Drawing
    $image = [System.Drawing.Image]::FromFile($target)
    $width = $image.Width
    $height = $image.Height
    $image.Dispose()
    $resource = "res://assets/characters/chibis-generated-2026-11-12-v3/$leaf"
    if ($ship[0].chibi_generated -and [string]$ship[0].chibi_generated -ne $resource) {
        throw "Refusing to replace an existing generated chibi mapping for $identity."
    }
    $ship[0].chibi_generated = $resource
    $ship[0].projection_status = "generated"
    $ship[0].chibi_appearance_verified_against_cas_portrait = $true
    $ship[0].chibi_user_style_accepted = $false
    $ship[0].art_scope = "local_developer_and_test_builds"
    $entry = [ordered]@{
        identity = $identity
        status = "generated"
        generator = "built-in imagegen"
        generation_version = 3
        source_portrait = "res://assets/characters/portraits/$($identity.ToLowerInvariant()).webp"
        source_portrait_absolute = $expectedPortrait
        source_portrait_sha256 = $portraitSha
        source_generated_file = $generated
        source_generated_sha256 = $sourceSha
        path = $resource
        sha256 = $sha
        width = $width
        height = $height
        prompt = [string]$job.prompt
        identity_features = @($job.identity_features)
        style_references = @($job.style_references)
        appearance_review = if ($job.appearance_review) { [string]$job.appearance_review } else { "agent_visual_checked_against_identity_portrait_and_approved_style_reference" }
        user_style_acceptance = "not_claimed"
        production_blockers = @("single static pose only", "directional and animation variants pending")
        scope = "local_developer_and_test_builds"
    }
    $newRecords += [pscustomobject]$entry
    Write-Json ($target -replace '\.png$', '.json') $entry
}

$catalog.summary.generated_chibis = (@($catalog.ships | Where-Object projection_status -eq "generated")).Count
$catalog.summary.accepted_generated_images = $catalog.summary.generated_chibis
$catalog.summary.available_chibis = (@($catalog.ships | Where-Object { $_.chibi -or $_.chibi_reference -or $_.chibi_generated })).Count
$catalog.summary.portrait_projections_pending_chibi = (@($catalog.ships | Where-Object projection_status -eq "portrait_projection")).Count
$catalog.summary | Add-Member -NotePropertyName generated_v3_chibis -NotePropertyValue $catalog.summary.generated_chibis -Force
$catalog.summary.generated_v3_chibis = $catalog.summary.generated_chibis
Write-Json $catalogFile $catalog

$ledger.chibis = @($ledger.chibis) + $newRecords
$ledger.generated_chibis = @($ledger.generated_chibis) + $newRecords
$ledger.pending_chibis = @($ledger.pending_chibis | Where-Object { $ids -notcontains [string]$_.identity })
$ledger.summary.generated_chibis = (@($ledger.generated_chibis)).Count
$ledger.summary.accepted_generated_images = $ledger.summary.generated_chibis
$ledger.summary.available_chibis = (@($catalog.ships | Where-Object { $_.chibi -or $_.chibi_reference -or $_.chibi_generated })).Count
$ledger.summary.portrait_projections_pending_chibi = (@($ledger.pending_chibis | Where-Object display_fallback -eq "portrait_projection")).Count
$ledger.summary | Add-Member -NotePropertyName generated_v3_chibis -NotePropertyValue $ledger.summary.generated_chibis -Force
$ledger.summary.generated_v3_chibis = $ledger.summary.generated_chibis
$ledger.summary.produced_generated_images = [int]$ledger.summary.generated_chibis + [int]$ledger.summary.generated_v2_candidates
Write-Json $ledgerFile $ledger

Write-Output (ConvertTo-Json -Compress ([ordered]@{ registered = $ids; count = $ids.Count; generated_v3 = $ledger.summary.generated_chibis; portrait_projection_pending = $ledger.summary.portrait_projections_pending_chibi }))
