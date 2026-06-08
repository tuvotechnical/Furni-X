# Furni-X

Furni-X is a commercial Add-in for Autodesk Inventor.
This repository contains public distribution files and release notes.

## Installation
Run the following command in PowerShell:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; iex (((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/tuvotechnical/Furni-X/main/install.ps1')).TrimStart([char]0xFEFF))"
```

## Recovery from v2.1.13-v2.1.16
If Inventor does not load the FurniX tab, close Inventor and run the same installation command above. The installer disables duplicate FurniX manifests from other Inventor add-in folders, resets the per-user Inventor `AddInLoadRules` block cache, unblocks downloaded files, installs the latest release, and writes one canonical `FurniX.addin` with the absolute DLL path.

For the strongest repair, run PowerShell as Administrator and execute the command again. In that mode the installer uses `%ProgramData%\Autodesk\Inventor Addins\FurniX`, writes the canonical manifest to `%ProgramData%\Autodesk\Inventor Addins\FurniX.addin`, and adds a FurniX trusted path to Inventor's administrator load rules.
