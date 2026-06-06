<![CDATA[
<#
.SYNOPSIS
  Migrate large folders from C: to D: via Junction links
.DESCRIPTION
  Uses robocopy to move folders then creates NTFS Junction at original
  location pointing to D:. Apps continue to work normally.
  MUST be run as Administrator.
  Close target apps before running (IDEs, Doubao, JianyingPro, etc.)
.NOTES
  Use: Start-Process powershell.exe -Verb RunAs -ArgumentList '-File migrate_to_d.ps1'
#>

#Requires -RunAsAdministrator

$ErrorActionPreference = "Continue"
$script:totalBytes = 0
$script:logFile = "C:\Temp\migrate_log.txt"
New-Item -ItemType Directory -Path "C:\Temp" -Force -ErrorAction SilentlyContinue | Out-Null

function Log($msg) {
    $t = Get-Date -Format "HH:mm:ss"
    $line = "$t $msg"
    Write-Host $line
    Add-Content $script:logFile $line
}

function Move-WithJunction {
    param($SrcPath, $DstPath, $Label)

    # Check if already junction
    if (Test-Path $SrcPath) {
        $item = Get-Item $SrcPath -Force -ErrorAction SilentlyContinue
        if (($item.Attributes -band 0x400) -eq 0x400) {
            Log "[OK]   $Label - already junction -> $($item.Target)"
            return
        }
    }

    # Handle: source missing but D: has data
    if (-not (Test-Path $SrcPath)) {
        if (Test-Path $DstPath) {
            Log "[FIX]  $Label - creating junction to existing D: data"
            $parent = Split-Path $SrcPath -Parent
            if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            try {
                New-Item -ItemType Junction -Path $SrcPath -Target $DstPath -Force | Out-Null
                Log "       Junction: $SrcPath -> $DstPath"
            } catch { Log "       FAILED: $_" }
        } else {
            Log "[SKIP] $Label - neither C: nor D: found"
        }
        return
    }

    # Measure source
    $sz = 0
    try { $sz = (Get-ChildItem $SrcPath -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum } catch {}
    if ($sz -lt 10MB) {
        Log "[SKIP] $Label - only $([math]::Round($sz/1MB,1))MB"
        return
    }

    $gb = [math]::Round($sz/1GB, 2)
    Log "[MOVE] $Label : ${gb}GB -> $DstPath"

    # Ensure D: parent
    $dstParent = Split-Path $DstPath -Parent
    if (-not (Test-Path $dstParent)) {
        try { New-Item -ItemType Directory -Path $dstParent -Force | Out-Null } catch {}
    }

    try {
        # Copy to D:
        & robocopy $SrcPath $DstPath /E /COPY:DAT /R:2 /W:2 /NFL /NDL /NJH /NJS 2>&1 | Out-Null

        # Verify D: got most data
        $dstSz = 0
        try { $dstSz = (Get-ChildItem $DstPath -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum } catch {}

        if ($dstSz -gt ($sz * 0.5)) {
            # Remove source (per-file to skip locked files)
            Get-ChildItem $SrcPath -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
                try { Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue } catch {}
            }

            # Force remove residual empty tree
            try { Remove-Item $SrcPath -Recurse -Force -ErrorAction SilentlyContinue } catch {}
            Start-Sleep -Seconds 1

            # Create junction
            New-Item -ItemType Junction -Path $SrcPath -Target $DstPath -Force | Out-Null

            $remain = 0
            try { $remain = (Get-ChildItem $SrcPath -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum } catch {}
            $script:totalBytes += ($sz - $remain)
            Log "       OK: ${gb}GB freed (junction created)"
            Log "       $SrcPath -> $DstPath"
        } else {
            Log "       FAILED: D: copy too small (${dstSz} vs ${sz})"
        }
    } catch {
        Log "       FAILED: $_"
    }
}

Log "============================================"
Log "  Folder Migration - Phase 4"
Log "  Started: $(Get-Date)"
Log "  WARNING: Close target apps before running!"
Log "============================================"

# === AppData Local folders ===
$local = "$env:LOCALAPPDATA"

Log ""; Log "=== AppData\\Local Migrations ==="

# Android SDK
Move-WithJunction "$local\Android\Sdk" "D:\Android\Sdk" "Android SDK"

# Doubao
Move-WithJunction "$local\Doubao" "D:\AppData\Doubao" "Doubao AI"

# UnrealEngine
Move-WithJunction "$local\UnrealEngine" "D:\AppData\UnrealEngine" "Unreal Engine"

# JetBrains
Move-WithJunction "$local\JetBrains" "D:\AppData\JetBrains" "JetBrains IDE"

# JianyingPro
Move-WithJunction "$local\JianyingPro" "D:\AppData\JianyingPro" "JianyingPro (剪映)"

# MathWorks / MATLAB
Move-WithJunction "$local\MathWorks" "D:\AppData\MathWorks" "MathWorks/MATLAB"

# uv (Python package manager)
Move-WithJunction "$local\uv" "D:\AppData\uv" "uv Python"

# PowerToys
Move-WithJunction "$local\PowerToys" "D:\AppData\PowerToys" "PowerToys"

# Azure Functions Tools
Move-WithJunction "$local\AzureFunctionsTools" "D:\AppData\AzureFunctionsTools" "Azure Functions Tools"

# fastpdf
Move-WithJunction "$local\fastpdf_duba" "D:\AppData\fastpdf_duba" "fastpdf_duba"

# b1
Move-WithJunction "$local\b1" "D:\AppData\b1" "b1 app data"

# Kingsoft
Move-WithJunction "$local\Kingsoft" "D:\AppData\Kingsoft" "Kingsoft/WPS"

# === C: root folders ===
Log ""; Log "=== C:\\ Root Migrations ==="

# Autodesk WI (installer cache)
Move-WithJunction "C:\Autodesk\WI" "D:\Autodesk\WI" "Autodesk WI"

# Boost library
$boostDirs = Get-ChildItem "C:\local" -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^boost' }
foreach ($bd in $boostDirs) {
    $name = $bd.Name
    Move-WithJunction "C:\local\$name" "D:\Dev\$name" "Boost: $name"
}

# === WSL Migration ===
Log ""; Log "=== WSL Migration (if installed) ==="
try {
    $wslList = & wsl --list --quiet 2>&1
    if ($wslList -and $wslList.Count -gt 0) {
        Log "Found WSL distros: $($wslList -join ', ')"
        foreach ($distro in $wslList) {
            $distro = $distro.Trim()
            if ($distro -and $distro -ne '') {
                $backupFile = "D:\WSL\${distro}_backup.tar"
                Log "Exporting $distro -> $backupFile ..."
                & wsl --export $distro $backupFile 2>&1 | Out-Null
                if (Test-Path $backupFile) {
                    $backupGb = [math]::Round((Get-Item $backupFile).Length/1GB, 2)
                    Log "  Exported: ${backupGb}GB"
                    Log "  Unregistering $distro ..."
                    & wsl --unregister $distro 2>&1 | Out-Null
                    $destDir = "D:\WSL\$distro"
                    Log "  Importing to $destDir ..."
                    & wsl --import $distro $destDir $backupFile 2>&1 | Out-Null
                    Log "  WSL $distro migrated to $destDir"
                    # Clean old AppData WSL dir
                    $oldWsl = "$env:LOCALAPPDATA\wsl"
                    if (Test-Path $oldWsl) {
                        try { Remove-Item $oldWsl -Recurse -Force -ErrorAction SilentlyContinue } catch {}
                        Log "  Old WSL data removed from C:"
                    }
                } else {
                    Log "  Export FAILED for $distro"
                }
            }
        }
    } else {
        Log "No WSL distros found"
    }
} catch {
    Log "WSL migration error (WSL may not be installed): $_"
}

# Summary
Log ""
$totalGB = [math]::Round($script:totalBytes/1GB, 2)
Log "============================================"
Log "  MIGRATION COMPLETE"
Log "  Total moved to D: ${totalGB}GB"
Log "  Ended: $(Get-Date)"
Log "  Log: $script:logFile"
Log "============================================"
Log ""
Log "Verify with: wsl --list --verbose"
]]>