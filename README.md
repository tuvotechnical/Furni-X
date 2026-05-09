# Furni-X

Furni-X is a commercial Add-in for Autodesk Inventor.
This repository contains public distribution files and release notes.

## Installation
Run the following command in PowerShell:
```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/tuvotechnical/Furni-X/main/install.ps1'))
```
