# Furni-X

Furni-X is a commercial Add-in for Autodesk Inventor.
This repository contains public distribution files and release notes.

## Installation
Run the following command in PowerShell:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; iex (((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/tuvotechnical/Furni-X/main/install.ps1')).TrimStart([char]0xFEFF))"
```