
<#
.SYNOPSIS
  C Drive Disk Analyzer - Read-only analysis of disk space usage
.DESCRIPTION
  Scans all drives, top C: folders, junk locations, AppData breakdown,
  WinSxS, ProgramData, hibernation, and page file.
  No admin required. No changes made.
.OUTPUTS
  Prints detailed disk usage report to console.
#>

$ErrorActionPreference = "SilentlyContinue"

function Write-Section($title) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  $title" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
}

function Get-DirSize($path) {
    if (-not (Test-Path $path)) { return 0 }
    $sz = 0
    try { $sz = (Get-ChildItem $path -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum } catch {}
    return $sz
}

# === Drive Summary ===
Write-Section "Drive Summary"
Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 } | ForEach-Object {
    $total = [math]::Round($_.Size/1GB, 1)
    $free = [math]::Round($_.FreeSpace/1GB, 1)
    $used = [math]::Round(($_.Size - $_.FreeSpace)/1GB, 1)
    $pct = [math]::Round(($_.Size - $_.FreeSpace)/$_.Size*100, 1)
    $color = if ($pct -gt 90) { "Red" } elseif ($pct -gt 80) { "Yellow" } else { "Green" }
    Write-Host "$($_.DeviceID) Total=${total}GB  Used=${used}GB  Free=${free}GB  (${pct}%)" -ForegroundColor $color
}

# === Top C: Folders ===
Write-Section "Top-Level Folders on C:"
Get-ChildItem C:\ -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $sz = Get-DirSize $_.FullName
    if ($sz -gt 0) {
        [PSCustomObject]@{ Name=$_.Name; SizeGB=[math]::Round($sz/1GB,2) }
    }
} | Sort-Object SizeGB -Descending | Format-Table -AutoSize

# === Junk Locations ===
Write-Section "Common Junk Locations"
$junk = @{
    "C:\Windows\Temp" = "Windows Temp"
    "C:\Windows\Prefetch" = "Prefetch"
    "C:\Windows\SoftwareDistribution\Download" = "Windows Update Download"
    "$env:LOCALAPPDATA\Temp" = "User Temp"
    "$env:LOCALAPPDATA\Microsoft\Windows\INetCache" = "IE Cache"
    "$env:LOCALAPPDATA\pip\cache" = "pip cache"
    "$env:LOCALAPPDATA\npm-cache" = "npm cache"
    "$env:USERPROFILE\.nuget\packages" = "NuGet cache"
}
foreach ($loc in $junk.GetEnumerator()) {
    $sz = Get-DirSize $loc.Key
    $mb = [math]::Round($sz/1MB, 1)
    Write-Host "  $($loc.Value): ${mb}MB"
}

# === AppData by User ===
Write-Section "AppData by User"
Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $user = $_.Name
    $localSz = Get-DirSize "$($_.FullName)\AppData\Local"
    $roamingSz = Get-DirSize "$($_.FullName)\AppData\Roaming"
    [PSCustomObject]@{
        User = $user
        AppDataLocalGB = [math]::Round($localSz/1GB, 2)
        AppDataRoamingGB = [math]::Round($roamingSz/1GB, 2)
        AppDataTotalGB = [math]::Round(($localSz + $roamingSz)/1GB, 2)
    }
} | Sort-Object AppDataTotalGB -Descending | Format-Table -AutoSize

# === Top AppData\Local Subfolders ===
Write-Section "Top 20 AppData\Local Subfolders (Current User)"
Get-ChildItem "$env:LOCALAPPDATA" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $sz = Get-DirSize $_.FullName
    [PSCustomObject]@{ Folder=$_.Name; SizeGB=[math]::Round($sz/1GB,2); SizeMB=[math]::Round($sz/1MB,1) }
} | Sort-Object SizeGB -Descending | Select-Object -First 20 | Format-Table -AutoSize

# === WinSxS ===
Write-Section "WinSxS Component Store"
$winsxsSz = Get-DirSize "C:\Windows\WinSxS"
Write-Host "  Size: $([math]::Round($winsxsSz/1GB,2)) GB"

# === Large ProgramData ===
Write-Section "Large ProgramData Folders (>500MB)"
Get-ChildItem "C:\ProgramData" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $sz = Get-DirSize $_.FullName
    if ($sz -gt 500MB) {
        Write-Host "  $($_.Name): $([math]::Round($sz/1GB,2)) GB"
    }
}

# === Special Files ===
Write-Section "Special Files"
if (Test-Path "C:\hiberfil.sys") {
    $h = Get-Item "C:\hiberfil.sys" -Force
    Write-Host "  hiberfil.sys: $([math]::Round($h.Length/1GB,2)) GB (Hibernation ENABLED)"
    Write-Host "    -> Run: powercfg -h off (frees this space)"
} else {
    Write-Host "  hiberfil.sys: NOT FOUND (Hibernation disabled)"
}

$pf = Get-CimInstance Win32_PageFileUsage -ErrorAction SilentlyContinue
if ($pf) {
    $pf | ForEach-Object { Write-Host "  Page file: $($_.Name) ($([math]::Round($_.CurrentUsage/1GB,2)) GB)" }
}

if (Test-Path "C:\Windows.old") {
    $sz = Get-DirSize "C:\Windows.old"
    Write-Host "  Windows.old: $([math]::Round($sz/1GB,2)) GB (can delete via Disk Cleanup)"
} else {
    Write-Host "  Windows.old: NOT FOUND"
}

# === Autodesk ===
if (Test-Path "C:\Autodesk") {
    Write-Section "Autodesk Directory"
    Get-ChildItem "C:\Autodesk" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $sz = Get-DirSize $_.FullName
        Write-Host "  $($_.Name): $([math]::Round($sz/1GB,2)) GB"
    }
}

# === MyDrivers ===
if (Test-Path "C:\MyDrivers") {
    Write-Section "MyDrivers Directory"
    $sz = Get-DirSize "C:\MyDrivers"
    Write-Host "  Total: $([math]::Round($sz/1GB,2)) GB (driver backups, safe to delete)"
}

Write-Section "Analysis Complete"
Write-Host "Run safe_cleanup.ps1 next for user-level cleanup." -ForegroundColor Yellow
