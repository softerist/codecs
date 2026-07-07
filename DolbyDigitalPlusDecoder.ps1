#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Downloads and installs the Dolby Digital Plus Decoder (OEM) package via the
    store.rg-adguard.net API, then verifies it registered.

.NOTES
    Store product: DolbyLaboratories.DolbyDigitalPlusDecoderOEM (ID: 9nvjqjbdkn97)
    API shape (type=url&url=..&ring=..&lang=..) confirmed against several
    independent working scripts that use store.rg-adguard.net/api/GetFiles.
    Not executed end-to-end from this environment (the site blocks automated
    fetches from here) -- run it once interactively and watch the output
    before trusting it unattended.
#>

$ErrorActionPreference = "Stop"
$ProductUrl = "https://www.microsoft.com/store/productId/9nvjqjbdkn97"
$Rings      = @("Retail", "RP", "WIF", "WIS")   # tried in order until one returns a match
$WorkDir    = Join-Path $env:TEMP "DolbyDDPInstall"
$UA         = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"

New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null

function Get-RgAdguardFiles {
    param([string]$Ring)
    $body = @{ type = "url"; url = $ProductUrl; ring = $Ring; lang = "en-US" }
    $resp = Invoke-WebRequest -Uri "https://store.rg-adguard.net/api/GetFiles" `
        -Method Post -Body $body -ContentType "application/x-www-form-urlencoded" `
        -UserAgent $UA -UseBasicParsing
    [regex]::Matches($resp.Content, '<a[^>]+href="([^"]+)"[^>]*>([^<]+)</a>') | ForEach-Object {
        [PSCustomObject]@{
            Url  = [System.Net.WebUtility]::HtmlDecode($_.Groups[1].Value)
            Name = [System.Net.WebUtility]::HtmlDecode($_.Groups[2].Value.Trim())
        }
    }
}

Write-Host "Querying rg-adguard for the Dolby DDP OEM package..." -ForegroundColor Cyan

$target = $null
foreach ($ring in $Rings) {
    Write-Host "  trying ring: $ring" -ForegroundColor DarkGray
    try {
        $files = Get-RgAdguardFiles -Ring $ring
    } catch {
        Write-Warning "  ring '$ring' request failed: $($_.Exception.Message)"
        continue
    }
    $candidates = $files | Where-Object {
        $_.Name -match 'Dolby.*Decoder.*OEM' -and $_.Name -match '\.(appx|msix)(bundle)?$'
    }
    if ($candidates) {
        # prefer the bundle over a lone-architecture package if both are listed
        $target = $candidates | Sort-Object { $_.Name -notmatch 'bundle' } | Select-Object -First 1
        Write-Host "  found: $($target.Name)" -ForegroundColor Green
        break
    }
}

if (-not $target) {
    Write-Error "No DolbyDigitalPlusDecoderOEM package found across rings ($($Rings -join ', ')). rg-adguard's markup/API may have changed -- check https://store.rg-adguard.net/ manually with $ProductUrl"
    exit 1
}

$destFile = Join-Path $WorkDir $target.Name
Write-Host "Downloading $($target.Name)..." -ForegroundColor Cyan
Invoke-WebRequest -Uri $target.Url -OutFile $destFile -UserAgent $UA -UseBasicParsing

Write-Host "Installing..." -ForegroundColor Cyan
try {
    Add-AppxPackage -Path $destFile -ForceApplicationShutdown
} catch {
    Write-Warning "Add-AppxPackage failed: $($_.Exception.Message)"
    Write-Warning "Often means a missing framework dependency. Try double-clicking instead: $destFile"
    throw
}

Start-Sleep -Seconds 2
$installed = Get-AppxPackage -Name "*DolbyDigitalPlusDecoderOEM*"
if ($installed) {
    Write-Host "Confirmed installed: $($installed.Name) v$($installed.Version)" -ForegroundColor Green
    Write-Host "Restart Media Player (or sign out/in) for the codec to take effect." -ForegroundColor Yellow
} else {
    Write-Warning "Add-AppxPackage reported success but Get-AppxPackage doesn't show it -- worth a manual check."
}
