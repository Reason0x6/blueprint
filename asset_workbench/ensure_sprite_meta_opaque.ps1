Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing

$imagesDir = Join-Path $PSScriptRoot "..\res\images"
$imagesDir = [System.IO.Path]::GetFullPath($imagesDir)

if (-not (Test-Path -LiteralPath $imagesDir)) {
    throw "Images directory not found: $imagesDir"
}

function Get-MetaMap {
    param([string]$Path)

    $map = @{}
    if (-not (Test-Path -LiteralPath $Path)) {
        return $map
    }

    foreach ($line in Get-Content -LiteralPath $Path) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $trim = $line.Trim()
        if ($trim.StartsWith("#")) { continue }
        $eq = $trim.IndexOf("=")
        if ($eq -lt 1) { continue }
        $key = $trim.Substring(0, $eq).Trim()
        $value = $trim.Substring($eq + 1).Trim()
        if ($key.Length -gt 0) {
            $map[$key] = $value
        }
    }
    return $map
}

function ComputeOpaqueData {
    param([string]$ImagePath)

    $bmp = [System.Drawing.Bitmap]::FromFile($ImagePath)
    try {
        $width = $bmp.Width
        $height = $bmp.Height
        $minX = $width
        $minY = $height
        $maxX = -1
        $maxY = -1

        for ($y = 0; $y -lt $height; $y++) {
            for ($x = 0; $x -lt $width; $x++) {
                $px = $bmp.GetPixel($x, $y)
                if ($px.A -eq 0) { continue }
                if ($x -lt $minX) { $minX = $x }
                if ($y -lt $minY) { $minY = $y }
                if ($x -gt $maxX) { $maxX = $x }
                if ($y -gt $maxY) { $maxY = $y }
            }
        }

        if ($maxX -lt 0 -or $maxY -lt 0) {
            return @{
                OpaqueBounds = "0:0:0:0"
                SortFootX = "0.0"
                SortFootY = "0.0"
            }
        }

        $sortFootX = ($minX + $maxX) / 2.0
        $sortFootY = [double]$maxY
        return @{
            OpaqueBounds = "$minX`:$minY`:$maxX`:$maxY"
            SortFootX = ("{0:0.###}" -f $sortFootX)
            SortFootY = ("{0:0.###}" -f $sortFootY)
        }
    } finally {
        $bmp.Dispose()
    }
}

$updatedCount = 0
$checkedCount = 0

Get-ChildItem -LiteralPath $imagesDir -Filter *.png -File | ForEach-Object {
    $checkedCount++
    $pngPath = $_.FullName
    $metaPath = [System.IO.Path]::ChangeExtension($pngPath, ".meta")
    $metaMap = Get-MetaMap -Path $metaPath

    $needBounds = -not $metaMap.ContainsKey("opaque_bounds")
    $needFootX = -not $metaMap.ContainsKey("sort_foot_x")
    $needFootY = -not $metaMap.ContainsKey("sort_foot_y")

    if (-not ($needBounds -or $needFootX -or $needFootY)) {
        return
    }

    $data = ComputeOpaqueData -ImagePath $pngPath

    if (-not (Test-Path -LiteralPath $metaPath)) {
        New-Item -Path $metaPath -ItemType File -Force | Out-Null
    }

    $append = @()
    if ($needBounds) { $append += "opaque_bounds=$($data.OpaqueBounds)" }
    if ($needFootX) { $append += "sort_foot_x=$($data.SortFootX)" }
    if ($needFootY) { $append += "sort_foot_y=$($data.SortFootY)" }

    if ($append.Count -gt 0) {
        Add-Content -LiteralPath $metaPath -Value $append
        $updatedCount++
    }
}

Write-Host "Meta opaque-foot check complete. Checked: $checkedCount, Updated: $updatedCount"
