<#
.SYNOPSIS
    Downloads and installs the Dolby Access package via the store.rg-adguard.net
    API, then verifies it registered.

.NOTES
    Store product: DolbyLaboratories.DolbyAccess (ID: 9N0866FS04W8)
    The Store backend may return multiple historical versions for this product.
    The script selects the newest compatible Appx/MSIX package by version.
#>

$ErrorActionPreference = "Stop"
$ScriptUrl = "https://raw.githubusercontent.com/softerist/codecs/main/DolbyAccess.ps1"
$ProductUrl = "https://www.microsoft.com/store/productId/9N0866FS04W8"
$PackageName = "DolbyLaboratories.DolbyAccess"
$Rings = @("Retail", "RP", "WIF", "WIS")
$WorkDir = Join-Path $env:TEMP "DolbyAccessInstall"
$UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) " +
    "AppleWebKit/537.36 (KHTML, like Gecko) " +
    "Chrome/126.0.0.0 Safari/537.36"
)
if ($env:DOLBY_ACCESS_SCRIPT_URL) {
    $ScriptUrl = $env:DOLBY_ACCESS_SCRIPT_URL
}

try {
    $utf8NoBom = New-Object System.Text.UTF8Encoding -ArgumentList $false
    [Console]::OutputEncoding = $utf8NoBom
    $OutputEncoding = $utf8NoBom
    $script:Utf8OutputEnabled = $true
} catch {
    $script:Utf8OutputEnabled = $false
}

$script:StartedAt = Get-Date
$script:StepStartedAt = $null
$script:UseAsciiGlyphs = (
    ($env:DOLBY_ACCESS_ASCII -eq "1") -or
    ($env:TERM -eq "dumb") -or
    (-not $script:Utf8OutputEnabled)
)
$script:NoColor = ($env:NO_COLOR -eq "1") -or ($env:TERM -eq "dumb")

$script:Glyph = @{}
if ($script:UseAsciiGlyphs) {
    $script:Glyph = @{
        TL = "+"
        TR = "+"
        BL = "+"
        BR = "+"
        H = "-"
        V = "|"
        Step = "*"
        Ok = "OK"
        Fail = "X"
        Warn = "!"
        Arrow = ">"
    }
} else {
    $script:Glyph = @{
        TL = [string][char]0x250C
        TR = [string][char]0x2510
        BL = [string][char]0x2514
        BR = [string][char]0x2518
        H = [string][char]0x2500
        V = [string][char]0x2502
        Step = [string][char]0x25CF
        Ok = [string][char]0x2713
        Fail = [string][char]0x2717
        Warn = [string][char]0x26A0
        Arrow = [string][char]0x2192
    }
}

function Write-Ui {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text,
        [ConsoleColor]$Color = [ConsoleColor]::Gray
    )

    if ($script:NoColor) {
        Write-Host $Text
    } else {
        Write-Host $Text -ForegroundColor $Color
    }
}

function Get-UiWidth {
    try {
        $width = [Console]::WindowWidth - 2
        if ($width -lt 56) { return 56 }
        if ($width -gt 88) { return 88 }
        return $width
    } catch {
        return 72
    }
}

function Split-Text {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory = $true)][int]$Width
    )

    if ($Text.Length -le $Width) { return @($Text) }

    $lines = New-Object System.Collections.Generic.List[string]
    $remaining = $Text
    while ($remaining.Length -gt $Width) {
        $breakAt = $remaining.LastIndexOf(" ", $Width)
        if ($breakAt -lt 1) { $breakAt = $Width }
        $lines.Add($remaining.Substring(0, $breakAt).TrimEnd())
        $remaining = $remaining.Substring($breakAt).TrimStart()
    }

    if ($remaining.Length -gt 0) {
        $lines.Add($remaining)
    }

    return $lines.ToArray()
}

function Format-Elapsed {
    param([TimeSpan]$Duration)

    if ($Duration.TotalSeconds -ge 1) {
        return ("{0:n1}s" -f $Duration.TotalSeconds)
    }

    return ("{0:n0}ms" -f $Duration.TotalMilliseconds)
}

