<![CDATA[
<#
.SYNOPSIS
  Safe C Drive Cleanup - User-level, no admin required
.DESCRIPTION
  Cleans temp files, browser caches, IDE caches, app caches.
  All caches regenerate automatically. Safe to run anytime.
.NOTES
  Run without admin. Phase 2 of C drive cleanup.
#>

$ErrorActionPreference = "Continue"
$script:totalBytes = 0

function Write-Status($msg, $color = "White") {
    Write-Host $msg -ForegroundColor $color
}

function Clean-Dir {
    param($Path, $Label)
    if (-not (Test-Path $Path)) {
        Write-Status "[SKIP] $Label" "Gray"
        return
    }
    $sz = 0
    try { $sz = (Get-ChildItem $Path -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum } catch {}
    if ($sz -lt 1MB) {
        Write-Status "[OK]   $Label - empty" "Gray"
        return
    }
    $mb = [math]::Round($sz/1MB, 1)
    Write-Status "[DEL]  $Label - ${mb}MB" "Yellow"
    try {
        Get-ChildItem $Path -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
            try { Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue } catch {}
        }
        $script:totalBytes += $sz
        Write-Status "       Freed ${mb}MB" "Green"
    } catch {
        Write-Status "       FAILED" "Red"
    }
}

Write-Status "============================================" "Cyan"
Write-Status "  Safe Cleanup - Phase 2" "Cyan"
Write-Status "  (No admin required, all caches regenerate)" "Cyan"
Write-Status "============================================" "Cyan"

# 1. User Temp
Write-Status ""; Write-Status "--- 1. User Temp ---" "Yellow"
Clean-Dir "$env:LOCALAPPDATA\Temp" "User Temp"

# 2. Windows Temp (try)
Write-Status ""; Write-Status "--- 2. Windows Temp ---" "Yellow"
Clean-Dir "C:\Windows\Temp" "Windows Temp"

# 3. Edge Browser
Write-Status ""; Write-Status "--- 3. Edge Browser Cache ---" "Yellow"
Clean-Dir "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache\Cache_Data" "Edge Cache"
Clean-Dir "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Code Cache" "Edge CodeCache"
Clean-Dir "$env:LOCALAPPDATA\Microsoft\Edge\User Data\GrShaderCache" "Edge ShaderCache"
Clean-Dir "$env:LOCALAPPDATA\Microsoft\Edge\User Data\ShaderCache" "Edge ShaderCache2"
Clean-Dir "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\GPUCache" "Edge GPUCache"
Clean-Dir "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Service Worker\CacheStorage" "Edge SW Cache"
Clean-Dir "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Service Worker\Database" "Edge SW DB"
Clean-Dir "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Service Worker\ScriptCache" "Edge SW Script"

# 4. Chrome
Write-Status ""; Write-Status "--- 4. Chrome Browser Cache ---" "Yellow"
Clean-Dir "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache\Cache_Data" "Chrome Cache"
Clean-Dir "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Code Cache" "Chrome CodeCache"

# 5. JetBrains IDE caches (keep index)
Write-Status ""; Write-Status "--- 5. JetBrains IDE Caches ---" "Yellow"
if (Test-Path "$env:LOCALAPPDATA\JetBrains") {
    Get-ChildItem "$env:LOCALAPPDATA\JetBrains" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $cacheDir = Join-Path $_.FullName "caches"
        Clean-Dir $cacheDir "JetBrains $($_.Name) caches"
        $logDir = Join-Path $_.FullName "log"
        Clean-Dir $logDir "JetBrains $($_.Name) logs"
    }
}

# 6. JianyingPro (剪映)
Write-Status ""; Write-Status "--- 6. JianyingPro (剪映) Caches ---" "Yellow"
if (Test-Path "$env:LOCALAPPDATA\JianyingPro") {
    Get-ChildItem "$env:LOCALAPPDATA\JianyingPro" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        Get-ChildItem $_.FullName -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.Name -match '^[Cc]ache|^[Ll]ogs|^[Tt]emp|^[Tt]mp|^[Gg]pu|^[Ss]hader|^[Dd]awn|^[Cc]ode') {
                Clean-Dir $_.FullName "JianyingPro $($_.Name)"
            }
        }
    }
}

# 7. Doubao (豆包)
Write-Status ""; Write-Status "--- 7. Doubao AI Cache ---" "Yellow"
if (Test-Path "$env:LOCALAPPDATA\Doubao") {
    Get-ChildItem "$env:LOCALAPPDATA\Doubao" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.Name -match '^[Cc]ache|^[Gg]pu|^[Cc]ode|^[Ll]og|^[Tt]emp') {
            Clean-Dir $_.FullName "Doubao $($_.Name)"
        }
    }
}

# 8. Package manager caches
Write-Status ""; Write-Status "--- 8. Package Manager Caches ---" "Yellow"
Clean-Dir "$env:LOCALAPPDATA\pip\cache" "pip cache"
Clean-Dir "$env:LOCALAPPDATA\npm-cache" "npm cache"
Clean-Dir "$env:USERPROFILE\.nuget\packages" "NuGet cache"

# 9. Unity
Clean-Dir "$env:LOCALAPPDATA\Unity\cache" "Unity cache"

# 10. Teams
Write-Status ""; Write-Status "--- 9. Microsoft Teams Cache ---" "Yellow"
Clean-Dir "$env:LOCALAPPDATA\Microsoft\Teams\Cache" "Teams Cache"
Clean-Dir "$env:LOCALAPPDATA\Microsoft\Teams\Code Cache" "Teams CodeCache"

# 11. Office Telemetry
Clean-Dir "$env:LOCALAPPDATA\Microsoft\Office\OTele" "Office Telemetry"

# 12. VS Code C++ IntelliSense IPCH
Write-Status ""; Write-Status "--- 10. VS Code C++ IntelliSense Cache ---" "Yellow"
$cpptools = "$env:LOCALAPPDATA\Microsoft\vscode-cpptools"
if (Test-Path $cpptools) {
    Get-ChildItem $cpptools -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        Clean-Dir (Join-Path $_.FullName "ipch") "VS Code IPCH $($_.Name)"
    }
}

# 13. Visual Studio
Write-Status ""; Write-Status "--- 11. Visual Studio Cache ---" "Yellow"
$vsPath = "$env:LOCALAPPDATA\Microsoft\VisualStudio"
if (Test-Path $vsPath) {
    Get-ChildItem $vsPath -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.Name -match 'Cache|Temp|ComponentModelCache|BackgroundDownload|CrashDumps|Logs') {
            Clean-Dir $_.FullName "VS $($_.Name)"
        }
    }
    Clean-Dir "$vsPath\WebView2Cache" "VS WebView2Cache"
}

# Summary
Write-Status ""
$totalMB = [math]::Round($script:totalBytes/1MB, 1)
$totalGB = [math]::Round($script:totalBytes/1GB, 2)
Write-Status "============================================" "Green"
Write-Status "  SAFE CLEANUP COMPLETE" "Green"
Write-Status "  Freed: ${totalMB}MB (${totalGB}GB)" "Green"
Write-Status "============================================" "Green"
Write-Status ""
Write-Status "Next: Run admin_cleanup.ps1 with Administrator privileges" "Yellow"
]]>