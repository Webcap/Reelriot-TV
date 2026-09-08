<#
.SYNOPSIS
    Automated Release Build Script for ReelRiot TV (Flutter).

.DESCRIPTION
    Executes pre-flight checks, quality validation (flutter analyze),
    compilation for selected TV flavors and targets, and outputs organized,
    checksummed release binaries to the output directory.

.PARAMETER Flavor
    The build flavor to target ('prod' or 'dev'). Defaults to 'prod'.

.PARAMETER Target
    The build target ('Apk', 'SplitApk', 'AppBundle', 'All'). Defaults to 'Apk'.

.PARAMETER Clean
    When specified, runs 'flutter clean' before starting the build.

.PARAMETER SkipTests
    When specified, skips static analysis validation gates.

.PARAMETER OutDir
    The destination directory for release artifacts. Defaults to 'build/outputs/releases'.

.EXAMPLE
    .\scripts\release.ps1 -Flavor prod -Target Apk
    .\scripts\release.ps1 -Flavor prod -Target AppBundle
    .\scripts\release.ps1 -Flavor prod -Target All -Clean
#>

[CmdletBinding()]
param (
    [ValidateSet('prod', 'dev')]
    [string]$Flavor = 'prod',

    [ValidateSet('Apk', 'SplitApk', 'AppBundle', 'All')]
    [string]$Target = 'Apk',

    [switch]$Clean,
    [switch]$SkipTests,
    [switch]$PublishGithub,
    [switch]$SyncUpdateCenter,
    [string]$OutDir = 'build/outputs/releases'
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Resolve-Path "$ScriptDir\.."

Set-Location $ProjectRoot

Write-Host "======================================================" -ForegroundColor Cyan
Write-Host "           ReelRiot TV Release Pipeline               " -ForegroundColor Green
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " Flavor : $Flavor" -ForegroundColor Yellow
Write-Host " Target : $Target" -ForegroundColor Yellow
Write-Host " Clean  : $Clean" -ForegroundColor Yellow
Write-Host " OutDir : $OutDir" -ForegroundColor Yellow
Write-Host "======================================================"

# --- 1. Pre-flight Checks -----------------------------------------------------
Write-Host "`n[1/4] Checking prerequisites..." -ForegroundColor Cyan
if (-not (Get-Command "flutter" -ErrorAction SilentlyContinue)) {
    Write-Error "Flutter SDK was not found in PATH."
}

$EnvFile = if ($Flavor -eq 'dev') { ".env.dev" } else { ".env.prod" }
if (-not (Test-Path $EnvFile)) {
    Write-Warning "Target environment file $EnvFile was not found in workspace root."
}

$KeyProps = "android/key.properties"
if (-not (Test-Path $KeyProps)) {
    Write-Warning "android/key.properties was not found. Release build will use debug signature."
} else {
    Write-Host "-> Keystore configuration found: $KeyProps" -ForegroundColor Green
}

# --- 2. Clean and Dependencies ------------------------------------------------
if ($Clean) {
    Write-Host "`n[2/4] Cleaning workspace..." -ForegroundColor Cyan
    & flutter clean
}

Write-Host "`n[2/4] Restoring dependencies..." -ForegroundColor Cyan
& flutter pub get
if ($LASTEXITCODE -ne 0) {
    Write-Error "flutter pub get failed with exit code $LASTEXITCODE"
}

# Resolve version from pubspec.yaml
$PubspecContent = Get-Content "pubspec.yaml" -Raw
if ($PubspecContent -match 'version:\s*([^\r\n]+)') {
    $AppVersion = $matches[1].Trim()
} else {
    $AppVersion = "unknown"
}
Write-Host "-> Target Version: $AppVersion" -ForegroundColor Green

# --- 3. Quality Gate ----------------------------------------------------------
if (-not $SkipTests) {
    Write-Host "`n[3/4] Running Quality Gate (flutter analyze)..." -ForegroundColor Cyan
    & flutter analyze
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Static analysis failed. Fix issues before creating a release build."
    }
} else {
    Write-Host "`n[3/4] Quality Gate skipped (-SkipTests specified)." -ForegroundColor Yellow
}

# --- 4. Compilation -----------------------------------------------------------
Write-Host "`n[4/4] Compiling release binaries..." -ForegroundColor Cyan

$EntryPoint = if ($Flavor -eq 'dev') { "lib/main_dev.dart" } else { "lib/main_prod.dart" }
$SanitizedVersion = $AppVersion -replace '\+', '_'