function Format-Bytes {
    param([long]$Bytes)

    if ($Bytes -lt 0) { return "0 B" }
    if ($Bytes -ge 1GB) { return ("{0:n2} GB" -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ("{0:n1} MB" -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ("{0:n0} KB" -f ($Bytes / 1KB)) }
    return "$Bytes B"
}

function Write-Box {
    param(
        [Parameter(Mandatory = $true)][string]$Title,
        [string[]]$Lines = @(),
        [ConsoleColor]$Color = [ConsoleColor]::Cyan
    )

    $width = Get-UiWidth
    $inner = $width - 4

    Write-Ui ""
    Write-Ui ($script:Glyph.TL + ($script:Glyph.H * ($width - 2)) + $script:Glyph.TR) $Color
    foreach ($line in (@($Title) + $Lines)) {
        foreach ($wrappedLine in (Split-Text $line $inner)) {
            $boxLine = (
                $script:Glyph.V +
                " " +
                $wrappedLine.PadRight($inner) +
                " " +
                $script:Glyph.V
            )
            Write-Ui $boxLine $Color
        }
    }
    Write-Ui ($script:Glyph.BL + ($script:Glyph.H * ($width - 2)) + $script:Glyph.BR) $Color
}

function Start-Step {
    param([Parameter(Mandatory = $true)][string]$Text)

    $script:StepStartedAt = Get-Date
    Write-Ui ("$($script:Glyph.Step) $Text") Cyan
}

function Complete-Step {
    param([Parameter(Mandatory = $true)][string]$Text)

    $elapsed = ""
    if ($script:StepStartedAt) {
        $elapsed = " (" + (Format-Elapsed ((Get-Date) - $script:StepStartedAt)) + ")"
    }
    Write-Ui ("  $($script:Glyph.Ok) $Text$elapsed") Green
}

function Write-Detail {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [ConsoleColor]$Color = [ConsoleColor]::DarkGray
    )

    Write-Ui ("  $($script:Glyph.Arrow) $Text") $Color
}

function Write-PrettyWarning {
    param([Parameter(Mandatory = $true)][string]$Text)

    Write-Ui ("  $($script:Glyph.Warn) $Text") Yellow
}

function Stop-WithMessage {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [string]$Hint
    )

    Write-Ui ("  $($script:Glyph.Fail) $Message") Red
    if ($Hint) {
        Write-Detail $Hint Yellow
    }
    exit 1
}

