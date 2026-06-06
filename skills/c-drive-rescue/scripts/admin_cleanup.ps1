<![CDATA[
<#
.SYNOPSIS
  Admin C Drive Cleanup - Requires Administrator privileges
.DESCRIPTION
  Cleans Windows Update cache, DISM component store, NVIDIA caches,
  Windows Error Reports, system logs, Defender scans, recycle bin.
  MUST be run as Administrator.
.NOTES
  Use: Start-Process powershell.exe -Verb RunAs -ArgumentList '-File admin_cleanup.ps1'
#>

#Requires -RunAsAdministrator

$ErrorActionPreference = "Continue"
$script:totalBytes = 0
$script:logFile = "C:\Temp\admin_cleanup_log.txt"
New-Item -ItemType Directory -Path "C:\Temp" -Force -ErrorAction SilentlyContinue | Out-Null

function Log($msg) {
    $t = Get-Date -Format "HH:mm:ss"
    $line = "$t $msg"
    Write-Host $line
    Add-Content $script:logFile $line
}

function Clean-Dir {
    param($Path, $Label)
    if (-not (Test-Path $Path)) { Log "[SKIP] $Label"; return }
    $sz = 0
    try { $sz = (Get-ChildItem $Path -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum } catch {}
    if ($sz -lt 1MB) { Log "[OK]   $Label - empty"; return }
    $mb = [math]::Round($sz/1MB, 1)
    Log "[DEL]  $Label - ${mb}MB"
    try {
        Get-ChildItem $Path -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
            try { Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue } catch {}
        }
        $script:totalBytes += $sz
        Log "       Freed ${mb}MB"
    } catch { Log "       FAILED" }
}

Log "============================================"
Log "  Admin Cleanup - Phase 3"
Log "  Started: $(Get-Date)"
Log "============================================"

# 1. Windows Update Cache
Log ""; Log "=== 1. Windows Update Download ==="
try {
    Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Clean-Dir "C:\Windows\SoftwareDistribution\Download" "WU Download"
    Start-Service wuauserv -ErrorAction SilentlyContinue
} catch {
    Start-Service wuauserv -ErrorAction SilentlyContinue
    Log "WU cleanup failed: $_"
}

# 2. Delivery Optimization
Log ""; Log "=== 2. Delivery Optimization ==="
Clean-Dir "C:\Windows\SoftwareDistribution\DeliveryOptimization" "DeliveryOpt"

# 3. Windows Error Reporting
Log ""; Log "=== 3. Windows Error Reports ==="
Clean-Dir "C:\ProgramData\Microsoft\Windows\WER\ReportArchive" "WER Archive"
Clean-Dir "C:\ProgramData\Microsoft\Windows\WER\ReportQueue" "WER Queue"

# 4. CBS Logs older than 30 days
Log ""; Log "=== 4. Old CBS Logs ==="
$cbsPath = "C:\Windows\Logs\CBS"
if (Test-Path $cbsPath) {
    $oldLogs = Get-ChildItem $cbsPath -Filter "*.log" -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) }
    $sz = ($oldLogs | Measure-Object -Property Length -Sum).Sum
    if ($sz -gt 1MB) {
        $mb = [math]::Round($sz/1MB, 1)
        Log "[DEL]  Old CBS logs - ${mb}MB"
        $oldLogs | Remove-Item -Force -ErrorAction SilentlyContinue
        $script:totalBytes += $sz
    } else { Log "[OK]   Old CBS logs - nothing old enough" }
}

# 5. DISM Component Cleanup
Log ""; Log "=== 5. DISM Component Cleanup ==="
Log "Running DISM /StartComponentCleanup /ResetBase (may take minutes)..."
try {
    $result = & dism.exe /online /cleanup-image /startcomponentcleanup /resetbase 2>&1
    $lastLines = $result | Select-Object -Last 3
    foreach ($l in $lastLines) { Log "DISM: $l" }
    Log "DISM completed"
} catch { Log "DISM error: $_" }

# 6. cleanmgr
Log ""; Log "=== 6. Disk Cleanup (cleanmgr) ==="
try {
    Start-Process cleanmgr.exe -ArgumentList "/autoclean" -Wait -NoNewWindow -ErrorAction SilentlyContinue
    Log "cleanmgr completed"
} catch { Log "cleanmgr error: $_" }

# 7. NVIDIA
Log ""; Log "=== 7. NVIDIA Driver Caches ==="
if (Test-Path "C:\ProgramData\NVIDIA Corporation") {
    Get-ChildItem "C:\ProgramData\NVIDIA Corporation" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.Name -match 'Downloader|Installer|Package|Cache|Temp') {
            Clean-Dir $_.FullName "NVIDIA $($_.Name)"
        }
    }
    # NVIDIA app caches
    $nvApp = "C:\ProgramData\NVIDIA Corporation\NVIDIA app"
    if (Test-Path $nvApp) {
        Get-ChildItem $nvApp -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.Name -match 'Cache|Logs|CrashDumps|Temp|Download') {
                Clean-Dir $_.FullName "NVIDIA App $($_.Name)"
            }
        }
    }
}

# 8. MyDrivers Backup
Log ""; Log "=== 8. MyDrivers Backup ==="
Clean-Dir "C:\MyDrivers\backup" "MyDrivers backup"

# 9. Windows Defender
Log ""; Log "=== 9. Windows Defender Scans ==="
Clean-Dir "C:\ProgramData\Microsoft\Windows Defender\Scans" "Defender Scans"
Clean-Dir "C:\ProgramData\Microsoft\Windows Defender\Definition Updates\Backup" "Defender Backup"

# 10. Windows Temp (admin)
Log ""; Log "=== 10. Windows Temp (Admin) ==="
Clean-Dir "C:\Windows\Temp" "Windows Temp"

# 11. Recycle Bin (all drives)
Log ""; Log "=== 11. Recycle Bin ==="
try {
    $shell = New-Object -ComObject Shell.Application
    $rb = $shell.Namespace(0xA)
    $count = $rb.Items().Count
    Log "Items in recycle bin: $count"
    if ($count -gt 0) {
        $rb.Items() | ForEach-Object {
            try { Remove-Item $_.Path -Recurse -Force -ErrorAction SilentlyContinue } catch {}
        }
        Log "Recycle bin emptied"
    }
} catch { Log "Recycle bin error: $_" }

# 12. DISM Logs
Log ""; Log "=== 12. DISM Logs ==="
Clean-Dir "C:\Windows\Logs\DISM" "DISM Logs"

# 13. System Restore shadow storage
Log ""; Log "=== 13. System Restore Shadow Storage ==="
try {
    & vssadmin.exe resize shadowstorage /on=C: /for=C: /maxsize=5GB 2>&1 | ForEach-Object { Log "VSS: $_" }
} catch { Log "VSS error: $_" }

# 14. Check hibernation
Log ""; Log "=== 14. Hibernation Status ==="
if (Test-Path "C:\hiberfil.sys") {
    $h = Get-Item "C:\hiberfil.sys" -Force
    $hgb = [math]::Round($h.Length/1GB, 2)
    Log "hiberfil.sys EXISTS: ${hgb}GB"
    Log "To disable: powercfg -h off"
} else { Log "Hibernation already disabled" }

# Summary
Log ""
$totalMB = [math]::Round($script:totalBytes/1MB, 1)
$totalGB = [math]::Round($script:totalBytes/1GB, 2)
Log "============================================"
Log "  ADMIN CLEANUP COMPLETE"
Log "  Freed: ${totalMB}MB (${totalGB}GB)"
Log "  Ended: $(Get-Date)"
Log "============================================"
]]>