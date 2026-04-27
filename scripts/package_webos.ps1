# Build and Package Reelriot TV for LG webOS
# This script requires Flutter and webOS TV SDK (ares-tools) to be installed.

Write-Host "[INFO] Starting webOS build process..." -ForegroundColor Cyan

# 1. Build Flutter Web
Write-Host "[STEP 1] Building Flutter Web..." -ForegroundColor Yellow
# Build with / to satisfy Flutter's CLI validation
flutter build web --release --base-href="/"

if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Flutter build failed!" -ForegroundColor Red
    exit $LASTEXITCODE
}

# Fix paths for webOS (local file access)
Write-Host "[INFO] Patching index.html for webOS compatibility..." -ForegroundColor Cyan
$indexPath = "build/web/index.html"
if (Test-Path $indexPath) {
    # Using ./ is the safest relative path for local file loading
    (Get-Content $indexPath) -replace '<base href="/">', '<base href="./">' | Set-Content $indexPath
    Write-Host "[SUCCESS] index.html patched (base href set to ./)." -ForegroundColor Green
}

# Add a dummy webOS.js to prevent 404 errors in the simulator if it doesn't inject it
$webosJsPath = "build/web/webOS.js"
if (!(Test-Path $webosJsPath)) {
    Write-Host "[INFO] Creating dummy webOS.js..." -ForegroundColor Cyan
    "// Dummy webOS.js for simulator compatibility`nwindow.webOS = window.webOS || {};" | Set-Content $webosJsPath
}

# 2. Package for webOS
Write-Host "[STEP 2] Packaging for webOS..." -ForegroundColor Yellow
$aresPath = Get-Command ares-package -ErrorAction SilentlyContinue
if ($aresPath) {
    if (!(Test-Path "output")) {
        New-Item -ItemType Directory -Path "output"
    }
    # Using --no-minify because canvaskit.js is already minified and causes ares-package to fail
    ares-package build/web -o output --no-minify
    Write-Host "[SUCCESS] Packaging complete! Check the 'output' directory for the .ipk file." -ForegroundColor Green
} else {
    Write-Host "[WARNING] ares-package not found in PATH." -ForegroundColor Yellow
}