function Test-IsAdministrator {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal -ArgumentList $identity
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Test-CanPrompt {
    try {
        if ([Console]::IsInputRedirected) {
            return $false
        }
    } catch {
        return $false
    }

    return ($Host -and $Host.UI)
}

function Get-PowerShellHostPath {
    if ($PSHOME) {
        $candidate = Join-Path $PSHOME "powershell.exe"
        if (Test-Path -LiteralPath $candidate) { return $candidate }

        $candidate = Join-Path $PSHOME "pwsh.exe"
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }

    $command = Get-Command powershell.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    $command = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    return $null
}

function Quote-PowerShellString {
    param([Parameter(Mandatory = $true)][string]$Text)

    return "'" + ($Text -replace "'", "''") + "'"
}

function Quote-ProcessArgument {
    param([Parameter(Mandatory = $true)][string]$Text)

    return '"' + ($Text -replace '"', '\"') + '"'
}

function Add-CacheBustToUrl {
    param([Parameter(Mandatory = $true)][string]$Url)

    $separator = "?"
    if ($Url -match "\?") {
        $separator = "&"
    }

    return $Url + $separator + "cb=" + ([guid]::NewGuid().ToString("N"))
}

function Start-ElevatedRelaunch {
    $hostPath = Get-PowerShellHostPath
    if (-not $hostPath) {
        Stop-WithMessage `
            "Could not find powershell.exe or pwsh.exe for elevation." `
            "Open PowerShell as Administrator and run this installer again."
    }

    if ($PSCommandPath -and (Test-Path -LiteralPath $PSCommandPath)) {
        $arguments = (
            "-NoExit -NoProfile -ExecutionPolicy Bypass -File " +
            (Quote-ProcessArgument $PSCommandPath)
        )
    } else {
        $quotedUrl = Quote-PowerShellString (Add-CacheBustToUrl $ScriptUrl)
        $command = @(
            "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12"
            "Invoke-RestMethod $quotedUrl | Invoke-Expression"
        ) -join "; "
        $arguments = (
            "-NoExit -NoProfile -ExecutionPolicy Bypass -Command " +
            (Quote-ProcessArgument $command)
        )
    }

    try {
        Start-Process -FilePath $hostPath -ArgumentList $arguments -Verb RunAs | Out-Null
    } catch {
        Stop-WithMessage "Elevation was cancelled or failed." $_.Exception.Message
    }
}

function Ensure-Administrator {
    if (Test-IsAdministrator) {
        return
    }

    Write-PrettyWarning "Administrator rights are required to install an Appx package."
    Write-Detail "A Windows UAC prompt will open a new elevated PowerShell window." Yellow
    Write-Detail "The elevated window stays open so you can review the result." Yellow
    Write-Detail "elevated source: $ScriptUrl" DarkGray

    if (-not (Test-CanPrompt)) {
        Stop-WithMessage "Cannot prompt for elevation in this host." `
            "Run this installer from an interactive PowerShell window."
    }

    $answer = Read-Host "Allow elevation now? [allow/yes/no]"
    if ($null -eq $answer) { $answer = "" }
    $normalized = ([string]$answer).Trim().ToLowerInvariant()

    if (@("a", "allow", "y", "yes") -contains $normalized) {
        Start-ElevatedRelaunch
        exit 0
    }

    Stop-WithMessage `
        "Elevation declined." `
        "Open PowerShell as Administrator and run this installer again."
}

function Get-RgAdguardFiles {
    param(
        [string]$Ring,
        $WebSession
    )

    $body = @{ type = "url"; url = $ProductUrl; ring = $Ring; lang = "en-US" }
    $resp = Invoke-WebRequest -Uri "https://store.rg-adguard.net/api/GetFiles" `
        -Method Post -Body $body -ContentType "application/x-www-form-urlencoded" `
        -Headers $commonHeaders -UserAgent $UA -WebSession $WebSession -UseBasicParsing
    [regex]::Matches($resp.Content, '<a[^>]+href="([^"]+)"[^>]*>([^<]+)</a>') | ForEach-Object {
        [PSCustomObject]@{
            Url = [System.Net.WebUtility]::HtmlDecode($_.Groups[1].Value)
            Name = [System.Net.WebUtility]::HtmlDecode($_.Groups[2].Value.Trim())
        }
    }
}

function Get-OsArchitectureToken {
    $arch = $env:PROCESSOR_ARCHITEW6432
    if (-not $arch) {
        $arch = $env:PROCESSOR_ARCHITECTURE
    }

    if ($arch -eq "ARM64") { return "arm64" }
    if ($arch -eq "AMD64") { return "x64" }
    return "x86"
}

function Get-PackageFileName {
    param([Parameter(Mandatory = $true)][string]$Name)

    $match = [regex]::Match(
        $Name,
        '[^<>:"/\\|?*]+?\.(appx|msix)(bundle)?',
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    if ($match.Success) {
        return $match.Value
    }

    return ($Name -replace '[<>:"/\\|?*]', '_')
}

function Get-PackageVersionFromName {
    param([Parameter(Mandatory = $true)][string]$Name)

    $match = [regex]::Match($Name, '_(\d+(?:\.\d+){1,3})_')
    if (-not $match.Success) {
        return [version]"0.0.0.0"
    }

    try {
        return [version]$match.Groups[1].Value
    } catch {
        return [version]"0.0.0.0"
    }
}

function Get-ArchitectureRank {
    param([Parameter(Mandatory = $true)][string]$Name)

    if ($Name -match "bundle") { return 0 }
    if ($Name -match "_$script:Architecture`_") { return 0 }
    if ($Name -match "_neutral_") { return 1 }
    return 9
}

function Test-PackageFileName {
    param([Parameter(Mandatory = $true)][string]$Name)

    return ($Name -match '\.(appx|msix)(bundle)?(\s|$)')
}

function Select-NewestPackage {
    param([Parameter(Mandatory = $true)]$Files)

    $Files | Where-Object {
        $_.Name -match [regex]::Escape($PackageName) -and
        (Test-PackageFileName $_.Name)
    } | Sort-Object -Property @(
        @{ Expression = { Get-ArchitectureRank $_.Name }; Ascending = $true },
        @{ Expression = { Get-PackageVersionFromName $_.Name }; Descending = $true },
        @{ Expression = { $_.Name -notmatch 'bundle' }; Ascending = $true },
        @{ Expression = { $_.Name }; Descending = $true }
    ) | Select-Object -First 1
}

function Select-DependencyFiles {
    param([Parameter(Mandatory = $true)]$Files)

    $dependencyPattern = (
        'Microsoft\.VCLibs|' +
        'Microsoft\.NET\.Native|' +
        'Microsoft\.UI\.Xaml|' +
        'Microsoft\.Services\.Store'
    )

    $Files | Where-Object {
        (Test-PackageFileName $_.Name) -and
        $_.Name -match $dependencyPattern -and
        (Get-ArchitectureRank $_.Name) -lt 9
    } | Sort-Object Name -Unique
}

function Save-StoreFile {
    param([Parameter(Mandatory = $true)]$File)

    $fileName = Get-PackageFileName $File.Name
    $destFile = Join-Path $WorkDir $fileName
    $downloadFile = Join-Path $WorkDir ($fileName + ".download")
    if (Test-Path -LiteralPath $downloadFile) {
        Remove-Item -LiteralPath $downloadFile -Force
    }

    $previousProgressPreference = $ProgressPreference
    $ProgressPreference = "SilentlyContinue"
    try {
        Invoke-WebRequest -Uri $File.Url -OutFile $downloadFile -UserAgent $UA `
            -UseBasicParsing
        Move-Item -LiteralPath $downloadFile -Destination $destFile -Force
    } finally {
        $ProgressPreference = $previousProgressPreference
    }

    return Get-Item -LiteralPath $destFile
}

Write-Box "Dolby Access" @(
    "Dolby Atmos setup app installer",
    "Source: rg-adguard / Microsoft Store package"
)

Ensure-Administrator
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null

$script:Architecture = Get-OsArchitectureToken

Start-Step "Establishing rg-adguard session"
try {
    Invoke-WebRequest -Uri "https://store.rg-adguard.net/" -UserAgent $UA `
        -SessionVariable Session -UseBasicParsing | Out-Null
    Complete-Step "Connected to store.rg-adguard.net"
} catch {
    Stop-WithMessage `
        "Could not reach the rg-adguard homepage." `
        "Likely a domain-level Cloudflare challenge: $($_.Exception.Message)"
}

$commonHeaders = @{
    "Accept" = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
    "Accept-Language" = "en-US,en;q=0.9"
    "Origin" = "https://store.rg-adguard.net"
    "Referer" = "https://store.rg-adguard.net/"
}

Start-Step "Resolving Dolby Access package"

$target = $null
$targetDependencies = @()
foreach ($ring in $Rings) {
    Write-Detail "trying ring: $ring"
    try {
        $files = Get-RgAdguardFiles -Ring $ring -WebSession $Session
    } catch {
        Write-PrettyWarning "ring '$ring' request failed: $($_.Exception.Message)"
        continue
    }

    $target = Select-NewestPackage -Files $files
    if ($target) {
        $targetDependencies = @(Select-DependencyFiles -Files $files)
        Complete-Step "Found $($target.Name)"
        break
    }
}

if (-not $target) {
    Stop-WithMessage `
        "No matching package came back across rings: $($Rings -join ', ')." `
        "The API may require a browser challenge; use a manually copied package URL."
}

$targetVersion = Get-PackageVersionFromName $target.Name
$installedBefore = Get-AppxPackage -Name $PackageName -ErrorAction SilentlyContinue |
    Sort-Object Version -Descending |
    Select-Object -First 1

if ($installedBefore -and ([version]$installedBefore.Version -ge $targetVersion)) {
    Write-Box "Done" @(
        "Already installed: $($installedBefore.Name) v$($installedBefore.Version)",
        "Latest available package: v$targetVersion",
        "Elapsed: $(Format-Elapsed ((Get-Date) - $script:StartedAt))"
    ) Green
    exit 0
}

Start-Step "Downloading package"
Write-Detail (Get-PackageFileName $target.Name)
$dependencyPaths = @()
foreach ($dependency in $targetDependencies) {
    $dependencyFile = Save-StoreFile -File $dependency
    $dependencyPaths += $dependencyFile.FullName
    Write-Detail "dependency: $($dependencyFile.Name)"
}

$packageFile = Save-StoreFile -File $target
$destFile = $packageFile.FullName
Complete-Step "Saved to $destFile ($(Format-Bytes $packageFile.Length))"

Start-Step "Installing package"
try {
    if ($dependencyPaths.Count -gt 0) {
        Add-AppxPackage `
            -Path $destFile `
            -DependencyPath $dependencyPaths `
            -ForceApplicationShutdown
    } else {
        Add-AppxPackage -Path $destFile -ForceApplicationShutdown
    }
    Complete-Step "Add-AppxPackage completed"
} catch {
    Write-PrettyWarning "Add-AppxPackage failed: $($_.Exception.Message)"
    Write-PrettyWarning (
        "This often means a missing framework dependency. " +
        "Try double-clicking: $destFile"
    )
    throw
}

Start-Step "Verifying install"
$installed = $null
for ($attempt = 1; $attempt -le 5 -and -not $installed; $attempt++) {
    if ($attempt -gt 1) {
        Start-Sleep -Seconds 1
    }

    $installedPackage = Get-AppxPackage -Name $PackageName -ErrorAction SilentlyContinue |
        Sort-Object Version -Descending |
        Select-Object -First 1

    if ($installedPackage -and ([version]$installedPackage.Version -ge $targetVersion)) {
        $installed = $installedPackage
    }
}

if ($installed) {
    Complete-Step "Confirmed $($installed.Name) v$($installed.Version)"
    Write-Box "Done" @(
        "Installed: $($installed.Name) v$($installed.Version)",
        "Dolby Atmos features may still require setup in Dolby Access,",
        "compatible output hardware, and any applicable Dolby license.",
        "Elapsed: $(Format-Elapsed ((Get-Date) - $script:StartedAt))"
    ) Green
} else {
    Stop-WithMessage "Add-AppxPackage reported success, but verification failed." `
        "Get-AppxPackage does not show Dolby Access v$targetVersion or newer."
}
