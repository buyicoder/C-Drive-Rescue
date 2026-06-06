<#
.SYNOPSIS
    Admin cleanup — requires Administrator privileges.
.DESCRIPTION
    Phase 3 of C-Drive Rescue. Runs rule engine (all rules), DISM,
    cleanmgr, NVIDIA cache removal, MyDrivers backup deletion, and
    system restore point resizing.
.EXAMPLE
    Start-Process powershell.exe -Verb RunAs -ArgumentList '-File admin_cleanup.ps1'
#>

#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$SkipDISM,
    [switch]$SkipRestorePoint
)

$ErrorActionPreference = "Continue"
$LogDir = "C:\Temp\c-drive-rescue"
$LogFile = Join-Path $LogDir "admin_cleanup.log"
New-Item -ItemType Directory -Path $LogDir -Force -ErrorAction SilentlyContinue | Out-Null

function Write-Log {
    param([string]$Msg, [string]$Color="White")
    $ts = Get-Date -Format "HH:mm:ss"
    $line = "$ts $Msg"
    Write-Host $line -ForegroundColor $Color
    try { Add-Content -Path $LogFile -Value $line -Encoding UTF8 } catch {}
}

Write-Log "============================================" "Cyan"
Write-Log "  C-Drive Rescue — Admin Cleanup (Phase 3)" "Cyan"
Write-Log "  Started: $(Get-Date)" "Cyan"
Write-Log "============================================" "Cyan"

# 1. Rule Engine: ALL rules
Write-Log ""; Write-Log "--- 1. Rule Engine: All Rules ---" "Yellow"
$enginePath = Join-Path $PSScriptRoot "engine.ps1"
$ruleDir = Join-Path (Split-Path $PSScriptRoot -Parent) "..\..\..\rules"
if (Test-Path $enginePath) {
    $engineArgs = @{ Command="Clean"; RuleFilter="all"; RuleDir=$ruleDir; DryRun=$DryRun; RecycleBin=$false }
    $engineResult = & $enginePath @engineArgs
    Write-Log "Engine: $([math]::Round($engineResult.TotalGB, 2)) GB cleaned" "Green"
} else {
    Write-Log "[WARN] Engine not found — skipping rule cleanup" "Yellow"
}

# 2. DISM
if (-not $SkipDISM -and -not $DryRun) {
    Write-Log ""; Write-Log "--- 2. DISM Component Cleanup ---" "Yellow"
    Write-Log "Running DISM /StartComponentCleanup /ResetBase (may take minutes)..." "White"
    try {
        $dismResult = & dism.exe /online /cleanup-image /startcomponentcleanup /resetbase 2>&1
        $dismResult | Select-Object -Last 2 | ForEach-Object { Write-Log "DISM: $_" }
        Write-Log "DISM complete" "Green"
    } catch { Write-Log "DISM error: $_" "Red" }
} elseif ($DryRun) {
    Write-Log ""; Write-Log "--- 2. DISM (skipped in DryRun) ---" "Gray"
}

# 3. cleanmgr
if (-not $DryRun) {
    Write-Log ""; Write-Log "--- 3. Disk Cleanup (cleanmgr) ---" "Yellow"
    try { Start-Process cleanmgr.exe -ArgumentList "/autoclean" -Wait -NoNewWindow; Write-Log "cleanmgr done" "Green" } catch {}
} else {
    Write-Log ""; Write-Log "--- 3. Disk Cleanup (skipped) ---" "Gray"
}

# 4. NVIDIA
Write-Log ""; Write-Log "--- 4. NVIDIA Caches ---" "Yellow"
$nvCorp = "C:\ProgramData\NVIDIA Corporation"
if (Test-Path $nvCorp) {
    Get-ChildItem $nvCorp -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.Name -match 'Downloader|Installer|Package|Cache|Temp') {
            try {
                $sz = (Get-ChildItem $_.FullName -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
                if (-not $DryRun) { Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
                Write-Log "  $($_.Name): $([math]::Round($sz/1MB,1))MB" "Green"
            } catch {}
        }
    }
}

# 5. MyDrivers
Write-Log ""; Write-Log "--- 5. MyDrivers Backup ---" "Yellow"
if (Test-Path "C:\MyDrivers\backup") {
    $sz = 0
    try { $sz = (Get-ChildItem "C:\MyDrivers\backup" -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum } catch {}
    if ($sz -gt 0 -and -not $DryRun) { Remove-Item "C:\MyDrivers\backup" -Recurse -Force -ErrorAction SilentlyContinue }
    Write-Log "  $([math]::Round($sz/1MB,1))MB freed" "Green"
}

# 6. System Restore
if (-not $SkipRestorePoint -and -not $DryRun) {
    Write-Log ""; Write-Log "--- 6. System Restore ---" "Yellow"
    try {
        & vssadmin.exe resize shadowstorage /on=C: /for=C: /maxsize=5GB 2>&1 | Select-Object -Last 2 | ForEach-Object { Write-Log "VSS: $_" "Green" }
    } catch { Write-Log "VSS error: $_" "Red" }
}

# 7. Hibernation
Write-Log ""; Write-Log "--- 7. Hibernation ---" "Yellow"
if (Test-Path "C:\hiberfil.sys") {
    $h = Get-Item "C:\hiberfil.sys" -Force
    Write-Log "  hiberfil.sys: $([math]::Round($h.Length/1GB,2)) GB — powercfg -h off to free" "Yellow"
} else { Write-Log "  Already disabled" "Green" }

Write-Log ""
Write-Log "============================================" "Green"
Write-Log "  ADMIN CLEANUP COMPLETE" "Green"
Write-Log "  Log: $LogFile" "Gray"
Write-Log "============================================" "Green"
