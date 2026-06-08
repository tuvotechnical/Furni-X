# ============================================================
#  FurniX - One-Command Installer
# ============================================================
#  Cai dat: powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; iex (((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/tuvotechnical/Furni-X/main/install.ps1')).TrimStart([char]0xFEFF))"
# ============================================================

$ErrorActionPreference = "Stop"

# --- Cau hinh ---
$repoOwner = "tuvotechnical"
$repoName = "Furni-X"
$installPath = "$env:AppData\Autodesk\ApplicationPlugins\FurniX"
$addinManifestPath = [System.IO.Path]::Combine($installPath, "FurniX.addin")
$installMode = "Current User"
$apiUrl = "https://api.github.com/repos/$repoOwner/$repoName/releases/latest"
$tempZip = "$env:TEMP\FurniX_install.zip"
$furniXAddinClassId = "24E2795D-CC26-4F30-A3FA-FB4217E8D710"

function Test-FurniXIsAdministrator {
    try {
        $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

function Get-FurniXInstallContext {
    $userInstallPath = [System.IO.Path]::Combine($env:AppData, "Autodesk", "ApplicationPlugins", "FurniX")
    $context = New-Object PSObject -Property @{
        InstallPath = $userInstallPath
        AddinPath = [System.IO.Path]::Combine($userInstallPath, "FurniX.addin")
        Mode = "Current User"
        IsAllUsers = $false
    }

    if (Test-FurniXIsAdministrator) {
        $allUsersAddins = [System.IO.Path]::Combine($env:ProgramData, "Autodesk", "Inventor Addins")
        $allUsersInstallPath = [System.IO.Path]::Combine($allUsersAddins, "FurniX")
        $context.InstallPath = $allUsersInstallPath
        $context.AddinPath = [System.IO.Path]::Combine($allUsersAddins, "FurniX.addin")
        $context.Mode = "All Users"
        $context.IsAllUsers = $true
    }

    return $context
}

function Get-FurniXAddinScanRoots {
    $roots = New-Object System.Collections.Generic.List[string]
    $roots.Add([System.IO.Path]::Combine($env:AppData, "Autodesk", "ApplicationPlugins"))
    $roots.Add([System.IO.Path]::Combine($env:ProgramData, "Autodesk", "ApplicationPlugins"))
    $roots.Add([System.IO.Path]::Combine($env:ProgramData, "Autodesk", "Inventor Addins"))

    foreach ($basePath in @(
        [System.IO.Path]::Combine($env:AppData, "Autodesk"),
        [System.IO.Path]::Combine($env:ProgramData, "Autodesk")
    )) {
        if (!(Test-Path $basePath)) { continue }
        Get-ChildItem -Path $basePath -Directory -Filter "Inventor *" -ErrorAction SilentlyContinue | ForEach-Object {
            $roots.Add([System.IO.Path]::Combine($_.FullName, "Addins"))
        }
    }

    return $roots | Where-Object { ![string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique
}

function Reset-FurniXUserAddInLoadRules {
    $backupStamp = Get-Date -Format "yyyyMMddHHmmss"
    $autodeskRoot = [System.IO.Path]::Combine($env:AppData, "Autodesk")
    if (!(Test-Path $autodeskRoot)) { return 0 }

    $resetCount = 0
    Get-ChildItem -Path $autodeskRoot -Directory -Filter "Inventor *" -ErrorAction SilentlyContinue | ForEach-Object {
        $rulesPath = [System.IO.Path]::Combine($_.FullName, "Addins", "AddInLoadRules")
        if (!(Test-Path $rulesPath)) { return }

        try {
            $backupPath = $rulesPath + ".FurniXBackup." + $backupStamp
            if (Test-Path $backupPath) {
                $backupPath = $rulesPath + ".FurniXBackup." + $backupStamp + "." + ([System.Guid]::NewGuid().ToString("N"))
            }
            Rename-Item -LiteralPath $rulesPath -NewName ([System.IO.Path]::GetFileName($backupPath)) -Force -ErrorAction Stop
            $resetCount = $resetCount + 1
            Write-Host "  -> Da reset cache block/allow cua Inventor: $rulesPath" -ForegroundColor Yellow
        }
        catch {
            Write-Host "  WARN: Khong the reset AddInLoadRules: $rulesPath" -ForegroundColor Yellow
            Write-Host "        $($_.Exception.Message)" -ForegroundColor DarkYellow
        }
    }

    return $resetCount
}

function Get-FurniXInventorPreferenceRuleFiles {
    $paths = New-Object System.Collections.Generic.List[string]

    foreach ($registryRoot in @(
        "HKLM:\SOFTWARE\Autodesk\Inventor",
        "HKLM:\SOFTWARE\WOW6432Node\Autodesk\Inventor"
    )) {
        if (!(Test-Path $registryRoot)) { continue }
        Get-ChildItem -Path $registryRoot -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $props = Get-ItemProperty -Path $_.PSPath -ErrorAction Stop
                $inventorLocation = $props.InventorLocation
                if ([string]::IsNullOrWhiteSpace($inventorLocation)) { return }

                $binDir = [System.IO.Path]::GetFullPath($inventorLocation)
                $installRoot = [System.IO.Directory]::GetParent($binDir.TrimEnd('\')).FullName
                $rulesPath = [System.IO.Path]::Combine($installRoot, "Preferences", "AddInLoadRules.xml")
                if (Test-Path $rulesPath) {
                    $paths.Add($rulesPath)
                }
            }
            catch {
            }
        }
    }

    $programFilesAutodesk = [System.IO.Path]::Combine($env:ProgramFiles, "Autodesk")
    if (Test-Path $programFilesAutodesk) {
        Get-ChildItem -Path $programFilesAutodesk -Directory -Filter "Inventor *" -ErrorAction SilentlyContinue | ForEach-Object {
            $rulesPath = [System.IO.Path]::Combine($_.FullName, "Preferences", "AddInLoadRules.xml")
            if (Test-Path $rulesPath) {
                $paths.Add($rulesPath)
            }
        }
    }

    return $paths | Where-Object { ![string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique
}

function Update-FurniXInventorTrustedPathRules {
    param([string]$TrustedPath)

    if ([string]::IsNullOrWhiteSpace($TrustedPath)) { return 0 }
    if (!(Test-FurniXIsAdministrator)) { return 0 }

    $normalizedTrustedPath = [System.IO.Path]::GetFullPath($TrustedPath).TrimEnd('\') + "\"
    $updatedCount = 0
    foreach ($rulesPath in Get-FurniXInventorPreferenceRuleFiles) {
        try {
            [xml]$xml = Get-Content -Path $rulesPath -Raw -ErrorAction Stop
            if ($xml.AddInLoadRules -eq $null) { continue }

            $alreadyAllowed = $false
            foreach ($node in $xml.AddInLoadRules.TrustedPath) {
                if ($node -eq $null) { continue }
                $policy = $node.Policy
                $value = [string]$node.InnerText
                if ([string]::Equals($policy, "Allow", [System.StringComparison]::OrdinalIgnoreCase) -and
                    [string]::Equals($value.TrimEnd('\') + "\", $normalizedTrustedPath, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $alreadyAllowed = $true
                    break
                }
            }

            if ($alreadyAllowed) { continue }

            $backupPath = $rulesPath + ".FurniXBackup." + (Get-Date -Format "yyyyMMddHHmmss")
            Copy-Item -LiteralPath $rulesPath -Destination $backupPath -Force -ErrorAction Stop

            $trustedNode = $xml.CreateElement("TrustedPath")
            $policyAttribute = $xml.CreateAttribute("Policy")
            $policyAttribute.Value = "Allow"
            [void]$trustedNode.Attributes.Append($policyAttribute)
            $trustedNode.InnerText = $normalizedTrustedPath

            $fallbackNode = $xml.AddInLoadRules.SelectSingleNode("Fallback")
            if ($fallbackNode -ne $null) {
                [void]$xml.AddInLoadRules.InsertBefore($trustedNode, $fallbackNode)
            }
            else {
                [void]$xml.AddInLoadRules.AppendChild($trustedNode)
            }

            $xml.Save($rulesPath)
            $updatedCount = $updatedCount + 1
            Write-Host "  -> Da them TrustedPath FurniX vao: $rulesPath" -ForegroundColor Green
        }
        catch {
            Write-Host "  WARN: Khong the cap nhat AddInLoadRules.xml: $rulesPath" -ForegroundColor Yellow
            Write-Host "        $($_.Exception.Message)" -ForegroundColor DarkYellow
        }
    }

    return $updatedCount
}

function Disable-DuplicateFurniXAddinManifests {
    param([string]$CanonicalAddinPath)

    $canonicalFullPath = [System.IO.Path]::GetFullPath($CanonicalAddinPath)
    $failures = New-Object System.Collections.Generic.List[string]
    foreach ($root in Get-FurniXAddinScanRoots) {
        if (!(Test-Path $root)) { continue }
        Get-ChildItem -Path $root -Filter "*.addin" -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
            $addinPath = $_.FullName
            try {
                $fullPath = [System.IO.Path]::GetFullPath($addinPath)
                $content = Get-Content -Path $fullPath -Raw -ErrorAction Stop
            }
            catch {
                return
            }
            if ([string]::Equals($fullPath, $canonicalFullPath, [System.StringComparison]::OrdinalIgnoreCase)) {
                return
            }
            if ($content.IndexOf($furniXAddinClassId, [System.StringComparison]::OrdinalIgnoreCase) -lt 0 -and
                $content.IndexOf("<DisplayName>FurniX</DisplayName>", [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
                return
            }
            try {
                $disabledPath = $fullPath + ".disabled"
                if (Test-Path $disabledPath) {
                    $disabledPath = $fullPath + ".disabled." + (Get-Date -Format "yyyyMMddHHmmss")
                }
                Rename-Item -LiteralPath $fullPath -NewName ([System.IO.Path]::GetFileName($disabledPath)) -Force -ErrorAction Stop
                Write-Host "  -> Da disable manifest FurniX trung lap: $fullPath" -ForegroundColor Yellow
            }
            catch {
                $failures.Add($fullPath)
                Write-Host "  WARN: Khong the disable manifest FurniX trung lap: $addinPath" -ForegroundColor Yellow
                Write-Host "        $($_.Exception.Message)" -ForegroundColor DarkYellow
            }
        }
    }

    if ($failures.Count -gt 0) {
        throw "Khong the disable manifest FurniX trung lap. Hay mo PowerShell bang Run as Administrator va chay lai: $($failures -join '; ')"
    }
}

function Write-FurniXAddinManifest {
    param(
        [string]$TargetPath,
        [string]$AddinPath
    )

    if ([string]::IsNullOrWhiteSpace($AddinPath)) {
        $AddinPath = [System.IO.Path]::Combine($TargetPath, "FurniX.addin")
    }
    $dllPath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($TargetPath, "FurniX.dll"))
    $dllPathXml = [System.Security.SecurityElement]::Escape($dllPath)
    $addinLines = @(
        '<?xml version="1.0" encoding="utf-8"?>',
        '<Addin Type="Standard">',
        '  <ClassId>{24E2795D-CC26-4F30-A3FA-FB4217E8D710}</ClassId>',
        '  <ClientId>{24E2795D-CC26-4F30-A3FA-FB4217E8D710}</ClientId>',
        '  <DisplayName>FurniX</DisplayName>',
        '  <Description>FurniX Add-in for Autodesk Inventor</Description>',
        "  <Assembly>$dllPathXml</Assembly>",
        '  <OSType>Win64</OSType>',
        '  <LoadAutomatically>1</LoadAutomatically>',
        '  <UserUnloadable>1</UserUnloadable>',
        '  <Hidden>0</Hidden>',
        '  <SupportedSoftwareVersionGreaterThan>16..</SupportedSoftwareVersionGreaterThan>',
        '  <DataVersion>1</DataVersion>',
        '  <LoadBehavior>0</LoadBehavior>',
        '  <UserInterfaceVersion>2</UserInterfaceVersion>',
        '</Addin>'
    )

    Disable-DuplicateFurniXAddinManifests $AddinPath
    $addinDir = [System.IO.Path]::GetDirectoryName($AddinPath)
    if (!(Test-Path $addinDir)) {
        New-Item -ItemType Directory -Path $addinDir -Force | Out-Null
    }
    [System.IO.File]::WriteAllText(
        $AddinPath,
        ($addinLines -join "`r`n"),
        [System.Text.Encoding]::UTF8)
}

# --- Banner ---
Write-Host ""
Write-Host "  ======================================" -ForegroundColor Cyan
Write-Host "          FurniX - Installer" -ForegroundColor Cyan
Write-Host "       Autodesk Inventor Add-in" -ForegroundColor Cyan
Write-Host "  ======================================" -ForegroundColor Cyan
Write-Host ""

$installContext = Get-FurniXInstallContext
$installPath = $installContext.InstallPath
$addinManifestPath = $installContext.AddinPath
$installMode = $installContext.Mode

try {
    # --- STEP 1: Lay thong tin release moi nhat ---
    Write-Host "  [1/6] Kiem tra phien ban moi nhat..." -ForegroundColor Yellow

    $headers = @{ "User-Agent" = "FurniX-Installer" }
    $release = Invoke-RestMethod -Uri $apiUrl -Headers $headers

    $version = $release.tag_name
    $releaseName = $release.name
    $asset = $release.assets | Where-Object { $_.name -like "*.zip" } | Select-Object -First 1

    if (-not $asset) {
        Write-Host "  !! Khong tim thay file cai dat trong release." -ForegroundColor Red
        Write-Host "  -> Truy cap: https://github.com/$repoOwner/$repoName/releases" -ForegroundColor Gray
        return
    }

    $downloadUrl = $asset.browser_download_url
    $fileName = $asset.name
    $fileSize = [math]::Round($asset.size / 1KB, 1)

    # Parse expected version tu tag (vd: v1.2.9 -> 1.2.9)
    $expectedVersion = $version -replace '^v', ''

    Write-Host "  -> Phien ban: $releaseName ($version)" -ForegroundColor Green
    Write-Host "  -> File:      $fileName ($fileSize KB)" -ForegroundColor Gray
    Write-Host "  -> Che do:    $installMode" -ForegroundColor Gray
    Write-Host "  -> Thu muc:   $installPath" -ForegroundColor Gray
    Write-Host "  -> Manifest:  $addinManifestPath" -ForegroundColor Gray

    $inventorWasRunning = $false
    if (Get-Process -Name "Inventor" -ErrorAction SilentlyContinue) {
        $inventorWasRunning = $true
    }

    # --- STEP 2: Dong Inventor (bat buoc) ---
    Write-Host "  [2/6] Kiem tra Inventor/AutoCAD..." -ForegroundColor Yellow
    $invProcesses = @("Inventor", "InvRaster", "InventorCoreConsole", "acad", "accoreconsole")
    $anyRunning = $false
    foreach ($procName in $invProcesses) {
        $proc = Get-Process -Name $procName -ErrorAction SilentlyContinue
        if ($proc) { $anyRunning = $true; break }
    }

    if ($anyRunning) {
        Write-Host "  -> Phan mem (Inventor hoac AutoCAD) dang chay. PHAI dong de cai dat..." -ForegroundColor Red
        Write-Host ""
        $confirm = Read-Host "     Nhap 'Y' de dong phan mem va tiep tuc, hoac 'N' de huy"
        if ($confirm -ne 'Y' -and $confirm -ne 'y') {
            Write-Host "  -> Da huy cai dat." -ForegroundColor Gray
            return
        }
        foreach ($procName in $invProcesses) {
            Stop-Process -Name $procName -Force -ErrorAction SilentlyContinue
        }
        # Doi lau hon de dam bao DLL duoc giai phong hoan toan
        Write-Host "  -> Dang doi phan mem dong hoan toan..." -ForegroundColor Gray
        Start-Sleep -Seconds 4

        # Kiem tra lai lan nua
        $stillRunning = $false
        foreach ($procName in $invProcesses) {
            $proc = Get-Process -Name $procName -ErrorAction SilentlyContinue
            if ($proc) { $stillRunning = $true; break }
        }
        if ($stillRunning) {
            Write-Host "  !! Phan mem van chua dong hoan toan. Thu dong thu cong va chay lai." -ForegroundColor Red
            return
        }
        Write-Host "  -> Da dong phan mem." -ForegroundColor Green
    } else {
        Write-Host "  -> OK (Khong chay phan mem nao)." -ForegroundColor Gray
    }

    # --- STEP 3: Tai file ---
    Write-Host "  [3/6] Dang tai $fileName..." -ForegroundColor Yellow

    if (Test-Path $tempZip) { Remove-Item $tempZip -Force }

    # Dung BitsTransfer neu co, fallback sang WebClient
    try {
        Import-Module BitsTransfer -ErrorAction Stop
        Start-BitsTransfer -Source $downloadUrl -Destination $tempZip -DisplayName "FurniX"
    }
    catch {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("User-Agent", "FurniX-Installer")
        $wc.DownloadFile($downloadUrl, $tempZip)
    }

    if (!(Test-Path $tempZip)) {
        Write-Host "  !! Tai file that bai!" -ForegroundColor Red
        return
    }
    Write-Host "  -> Tai thanh cong." -ForegroundColor Green

    # --- STEP 4: Giai nen va cai dat ---
    Write-Host "  [4/6] Cai dat vao Inventor..." -ForegroundColor Yellow

    # Tao thu muc neu chua co
    if (!(Test-Path $installPath)) {
        New-Item -ItemType Directory -Path $installPath -Force | Out-Null
    }

    # Giai nen (ghi de file cu)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($tempZip)
    foreach ($entry in $zip.Entries) {
        if ([string]::IsNullOrEmpty($entry.Name)) { continue }  # Bo qua thu muc

        # Giu nguyen cau truc thu muc trong ZIP
        $destPath = [System.IO.Path]::Combine($installPath, $entry.FullName)
        $destDir = [System.IO.Path]::GetDirectoryName($destPath)
        if (!(Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
        
        # Xoa file cu truoc neu co de tranh loi File Locked hoac ExtractToFile bi fail
        if (Test-Path $destPath) {
            try {
                Remove-Item $destPath -Force -ErrorAction Stop
            }
            catch {
                Write-Host ""
                Write-Host "  !! KHONG THE GHI DE FILE: $($entry.Name)" -ForegroundColor Red
                Write-Host "  !! File dang bi khoa boi Inventor, AutoCAD hoac process khac." -ForegroundColor Red
                Write-Host "  !! Hay dong HOAN TOAN cac phan mem va chay lai lenh cai dat." -ForegroundColor Yellow
                Write-Host ""
                $zip.Dispose()
                return
            }
        }

        try {
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $destPath, $true)
        }
        catch {
            Write-Host ""
            Write-Host "  !! LOI KHI GIAI NEN FILE: $($entry.Name)" -ForegroundColor Red
            Write-Host "  !! Chi tiet: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host ""
            $zip.Dispose()
            return
        }
    }
    $zip.Dispose()

    $trustedRuleCount = Update-FurniXInventorTrustedPathRules $installPath
    if ($installContext.IsAllUsers -and $trustedRuleCount -eq 0) {
        Write-Host "  -> TrustedPath FurniX da co san hoac khong tim thay rule file can sua." -ForegroundColor Gray
    }

    $resetRuleCount = Reset-FurniXUserAddInLoadRules
    if ($resetRuleCount -eq 0) {
        Write-Host "  -> Khong co cache AddInLoadRules theo user can reset." -ForegroundColor Gray
    }

    Write-FurniXAddinManifest $installPath $addinManifestPath
    Write-Host "  -> Da cap nhat FurniX.addin theo thu muc cai dat." -ForegroundColor Green

    # Xac minh material library bat buoc cho Change Material
    $materialPath = [System.IO.Path]::Combine($installPath, "Materials", "PTC Materials Library.adsklib")
    if (!(Test-Path $materialPath)) {
        Write-Host ""
        Write-Host "  !! THIEU PTC Materials Library sau khi cap nhat." -ForegroundColor Red
        Write-Host "  !! Hay chay lai update hoac tai ZIP release moi nhat de cai dat thu cong." -ForegroundColor Yellow
        Write-Host ""
        return
    }

    $materialInfo = Get-Item $materialPath
    if ($materialInfo.Length -lt 1MB) {
        Write-Host ""
        Write-Host "  !! PTC Materials Library bi loi hoac tai chua day du: $($materialInfo.Length) bytes." -ForegroundColor Red
        Write-Host "  !! Hay chay lai update hoac tai ZIP release moi nhat de cai dat thu cong." -ForegroundColor Yellow
        Write-Host ""
        return
    }

    try {
        $materialZip = [System.IO.Compression.ZipFile]::OpenRead($materialPath)
        $materialEntryCount = $materialZip.Entries.Count
        $materialZip.Dispose()
        if ($materialEntryCount -eq 0) {
            Write-Host ""
            Write-Host "  !! PTC Materials Library khong co noi dung hop le." -ForegroundColor Red
            Write-Host "  !! Hay chay lai update hoac tai ZIP release moi nhat de cai dat thu cong." -ForegroundColor Yellow
            Write-Host ""
            return
        }
    }
    catch {
        Write-Host ""
        Write-Host "  !! PTC Materials Library khong doc duoc: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  !! Hay chay lai update hoac tai ZIP release moi nhat de cai dat thu cong." -ForegroundColor Yellow
        Write-Host ""
        return
    }

    # Xoa file tam
    Remove-Item $tempZip -Force -ErrorAction SilentlyContinue

    Write-Host "  -> Da cai dat vao: $installPath" -ForegroundColor Green

    # --- STEP 5: Xac minh cai dat ---
    Write-Host "  [5/6] Xac minh phien ban da cai..." -ForegroundColor Yellow
    $dllPath = [System.IO.Path]::Combine($installPath, "FurniX.dll")
    if (Test-Path $dllPath) {
        $fileVer = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($dllPath)
        $installedVer = $fileVer.FileVersion
        Write-Host "  -> DLL version: $installedVer" -ForegroundColor Cyan

        # So sanh voi expected version
        if ($installedVer -like "$expectedVersion*") {
            Write-Host "  -> Version KHOP! Cai dat thanh cong." -ForegroundColor Green
        } else {
            Write-Host "  !! CANH BAO: Version DLL ($installedVer) khong khop voi release ($expectedVersion)!" -ForegroundColor Red
            Write-Host "  !! Thu dong Inventor va chay lai lenh cai dat." -ForegroundColor Yellow
        }
    } else {
        Write-Host "  !! CANH BAO: Khong tim thay FurniX.dll sau khi cai dat!" -ForegroundColor Red
    }

    # Xoa file update_skip.txt cu (reset trang thai skip)
    $skipFile = [System.IO.Path]::Combine($installPath, "update_skip.txt")
    if (Test-Path $skipFile) {
        Remove-Item $skipFile -Force -ErrorAction SilentlyContinue
        Write-Host "  -> Da reset trang thai update." -ForegroundColor Gray
    }

    # --- STEP 6: Unblock files ---
    Write-Host "  [6/6] Mo khoa file (Unblock)..." -ForegroundColor Yellow
    Get-ChildItem -Path $installPath -Recurse | Unblock-File -ErrorAction SilentlyContinue
    if (Test-Path $addinManifestPath) {
        Unblock-File -Path $addinManifestPath -ErrorAction SilentlyContinue
    }
    Write-Host "  -> Hoan tat." -ForegroundColor Green

    # --- STEP 7: Tu dong mo lai Inventor ---
    if ($inventorWasRunning) {
        Write-Host "  [7/7] Dang khoi dong lai Inventor..." -ForegroundColor Yellow
        # Inventor system alias is usually just Inventor.exe or via protocol / shell execute.
        # But starting "Inventor.exe" might require it to be in PATH. 
        # Alternatively we can start via COM or try start process "Inventor" (which works if app paths are registered).
        # We will just try Start-Process "Inventor" and handle it silently.
        Start-Process "Inventor" -ErrorAction SilentlyContinue
        Write-Host "  -> Da gui lenh khoi dong Inventor." -ForegroundColor Green
    }

    # --- HOAN TAT ---
    Write-Host ""
    Write-Host "  ======================================" -ForegroundColor Green
    Write-Host "       CAI DAT THANH CONG!" -ForegroundColor Green
    Write-Host "       Khoi dong Inventor de su dung." -ForegroundColor Green
    Write-Host "       Tab 'FurniX' se xuat hien" -ForegroundColor Green
    Write-Host "       trong Ribbon khi mo ban ve." -ForegroundColor Green
    Write-Host "  ======================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Phien ban: $version" -ForegroundColor White
    Write-Host "  Thu muc:   $installPath" -ForegroundColor Gray
    Write-Host "  Manifest:  $addinManifestPath" -ForegroundColor Gray
    Write-Host "  GitHub:    https://github.com/$repoOwner/$repoName" -ForegroundColor Cyan
    Write-Host ""
}
catch {
    Write-Host ""
    Write-Host "  !! LOI: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Thu cai dat thu cong:" -ForegroundColor Yellow
    Write-Host "  1. DONG HOAN TOAN Inventor truoc." -ForegroundColor White
    Write-Host "  2. Tai file ZIP tu: https://github.com/$repoOwner/$repoName/releases/latest" -ForegroundColor White
    Write-Host "  3. Giai nen vao: $installPath" -ForegroundColor White
    Write-Host "  4. Dam bao manifest FurniX.addin tro toi FurniX.dll trong thu muc tren." -ForegroundColor White
    Write-Host "  5. Khoi dong lai Inventor." -ForegroundColor White
    Write-Host ""

    # Don dep file tam
    if (Test-Path $tempZip) { Remove-Item $tempZip -Force -ErrorAction SilentlyContinue }
}