# Ensure Output Directory exists
if (-not (Test-Path $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
}

$Artifacts = @()

# Build Universal APK
if ($Target -eq 'All' -or $Target -eq 'Apk') {
    Write-Host "-> Building Universal APK for $Flavor..." -ForegroundColor Yellow
    & flutter build apk --flavor $Flavor -t $EntryPoint --release
    if ($LASTEXITCODE -ne 0) { Write-Error "Universal APK build failed." }

    $SrcApk = "build/app/outputs/flutter-apk/app-$Flavor-release.apk"
    if (Test-Path $SrcApk) {
        $DestApk = "$OutDir/ReelriotTV-$Flavor-$SanitizedVersion-universal.apk"
        Copy-Item -Path $SrcApk -Destination $DestApk -Force
        $Artifacts += $DestApk
    }
}

# Build Split-per-ABI APKs
if ($Target -eq 'All' -or $Target -eq 'SplitApk') {
    Write-Host "-> Building Split-per-ABI APKs for $Flavor..." -ForegroundColor Yellow
    & flutter build apk --flavor $Flavor -t $EntryPoint --release --split-per-abi
    if ($LASTEXITCODE -ne 0) { Write-Error "Split APK build failed." }

    $Abis = @('arm64-v8a', 'armeabi-v7a', 'x86_64')
    foreach ($Abi in $Abis) {
        $SrcSplit = "build/app/outputs/flutter-apk/app-$Abi-$Flavor-release.apk"
        if (Test-Path $SrcSplit) {
            $DestSplit = "$OutDir/ReelriotTV-$Flavor-$SanitizedVersion-$Abi.apk"
            Copy-Item -Path $SrcSplit -Destination $DestSplit -Force
            $Artifacts += $DestSplit
        }
    }
}

# Build AppBundle (AAB)
if ($Target -eq 'All' -or $Target -eq 'AppBundle') {
    Write-Host "-> Building AppBundle (.aab) for $Flavor..." -ForegroundColor Yellow
    & flutter build appbundle --flavor $Flavor -t $EntryPoint --release
    if ($LASTEXITCODE -ne 0) { Write-Error "AppBundle build failed." }

    $SrcAab = "build/app/outputs/bundle/${Flavor}Release/app-$Flavor-release.aab"
    if (Test-Path $SrcAab) {
        $DestAab = "$OutDir/ReelriotTV-$Flavor-$SanitizedVersion.aab"
        Copy-Item -Path $SrcAab -Destination $DestAab -Force
        $Artifacts += $DestAab
    }
}

# --- Summary & Checksums ------------------------------------------------------
Write-Host "`n======================================================" -ForegroundColor Cyan
Write-Host "             Release Artifacts Generated              " -ForegroundColor Green
Write-Host "======================================================" -ForegroundColor Cyan

foreach ($Artifact in $Artifacts) {
    if (Test-Path $Artifact) {
        $Hash = (Get-FileHash -Path $Artifact -Algorithm SHA256).Hash
        $SizeMb = [math]::Round((Get-Item $Artifact).Length / 1MB, 2)
        $ItemName = Split-Path -Leaf $Artifact
        Write-Host "  File : $ItemName ($SizeMb MB)" -ForegroundColor White
        Write-Host "  SHA256: $Hash" -ForegroundColor DarkGray
        Write-Host "------------------------------------------------------"
    }
}

Write-Host "All done! Binaries located in $OutDir" -ForegroundColor Green

# --- 5. Publish to GitHub Releases (Optional) ---------------------------------
if ($PublishGithub) {
    Write-Host "`nPublishing GitHub Release for v$AppVersion..." -ForegroundColor Cyan
    $GhCmd = Get-Command -Name "gh" -ErrorAction SilentlyContinue
    if ($null -ne $GhCmd) {
        $Tag = "v$AppVersion"
        $Title = "ReelRiot TV v$AppVersion ($Flavor)"
        Write-Host "-> Creating release page with GitHub CLI..." -ForegroundColor Gray
        & gh release create $Tag $Artifacts --title $Title --generate-notes
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] GitHub Release published successfully for $Tag" -ForegroundColor Green
        } else {
            Write-Warning "Failed to publish GitHub release using GitHub CLI."
        }
    } else {
        Write-Warning "GitHub CLI ('gh') was not found in PATH."
        Write-Host "To publish automatically from local terminal, install gh (`winget install GitHub.cli`)." -ForegroundColor Yellow
        Write-Host "Alternatively, push tag `v$AppVersion` to trigger the GitHub Actions release workflow:" -ForegroundColor Yellow
        Write-Host "  git tag v$AppVersion" -ForegroundColor Cyan
        Write-Host "  git push origin v$AppVersion" -ForegroundColor Cyan
    }
}

# --- 6. Sync to ReelRiot Update Center (Optional) -----------------------------
if ($SyncUpdateCenter) {
    Write-Host "`nSyncing release metadata to ReelRiot Update Center..." -ForegroundColor Cyan
    & dart tools/sync_update_center.dart --platform tv --environment $Flavor --version $AppVersion
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] Update Center synced successfully." -ForegroundColor Green
    } else {
        Write-Warning "Update center sync completed with exit code $LASTEXITCODE."
    }
}
