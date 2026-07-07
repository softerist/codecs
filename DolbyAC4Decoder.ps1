<#
.SYNOPSIS
    Downloads and installs the Dolby AC-4 Decoder (OEM) package via the
    store.rg-adguard.net API, then verifies it registered.

.NOTES
    Store product: DolbyLaboratories.DolbyAC4DecoderOEM (ID: 9P7646QPH1Q0)
    v2: establishes a session against the homepage first and reuses its cookies
    on the API POST, since bare POSTs were getting 403'd by Cloudflare in testing.
    If the homepage GET itself fails, that's a full domain-level block (likely a
    JS/Turnstile challenge) that no header/cookie trick from a script can pass --
    the script exits early and points at the fallback instead of masking it.
#>

$ErrorActionPreference = "Stop"
$ScriptUrl  = "https://raw.githubusercontent.com/softerist/codecs/main/DolbyAC4Decoder.ps1"
$ProductUrl = "https://www.microsoft.com/store/productId/9P7646QPH1Q0"
$PackageName = "DolbyLaboratories.DolbyAC4DecoderOEM"
$Rings      = @("Retail", "RP", "WIF", "WIS")
$WorkDir    = Join-Path $env:TEMP "DolbyAC4Install"
$UA         = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) " +
    "AppleWebKit/537.36 (KHTML, like Gecko) " +
    "Chrome/126.0.0.0 Safari/537.36"
)
if ($env:DOLBY_AC4_SCRIPT_URL) {
    $ScriptUrl = $env:DOLBY_AC4_SCRIPT_URL
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
    ($env:DOLBY_AC4_ASCII -eq "1") -or
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
        H  = "-"
        V  = "|"
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
        H  = [string][char]0x2500
        V  = [string][char]0x2502
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

Write-Box "Dolby AC-4 Decoder" @(
    "OEM codec installer",
    "Source: rg-adguard / Microsoft Store package"
)

Ensure-Administrator
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null

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
    "Accept"          = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
    "Accept-Language" = "en-US,en;q=0.9"
    "Origin"          = "https://store.rg-adguard.net"
    "Referer"         = "https://store.rg-adguard.net/"
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
            Url  = [System.Net.WebUtility]::HtmlDecode($_.Groups[1].Value)
            Name = [System.Net.WebUtility]::HtmlDecode($_.Groups[2].Value.Trim())
        }
    }
}

Start-Step "Resolving Dolby AC-4 OEM package"

$target = $null
foreach ($ring in $Rings) {
    Write-Detail "trying ring: $ring"
    try {
        $files = Get-RgAdguardFiles -Ring $ring -WebSession $Session
    } catch {
        Write-PrettyWarning "ring '$ring' request failed: $($_.Exception.Message)"
        continue
    }
    $candidates = $files | Where-Object {
        $_.Name -match [regex]::Escape($PackageName) -and
        $_.Name -match '\.(appx|msix)(bundle)?(\s|$)'
    }
    if ($candidates) {
        $packageSort = @(
            @{ Expression = { $_.Name -notmatch 'bundle' }; Ascending = $true },
            @{ Expression = { $_.Name }; Ascending = $true }
        )
        $target = $candidates | Sort-Object -Property $packageSort | Select-Object -First 1
        Complete-Step "Found $($target.Name)"
        break
    }
}

if (-not $target) {
    Stop-WithMessage `
        "No matching package came back across rings: $($Rings -join ', ')." `
        "The API may require a browser challenge; use a manually copied package URL."
}

$destFile = Join-Path $WorkDir $target.Name
Start-Step "Downloading package"
Write-Detail $target.Name
$previousProgressPreference = $ProgressPreference
$ProgressPreference = "SilentlyContinue"
try {
    Invoke-WebRequest -Uri $target.Url -OutFile $destFile -UserAgent $UA -UseBasicParsing
} finally {
    $ProgressPreference = $previousProgressPreference
}
$downloadedFile = Get-Item -LiteralPath $destFile
Complete-Step "Saved to $destFile ($(Format-Bytes $downloadedFile.Length))"

Start-Step "Installing package"
try {
    Add-AppxPackage -Path $destFile -ForceApplicationShutdown
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

    $installed = Get-AppxPackage -Name $PackageName |
        Select-Object -First 1
}

if ($installed) {
    Complete-Step "Confirmed $($installed.Name) v$($installed.Version)"
    Write-Box "Done" @(
        "Installed: $($installed.Name) v$($installed.Version)",
        "Restart Media Player, or sign out and back in, for the codec to take effect.",
        "Elapsed: $(Format-Elapsed ((Get-Date) - $script:StartedAt))"
    ) Green
} else {
    Stop-WithMessage "Add-AppxPackage reported success, but verification failed." `
        "Get-AppxPackage does not show the Dolby AC-4 OEM package."
}
