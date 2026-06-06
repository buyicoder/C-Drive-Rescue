
<#
.SYNOPSIS
  Setup script for c-disk-cleaner — downloads open-source cleanup tools
.DESCRIPTION
  Downloads system-tools.rs from GitHub Releases.
  system-tools.rs: 4万+ stars Rust CLI, 35 builtin cleanup rules,
  covers system/browser/dev-tool/Chinese-app caches.
  If download fails, skill falls back to pure PowerShell.
#>

$ErrorActionPreference = "Continue"
$toolsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "tools"
New-Item -ItemType Directory -Path $toolsDir -Force -ErrorAction SilentlyContinue | Out-Null

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  C-Disk-Cleaner Tool Setup" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# =============================================
# 1. system-tools.rs
# =============================================
$stPath = Join-Path $toolsDir "system-tools.exe"
$stVersionFile = Join-Path $toolsDir "system-tools.version"

Write-Host "--- system-tools.rs ---" -ForegroundColor Yellow
Write-Host "  GitHub: https://github.com/VDHewei/system-tools.rs" -ForegroundColor Gray
Write-Host "  Stars: 40,000+ | Rust | 35 rules | 0 deps" -ForegroundColor Gray
Write-Host ""

if (Test-Path $stPath) {
    Write-Host "  [OK] system-tools.exe already installed" -ForegroundColor Green
    try {
        $ver = & $stPath --version 2>&1
        Write-Host "  Version: $ver" -ForegroundColor Green
    } catch {}
} else {
    Write-Host "  Downloading system-tools.exe from GitHub Releases..." -ForegroundColor Yellow
    $stUrl = "https://github.com/VDHewei/system-tools.rs/releases/latest/download/system-tools.exe"

    try {
        # Try Invoke-WebRequest with progress
        Invoke-WebRequest -Uri $stUrl -OutFile $stPath -UseBasicParsing -ErrorAction Stop
        if (Test-Path $stPath) {
            $size = [math]::Round((Get-Item $stPath).Length/1MB, 1)
            Write-Host "  [OK] Downloaded: ${size}MB" -ForegroundColor Green
            try {
                $ver = & $stPath --version 2>&1
                Write-Host "  Version: $ver" -ForegroundColor Green
            } catch {}
        }
    } catch {
        Write-Host "  [FAIL] Download failed: $_" -ForegroundColor Red
        Write-Host "  Manual download: $stUrl" -ForegroundColor Yellow
        Write-Host "  Skill will use PowerShell fallback instead." -ForegroundColor Yellow
    }
}

# =============================================
# 2. Check available
# =============================================
Write-Host ""
Write-Host "--- Available Engines ---" -ForegroundColor Yellow

$engines = @()

if (Test-Path $stPath) {
    $engines += "system-tools.rs (Rust CLI, 35 rules)"
}

# Dism++ check (if user has it)
$dismppPaths = @(
    "$env:USERPROFILE\Downloads\Dism++\Dism++x64.exe",
    "C:\Tools\Dism++\Dism++x64.exe",
    "$toolsDir\Dism++x64.exe"
)
foreach ($dp in $dismppPaths) {
    if (Test-Path $dp) {
        $engines += "Dism++ (at $dp)"
        break
    }
}

# Always available
$engines += "dism.exe (WinSxS component cleanup)"
$engines += "cleanmgr.exe (System disk cleanup)"
$engines += "PowerShell + robocopy (Junction migration)"

foreach ($e in $engines) {
    Write-Host "  [*] $e" -ForegroundColor Green
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Setup complete. ${engines.Count} engines available." -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
