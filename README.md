# Furni-X

Furni-X is a commercial Add-in for Autodesk Inventor.
This repository contains public distribution files and release notes.

## Installation
Run the following command in PowerShell:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; iex (((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/tuvotechnical/Furni-X/main/install.ps1')).TrimStart([char]0xFEFF))"
```

## Recovery from v2.1.13-v2.1.17
If Inventor does not load the FurniX tab, close Inventor and run the same installation command above in a normal PowerShell window. Administrator rights are not required.

The installer disables duplicate FurniX manifests where permitted, resets the per-user Inventor `AddInLoadRules` cache, unblocks downloaded files, installs the latest release, removes the duplicate package manifest, and writes an active manifest to `%AppData%\Autodesk\Inventor 20xx\Addins` with the absolute path to `FurniX.dll`.

Version 2.1.18 also restores the required `FurniX.AutoCAD.dll`, `Autodesk.Inventor.Interop.dll`, and `stdole.dll` files in the release package.
