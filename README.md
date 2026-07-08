# Windows Codec Installers

Small PowerShell installers for restoring Microsoft codec packages and Dolby
codec packages on Windows 10 and Windows 11.

This repository does not host, mirror, or modify codec packages. The scripts ask
the Microsoft Store backend, through `store.rg-adguard.net`, for current package
URLs and install those packages with `Add-AppxPackage`.

## Why This Exists

This repo exists because Microsoft removed, or no longer reliably exposes, some
codec packages through the normal Microsoft Store flow on Windows 10 and
Windows 11. On affected systems, media players may fail to play common formats
even though the Store packages still exist.

The goal is a small, auditable, repeatable recovery path after a clean Windows
install.

## Quick Install

### Dolby Digital Plus Decoder OEM

```powershell
irm https://raw.githubusercontent.com/softerist/codecs/main/DolbyDigitalPlusDecoder.ps1 | iex
```

This installs only:

- `DolbyLaboratories.DolbyDigitalPlusDecoderOEM`
- Store product ID: `9nvjqjbdkn97`

### Dolby AC-4 Decoder OEM

```powershell
irm https://raw.githubusercontent.com/softerist/codecs/main/DolbyAC4Decoder.ps1 | iex
```

This installs only:

- `DolbyLaboratories.DolbyAC4DecoderOEM`
- Store product ID: `9P7646QPH1Q0`

### Dolby Vision Extensions

```powershell
irm https://raw.githubusercontent.com/softerist/codecs/main/DolbyVisionExtensions.ps1 | iex
```

This installs only:

- `DolbyLaboratories.DolbyVisionAccess`
- Store product ID: `9PLTG1LWPHLF`

Dolby Vision support still depends on compatible display hardware, GPU drivers,
HDR settings, and playback app support.

### Dolby Access

```powershell
irm https://raw.githubusercontent.com/softerist/codecs/main/DolbyAccess.ps1 | iex
```

This installs only:

- `DolbyLaboratories.DolbyAccess`
- Store product ID: `9N0866FS04W8`

Dolby Access is the setup app for Dolby Atmos for Headphones and Dolby Atmos
for Home Theater. Installing it does not grant a paid Atmos license by itself;
restore or purchase the license inside Dolby Access if your device/account
requires one.

### Microsoft Codec Extensions

```powershell
irm https://raw.githubusercontent.com/softerist/codecs/main/MicrosoftCodecExtensions.ps1 | iex
```

This installs the verified first-party Microsoft Store codec-extension set:

- AV1 Video Extension: `9MVZQVXJBQ9V`
- AVC Encoder Video Extension: `9PB0TRCNRHFX`
- HEIF Image Extension: `9PMMSR1CGPWG`
- HEVC Video Extension from Device Manufacturer: `9N4WGH0Z6VHQ`
- MPEG-2 Video Extension: `9N95Q1ZZPMH4`
- VP9 Video Extensions: `9N4D0MSMP0PT`
- Web Media Extensions: `9N5TDP8VCMHS`
- WebP Image Extension: `9PG2DK419DRG`
- Raw Image Extension: `9NCTDW2W1BH8`
- JPEG XL Image Extension: `9MZPRTH5C0TB`

After this script finishes, it reminds you that the paid `HEVC Video Extensions`
package (`9NMZLZ57R3T7`) is separate. Restore it from Microsoft Store if your
account owns it: <https://apps.microsoft.com/detail/9nmzlz57r3t7>.

## Scope

The Microsoft script is intentionally separate from the Dolby scripts.

It targets Microsoft first-party Store codec extensions that can be resolved
from product IDs. It is not every codec Windows can use. Built-in formats such
as H.264, AAC, MP3, and common container support are part of Windows and are not
installed as separate Store packages.

The script does not install the paid `HEVC Video Extensions` Store package
(`9NMZLZ57R3T7`). It uses the free/OEM `HEVC Video Extension from Device
Manufacturer` package instead.

## Elevation

If PowerShell is not already elevated, the scripts ask before opening a Windows
UAC prompt:

```text
Allow elevation now? [allow/yes/no]
```

Accepted answers are `allow`, `yes`, `a`, or `y`.

The elevated PowerShell window stays open so you can review the result. Close it
when you are done.

## What The Scripts Do

1. Open a session with `store.rg-adguard.net`.
2. Query Microsoft Store product IDs across common release rings.
3. Select matching Appx/MSIX packages.
4. Download packages to `%TEMP%`.
5. Install them with `Add-AppxPackage`.
6. Verify installation with `Get-AppxPackage`.

After installation, restart your media player. If playback still does not work,
sign out and back in, or restart Windows.

## Requirements

- Windows 10 or Windows 11
- PowerShell 5.1 or newer
- Internet access
- Administrator rights for the Appx install step

## Environment Options

- `NO_COLOR=1`: disable colored output.
- `DOLBY_DDP_ASCII=1`: force ASCII output in the Dolby script.
- `DOLBY_AC4_ASCII=1`: force ASCII output in the Dolby AC-4 script.
- `DOLBY_VISION_ASCII=1`: force ASCII output in the Dolby Vision script.
- `DOLBY_ACCESS_ASCII=1`: force ASCII output in the Dolby Access script.
- `MICROSOFT_CODECS_ASCII=1`: force ASCII output in the Microsoft script.
- `DOLBY_DDP_SCRIPT_URL`: override the Dolby elevated relaunch URL.
- `DOLBY_AC4_SCRIPT_URL`: override the Dolby AC-4 elevated relaunch URL.
- `DOLBY_VISION_SCRIPT_URL`: override the Dolby Vision elevated relaunch URL.
- `DOLBY_ACCESS_SCRIPT_URL`: override the Dolby Access elevated relaunch URL.
- `MICROSOFT_CODECS_SCRIPT_URL`: override the Microsoft elevated relaunch URL.

## References

- [Microsoft Store: Dolby Digital Plus Decoder OEM][dolby-ddp]
- [Microsoft Store: Dolby AC-4 Decoder OEM][dolby-ac4]
- [Microsoft Store: Dolby Vision Extensions][dolby-vision]
- [Microsoft Store: Dolby Access][dolby-access]
- [Microsoft Support: Windows Media Player errors][wmp-errors]
- [Microsoft Support: Media Feature Pack optional apps][media-feature-pack]
- [Microsoft Store: JPEG XL Image Extension][jpeg-xl]
- [Microsoft Store: paid HEVC Video Extensions][paid-hevc]

## Safety Notes

- Read the scripts before running `irm ... | iex`.
- The repository does not redistribute codec binaries.
- The scripts install packages returned by the Microsoft Store backend.
- This project is not affiliated with Microsoft, Dolby, or rg-adguard.

[wmp-errors]: https://support.microsoft.com/en-us/windows/apps/windowsmediaplayer/troubleshoot-windows-media-player-errors
[media-feature-pack]: https://support.microsoft.com/en-us/windows/experience/platform-variants/media-feature-pack-for-windows-10-11-n-february-2023
[dolby-ddp]: https://apps.microsoft.com/detail/9nvjqjbdkn97
[dolby-ac4]: https://apps.microsoft.com/detail/9P7646QPH1Q0
[dolby-vision]: https://apps.microsoft.com/detail/9PLTG1LWPHLF
[dolby-access]: https://apps.microsoft.com/detail/9N0866FS04W8
[jpeg-xl]: https://apps.microsoft.com/detail/9mzprth5c0tb
[paid-hevc]: https://apps.microsoft.com/detail/9nmzlz57r3t7
