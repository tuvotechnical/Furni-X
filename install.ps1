# ============================================================
#  FurniX - One-Command Installer
# ============================================================
#  Cai dat:  powershell -c "irm https://raw.githubusercontent.com/tuvotechnical/FurniX/main/install.ps1 | iex"
# ============================================================

$ErrorActionPreference = "Stop"

# --- Cau hinh ---
$repoOwner = "tuvotechnical"
$repoName = "Furni-X"
$installPath = "$env:AppData\Autodesk\ApplicationPlugins\FurniX"
$apiUrl = "https://api.github.com/repos/$repoOwner/$repoName/releases/latest"
$tempZip = "$env:TEMP\FurniX_install.zip"

# --- Banner ---
Write-Host ""
Write-Host "  ╔══════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║                                      ║" -ForegroundColor Cyan
Write-Host "  ║        FurniX — Installer             ║" -ForegroundColor Cyan
Write-Host "  ║   Autodesk Inventor Add-in            ║" -ForegroundColor Cyan
Write-Host "  ║                                      ║" -ForegroundColor Cyan
Write-Host "  ╚══════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

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
    Write-Host "  ╔══════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "  ║                                      ║" -ForegroundColor Green
    Write-Host "  ║   CAI DAT THANH CONG!                ║" -ForegroundColor Green
    Write-Host "  ║                                      ║" -ForegroundColor Green
    Write-Host "  ║   Khoi dong Inventor de su dung.     ║" -ForegroundColor Green
    Write-Host "  ║   Tab 'FurniX' se xuat hien          ║" -ForegroundColor Green
    Write-Host "  ║   trong Ribbon khi mo ban ve.        ║" -ForegroundColor Green
    Write-Host "  ║                                      ║" -ForegroundColor Green
    Write-Host "  ╚══════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Phien ban: $version" -ForegroundColor White
    Write-Host "  Thu muc:   $installPath" -ForegroundColor Gray
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
    Write-Host "  4. Khoi dong lai Inventor." -ForegroundColor White
    Write-Host ""

    # Don dep file tam
    if (Test-Path $tempZip) { Remove-Item $tempZip -Force -ErrorAction SilentlyContinue }
}

