# Dolby Digital Plus Decoder OEM Installer

Small PowerShell installer for the Dolby Digital Plus Decoder OEM package on
Windows 10 and Windows 11.

This repository does not host, mirror, or modify the Dolby package. The script
asks the Microsoft Store backend, through `store.rg-adguard.net`, for the current
package URL and installs that package with `Add-AppxPackage`.

## Why This Exists

This repo exists because Microsoft removed, or no longer reliably exposes, the
Dolby Digital Plus Decoder OEM package through the normal Microsoft Store flow
on Windows 10 and Windows 11. On affected systems, media players may fail to
play Dolby Digital Plus / E-AC-3 audio until the OEM decoder package is
installed.

The package still exists as a Microsoft Store package, but it can be difficult to
install directly from the Store app. This repo keeps the recovery path small,
auditable, and repeatable.

## Package

- Store product ID: `9nvjqjbdkn97`
- Package name: `DolbyLaboratories.DolbyDigitalPlusDecoderOEM`
- Current package found by the script: resolved at runtime
- Source: Microsoft Store package link resolved through `store.rg-adguard.net`

## Quick Install

Open PowerShell and run:

```powershell
irm https://raw.githubusercontent.com/softerist/codecs/main/DolbyDigitalPlusDecoder.ps1 | iex
```

If PowerShell is not already elevated, the script asks before opening a Windows
UAC prompt:

```text
Allow elevation now? [allow/yes/no]
```

Accepted answers are `allow`, `yes`, `a`, or `y`.

The elevated PowerShell window stays open so you can review the result. Close it
when you are done.

## What The Script Does

1. Opens a session with `store.rg-adguard.net`.
2. Queries the Store product ID across common release rings.
3. Selects the Dolby Digital Plus Decoder OEM Appx/MSIX package.
4. Downloads the package to `%TEMP%\DolbyDDPInstall`.
5. Installs it with `Add-AppxPackage`.
6. Verifies installation with `Get-AppxPackage`.

After installation, restart your media player. If audio still does not work,
sign out and back in, or restart Windows.

## Requirements

- Windows 10 or Windows 11
- PowerShell 5.1 or newer
- Internet access
- Administrator rights for the Appx install step

### The Codec Is Installed But Playback Still Fails

Restart the media app first. If that does not work, sign out and back in, or
restart Windows so media components reload the codec registration.

## Safety Notes

- Read the script before running `irm ... | iex`.
- The repository does not redistribute Dolby binaries.
- The script installs the package returned by the Microsoft Store backend.
- This project is not affiliated with Microsoft, Dolby, or rg-adguard.
