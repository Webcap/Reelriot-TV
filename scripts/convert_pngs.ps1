Add-Type -AssemblyName System.Drawing

function Convert-ToTruePng([string]$filePath) {
    if (-not (Test-Path $filePath)) { return }
    $resolved = (Resolve-Path $filePath).Path
    
    # Check if first 2 bytes are FF D8 (JPEG)
    $stream = [System.IO.File]::OpenRead($resolved)
    $b0 = $stream.ReadByte()
    $b1 = $stream.ReadByte()
    $stream.Close()
    $stream.Dispose()

    if ($b0 -eq 0xFF -and $b1 -eq 0xD8) {
        Write-Host "Converting JPEG disguised as PNG: $filePath" -ForegroundColor Yellow
        $tempFile = "$resolved.tmp.png"
        $img = [System.Drawing.Image]::FromFile($resolved)
        $img.Save($tempFile, [System.Drawing.Imaging.ImageFormat]::Png)
        $img.Dispose()

        Remove-Item $resolved -Force
        Move-Item $tempFile $resolved -Force
        Write-Host "-> Successfully converted to valid PNG: $filePath" -ForegroundColor Green
    } else {
        Write-Host "Already valid (or non-JPEG): $filePath" -ForegroundColor Gray
    }
}

# 1. Base asset
Convert-ToTruePng "assets/images/ReelriotTVLogo.png"

# 2. Check all PNGs in android/app/src
Get-ChildItem -Path "android/app/src" -Filter "*.png" -Recurse | ForEach-Object {
    Convert-ToTruePng $_.FullName
}
