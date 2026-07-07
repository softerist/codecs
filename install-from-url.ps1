#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Installs the Dolby Digital Plus Decoder (OEM) package from a URL you already
    have -- e.g. grabbed manually from store.rg-adguard.net in a browser.

.PARAMETER Url
    The signed tlu.dl.delivery.mp.microsoft.com download link. These expire
    (the P1= param is a Unix timestamp) -- grab it and run this within a
    few minutes.

.EXAMPLE
    .\install-from-url.ps1 -Url "https://tlu.dl.delivery.mp.microsoft.com/..."
#>
param(
    [Parameter(Mandatory)]
    [string]$Url,
    [string]$FileName = "DolbyDigitalPlusDecoderOEM.msixbundle"
)

$ErrorActionPreference = "Stop"
$WorkDir  = Join-Path $env:TEMP "DolbyDDPInstall"
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
$destFile = Join-Path $WorkDir $FileName

Write-Host "Downloading..." -ForegroundColor Cyan
Invoke-WebRequest -Uri $Url -OutFile $destFile -UseBasicParsing

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
