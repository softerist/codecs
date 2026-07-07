<#
.SYNOPSIS
    Installs common Microsoft Store media and image codec extensions.

.NOTES
    Packages are resolved at runtime from Microsoft Store product IDs through
    store.rg-adguard.net. This repository does not host package binaries.
#>

$ErrorActionPreference = "Stop"
$ScriptUrl = "https://raw.githubusercontent.com/softerist/codecs/main/MicrosoftCodecExtensions.ps1"
$Rings = @("Retail", "RP", "WIF", "WIS")
$WorkDir = Join-Path $env:TEMP "MicrosoftCodecInstall"
$UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) " +
    "AppleWebKit/537.36 (KHTML, like Gecko) " +
    "Chrome/126.0.0.0 Safari/537.36"
)

if ($env:MICROSOFT_CODECS_SCRIPT_URL) {
    $ScriptUrl = $env:MICROSOFT_CODECS_SCRIPT_URL
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
    ($env:MICROSOFT_CODECS_ASCII -eq "1") -or
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

$PackageSpecs = @(
    [PSCustomObject]@{
        Title = "AV1 Video Extension"
        ProductId = "9MVZQVXJBQ9V"
        PackageName = "Microsoft.AV1VideoExtension"
    },
    [PSCustomObject]@{
        Title = "AVC Encoder Video Extension"
        ProductId = "9PB0TRCNRHFX"
        PackageName = "Microsoft.AVCEncoderVideoExtension"
    },
    [PSCustomObject]@{
        Title = "HEIF Image Extension"
        ProductId = "9PMMSR1CGPWG"
        PackageName = "Microsoft.HEIFImageExtension"
    },
    [PSCustomObject]@{
        Title = "HEVC Video Extension from Device Manufacturer"
        ProductId = "9N4WGH0Z6VHQ"
        PackageName = "Microsoft.HEVCVideoExtension"
    },
    [PSCustomObject]@{
        Title = "MPEG-2 Video Extension"
        ProductId = "9N95Q1ZZPMH4"
        PackageName = "Microsoft.MPEG2VideoExtension"
    },
    [PSCustomObject]@{
        Title = "VP9 Video Extensions"
        ProductId = "9N4D0MSMP0PT"
        PackageName = "Microsoft.VP9VideoExtensions"
    },
    [PSCustomObject]@{
        Title = "Web Media Extensions"
        ProductId = "9N5TDP8VCMHS"
        PackageName = "Microsoft.WebMediaExtensions"
    },
    [PSCustomObject]@{
        Title = "WebP Image Extension"
        ProductId = "9PG2DK419DRG"
        PackageName = "Microsoft.WebpImageExtension"
    },
    [PSCustomObject]@{
        Title = "Raw Image Extension"
        ProductId = "9NCTDW2W1BH8"
        PackageName = "Microsoft.RawImageExtension"
    },
    [PSCustomObject]@{
        Title = "JPEG XL Image Extension"
        ProductId = "9MZPRTH5C0TB"
        PackageName = "Microsoft.JPEG-XLImageExtension"
    }
)

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

    Write-PrettyWarning "Administrator rights are required to install Appx packages."
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

function Get-OsArchitectureToken {
    $arch = $env:PROCESSOR_ARCHITEW6432
    if (-not $arch) {
        $arch = $env:PROCESSOR_ARCHITECTURE
    }

    if ($arch -eq "ARM64") { return "arm64" }
    if ($arch -eq "AMD64") { return "x64" }
    return "x86"
}

function Get-RgAdguardFiles {
    param(
        [Parameter(Mandatory = $true)][string]$ProductId,
        [Parameter(Mandatory = $true)][string]$Ring,
        $WebSession
    )

    $productUrl = "https://www.microsoft.com/store/productId/$ProductId"
    $body = @{ type = "url"; url = $productUrl; ring = $Ring; lang = "en-US" }
    $resp = Invoke-WebRequest -Uri "https://store.rg-adguard.net/api/GetFiles" `
        -Method Post -Body $body -ContentType "application/x-www-form-urlencoded" `
        -Headers $script:CommonHeaders -UserAgent $UA -WebSession $WebSession `
        -UseBasicParsing

    [regex]::Matches($resp.Content, '<a[^>]+href="([^"]+)"[^>]*>([^<]+)</a>') |
        ForEach-Object {
            [PSCustomObject]@{
                Url = [System.Net.WebUtility]::HtmlDecode($_.Groups[1].Value)
                Name = [System.Net.WebUtility]::HtmlDecode($_.Groups[2].Value.Trim())
            }
        }
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
        return $null
    }

    try {
        return [version]$match.Groups[1].Value
    } catch {
        return $null
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

function Select-MainPackageFile {
    param(
        [Parameter(Mandatory = $true)]$Spec,
        [Parameter(Mandatory = $true)]$Files
    )

    $escapedName = [regex]::Escape($Spec.PackageName)
    $candidates = $Files | Where-Object {
        (Test-PackageFileName $_.Name) -and $_.Name -match $escapedName
    }

    $sort = @(
        @{ Expression = { Get-ArchitectureRank $_.Name }; Ascending = $true },
        @{ Expression = { $_.Name -notmatch 'bundle' }; Ascending = $true },
        @{ Expression = { $_.Name }; Ascending = $true }
    )
    return $candidates | Sort-Object -Property $sort | Select-Object -First 1
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
    if (Test-Path -LiteralPath $destFile) {
        return Get-Item -LiteralPath $destFile
    }

    $previousProgressPreference = $ProgressPreference
    $ProgressPreference = "SilentlyContinue"
    try {
        Invoke-WebRequest -Uri $File.Url -OutFile $destFile -UserAgent $UA `
            -UseBasicParsing
    } finally {
        $ProgressPreference = $previousProgressPreference
    }

    return Get-Item -LiteralPath $destFile
}

