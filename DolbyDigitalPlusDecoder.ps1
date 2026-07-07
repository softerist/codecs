#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Downloads and installs the Dolby Digital Plus Decoder (OEM) package via the
    store.rg-adguard.net API, then verifies it registered.

.NOTES
    Store product: DolbyLaboratories.DolbyDigitalPlusDecoderOEM (ID: 9nvjqjbdkn97)
    v2: establishes a session against the homepage first and reuses its cookies
    on the API POST, since bare POSTs were getting 403'd by Cloudflare in testing.
    If the homepage GET itself fails, that's a full domain-level block (likely a
    JS/Turnstile challenge) that no header/cookie trick from a script can pass --
    the script exits early and points at the fallback instead of masking it.
#>

$ErrorActionPreference = "Stop"
$ProductUrl = "https://www.microsoft.com/store/productId/9nvjqjbdkn97"
$Rings      = @("Retail", "RP", "WIF", "WIS")
$WorkDir    = Join-Path $env:TEMP "DolbyDDPInstall"
$UA         = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"

New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null

Write-Host "Establishing a session with rg-adguard..." -ForegroundColor Cyan
try {
    Invoke-WebRequest -Uri "https://store.rg-adguard.net/" -UserAgent $UA `
        -SessionVariable Session -UseBasicParsing | Out-Null
} catch {
    Write-Error "Can't reach the rg-adguard homepage at all from this script ($($_.Exception.Message)). That points to a domain-level Cloudflare block (likely a JS/Turnstile challenge), not just the API path -- no header or cookie trick from a plain script will get past that. Use the fallback script (install-from-url.ps1) with a link grabbed manually from a browser instead."
    exit 1
}

$commonHeaders = @{
    "Accept"          = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
    "Accept-Language" = "en-US,en;q=0.9"
    "Origin"          = "https://store.rg-adguard.net"
    "Referer"         = "https://store.rg-adguard.net/"
}

function Get-RgAdguardFiles {
    param([string]$Ring)
    $body = @{ type = "url"; url = $ProductUrl; ring = $Ring; lang = "en-US" }
    $resp = Invoke-WebRequest -Uri "https://store.rg-adguard.net/api/GetFiles" `
        -Method Post -Body $body -ContentType "application/x-www-form-urlencoded" `
        -Headers $commonHeaders -UserAgent $UA -WebSession $Session -UseBasicParsing
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
        $target = $candidates | Sort-Object { $_.Name -notmatch 'bundle' } | Select-Object -First 1
        Write-Host "  found: $($target.Name)" -ForegroundColor Green
        break
    }
}

if (-not $target) {
    Write-Error "Session established but no matching package came back across rings ($($Rings -join ', ')). The API may require something beyond cookies (a real JS challenge) -- use the fallback script instead."
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