function Resolve-StoreFiles {
    param(
        [Parameter(Mandatory = $true)]$Spec,
        $WebSession
    )

    foreach ($ring in $Rings) {
        Write-Detail "trying ring: $ring"
        try {
            $files = Get-RgAdguardFiles `
                -ProductId $Spec.ProductId `
                -Ring $ring `
                -WebSession $WebSession
        } catch {
            Write-PrettyWarning "ring '$ring' request failed: $($_.Exception.Message)"
            continue
        }

        $target = Select-MainPackageFile -Spec $Spec -Files $files
        if ($target) {
            return [PSCustomObject]@{
                Target = $target
                Dependencies = @(Select-DependencyFiles -Files $files)
            }
        }
    }

    return $null
}

function Test-PackageInstalled {
    param(
        [Parameter(Mandatory = $true)][string]$PackageName,
        [version]$MinimumVersion
    )

    $installed = Get-AppxPackage -Name $PackageName -ErrorAction SilentlyContinue |
        Sort-Object Version -Descending |
        Select-Object -First 1

    if (-not $installed) {
        return $false
    }

    if ($MinimumVersion -and ([version]$installed.Version -lt $MinimumVersion)) {
        return $false
    }

    return $installed
}

function Wait-InstalledPackage {
    param([Parameter(Mandatory = $true)][string]$PackageName)

    for ($attempt = 1; $attempt -le 5; $attempt++) {
        if ($attempt -gt 1) {
            Start-Sleep -Seconds 1
        }

        $installed = Get-AppxPackage -Name $PackageName -ErrorAction SilentlyContinue |
            Sort-Object Version -Descending |
            Select-Object -First 1

        if ($installed) {
            return $installed
        }
    }

    return $null
}

function Install-StorePackageSpec {
    param(
        [Parameter(Mandatory = $true)]$Spec,
        $WebSession
    )

    Start-Step $Spec.Title
    $resolved = Resolve-StoreFiles -Spec $Spec -WebSession $WebSession
    if (-not $resolved) {
        Write-PrettyWarning "no package found for product ID $($Spec.ProductId)"
        return "failed"
    }

    $targetVersion = Get-PackageVersionFromName $resolved.Target.Name
    $installed = Test-PackageInstalled `
        -PackageName $Spec.PackageName `
        -MinimumVersion $targetVersion

    if ($installed) {
        Complete-Step "Already installed $($installed.Name) v$($installed.Version)"
        return "skipped"
    }

    Write-Detail (Get-PackageFileName $resolved.Target.Name)
    $dependencyPaths = @()
    foreach ($dependency in $resolved.Dependencies) {
        $dependencyFile = Save-StoreFile -File $dependency
        $dependencyPaths += $dependencyFile.FullName
        Write-Detail "dependency: $($dependencyFile.Name)"
    }

    $packageFile = Save-StoreFile -File $resolved.Target
    Complete-Step "Downloaded $($packageFile.Name) ($(Format-Bytes $packageFile.Length))"

    Start-Step "Installing $($Spec.Title)"
    try {
        if ($dependencyPaths.Count -gt 0) {
            Add-AppxPackage `
                -Path $packageFile.FullName `
                -DependencyPath $dependencyPaths `
                -ForceApplicationShutdown
        } else {
            Add-AppxPackage -Path $packageFile.FullName -ForceApplicationShutdown
        }
    } catch {
        Write-PrettyWarning "Add-AppxPackage failed: $($_.Exception.Message)"
        return "failed"
    }

    $verified = Wait-InstalledPackage -PackageName $Spec.PackageName
    if (-not $verified) {
        Write-PrettyWarning "install finished, but verification failed"
        return "failed"
    }

    Complete-Step "Installed $($verified.Name) v$($verified.Version)"
    return "installed"
}

Write-Box "Microsoft Codec Extension Installer" @(
    "Microsoft Store media and image extensions",
    "Source: rg-adguard / Microsoft Store packages"
)

Ensure-Administrator
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null

$script:Architecture = Get-OsArchitectureToken
$script:CommonHeaders = @{
    "Accept" = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
    "Accept-Language" = "en-US,en;q=0.9"
    "Origin" = "https://store.rg-adguard.net"
    "Referer" = "https://store.rg-adguard.net/"
}

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

$installedCount = 0
$skippedCount = 0
$failedPackages = New-Object System.Collections.Generic.List[string]

foreach ($spec in $PackageSpecs) {
    $result = Install-StorePackageSpec -Spec $spec -WebSession $Session
    if ($result -eq "installed") {
        $installedCount++
    } elseif ($result -eq "skipped") {
        $skippedCount++
    } else {
        $failedPackages.Add($spec.Title)
    }
}

$summary = @(
    "Installed or updated: $installedCount",
    "Already present: $skippedCount",
    "Failed: $($failedPackages.Count)",
    "Note: paid HEVC Video Extensions is not included.",
    "Restore 9NMZLZ57R3T7 from Microsoft Store if your account owns it.",
    "URL: https://apps.microsoft.com/detail/9nmzlz57r3t7",
    "Elapsed: $(Format-Elapsed ((Get-Date) - $script:StartedAt))"
)

if ($failedPackages.Count -gt 0) {
    $summary += "Failed packages: $($failedPackages -join ', ')"
    Write-Box "Completed With Warnings" $summary Yellow
    exit 1
}

Write-Box "Done" $summary Green
