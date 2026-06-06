
<#
.SYNOPSIS
    C-Drive Rescue Rule Engine — JSON-driven cleanup engine
.DESCRIPTION
    BleachBit-compatible rule format. Scans, estimates, and cleans junk files
    based on declarative JSON rule files. Supports dry-run, recycle-bin mode,
    rule filtering, and i18n output.

    Rule format (BleachBit compatible):
    [
      ["display_name", "path_template", "type", recycle_bool, "description"],
      ...
    ]

    Types: "dir" (delete entire directory), "file" (delete single file),
           "glob" (delete files matching pattern inside directory)

.PARAMETER Command
    "Scan" - load rules, measure sizes, return report
    "Clean" - load rules, delete files, return report
.PARAMETER RuleDir
    Path to rules/ directory (default: ../rules relative to this script)
.PARAMETER RuleFilter
    Comma-separated category filter: "system,browser,dev_tools,cn_apps,game,creative"
    Also supports "safe" (safe rules only), "all" (default)
.PARAMETER DryRun
    If set, Clean command measures but does not delete
.PARAMETER RecycleBin
    If set, moves files to recycle bin instead of permanent delete
.PARAMETER Lang
    Language code: "zh_cn" or "en_us" (default: "zh_cn")
.EXAMPLE
    .\engine.ps1 -Command Scan
    .\engine.ps1 -Command Clean -DryRun
    .\engine.ps1 -Command Clean -RuleFilter "system,browser"
    .\engine.ps1 -Command Clean -RuleFilter "safe" -RecycleBin
#>

[CmdletBinding()]
param(
    [ValidateSet("Scan", "Clean")]
    [string]$Command = "Scan",

    [string]$RuleDir = $null,

    [string]$RuleFilter = "all",

    [switch]$DryRun,

    [switch]$RecycleBin,

    [ValidateSet("zh_cn", "en_us")]
    [string]$Lang = "zh_cn",

    [string]$TargetDrive = "C:"
)

$ErrorActionPreference = "Continue"

# ---- Path Setup ----
if (-not $RuleDir) {
    $RuleDir = Join-Path (Split-Path $PSScriptRoot -Parent) "rules"
    if (-not (Test-Path $RuleDir)) {
        $RuleDir = Join-Path $PSScriptRoot "..\..\..\rules"
    }
}
$Script:RuleDir = $RuleDir
$Script:TargetDrive = $TargetDrive

$Script:LogDir = "C:\Temp\c-drive-rescue"
$Script:LogFile = Join-Path $Script:LogDir "engine.log"
New-Item -ItemType Directory -Path $Script:LogDir -Force -ErrorAction SilentlyContinue | Out-Null

# ---- i18n ----
$Script:I18n = @{}
$i18nDir = Join-Path (Split-Path $PSScriptRoot -Parent) "i18n"
if (-not (Test-Path $i18nDir)) {
    $i18nDir = Join-Path $PSScriptRoot "..\..\..\i18n"
}
$i18nFile = Join-Path $i18nDir "$Lang.json"
if (Test-Path $i18nFile) {
    try {
        $Script:I18n = Get-Content $i18nFile -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
    } catch {}
}

function _t($key) {
    if ($Script:I18n.ContainsKey($key)) { return $Script:I18n[$key] }
    return $key
}

# ---- Logging ----
function Write-Log {
    param([string]$Level = "INFO", [string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "$ts [$Level] $Message"
    Write-Host $line
    try { Add-Content -Path $Script:LogFile -Value $line -Encoding UTF8 } catch {}
}

# ---- Rule Engine Core ----
$Script:Rules = @()
$Script:RuleFiles = @()
$Script:TotalScannedBytes = 0
$Script:TotalCleanedBytes = 0
$Script:ErrorSamples = @{}  # Sampled error suppression (mimics c_cleaner_plus)

# ---- Junction Detection ----
function Test-IsReparsePoint {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $false }
    try {
        $item = Get-Item $Path -Force -ErrorAction SilentlyContinue
        return ($item.Attributes -band 0x400) -eq 0x400  # ReparsePoint attribute
    } catch { return $false }
}

# Check if any ancestor of Path is a junction (data lives on another drive)
# Walks parents from leaf up to drive root, checking each level.
# Handles wildcard paths by stripping the filename portion first.
function Test-IsUnderJunction {
    param([string]$Path)
    # If path contains wildcards, resolve to parent directory
    if ($Path -match '[\*\?]') {
        $Path = Split-Path $Path -Parent
        if (-not $Path) { return $false }
    }
    # Remove trailing backslash
    $Path = $Path.TrimEnd('\')
    # Walk up: C:\Users\me\AppData\Local\Doubao → ... → C:\
    $limit = 30
    while ($Path.Length -gt 3 -and $limit-- -gt 0) {
        if (Test-IsReparsePoint $Path) { return $true }
        $idx = $Path.LastIndexOf('\')
        if ($idx -le 2) { break }  # Stop at drive root (C:\)
        $Path = $Path.Substring(0, $idx)
    }
    return $false
}

# Junction-safe Get-ChildItem.
# Caller MUST call Test-IsUnderJunction first on the root path.
# Uses standard -Recurse — safe because temp/cache dirs don't contain sub-junctions.

function Get-ScannableBytes {
    param([string]$Path, [string]$Type)
    if (-not (Test-Path $Path)) { return 0 }
    try {
        if ($Type -eq "dir") {
            # Junction check (path or any ancestor): data is on another drive
            if (Test-IsUnderJunction $Path) { return 0 }
            $items = Get-ChildItem $Path -Recurse -File -Force -ErrorAction SilentlyContinue
            return ($items | Measure-Object -Property Length -Sum).Sum
        } elseif ($Type -eq "file") {
            if (Test-IsReparsePoint $Path) { return 0 }
            return (Get-Item $Path -Force -ErrorAction SilentlyContinue).Length
        } elseif ($Type -eq "glob") {
            $parent = Split-Path $Path -Parent
            $pattern = Split-Path $Path -Leaf
            if (Test-Path $parent) {
                # Don't follow junctions within found items
$items = Get-ChildItem $parent -Filter $pattern -Recurse -File -Force -ErrorAction SilentlyContinue
                return ($items | Measure-Object -Property Length -Sum).Sum
            }
        }
    } catch {}
    return 0
}

function Resolve-RulePath {
    param([string]$PathTemplate)
    # Expand environment variables in path
    $resolved = $PathTemplate
    # Match %ENVVAR% patterns and expand
    $matches = [regex]::Matches($resolved, '%([^%]+)%')
    foreach ($m in $matches) {
        $varName = $m.Groups[1].Value
        if ($varName -eq "DRIVE") {
            # %DRIVE% is resolved to the target drive specified by -TargetDrive parameter
            $varValue = $Script:TargetDrive
        } else {
            $varValue = [Environment]::GetEnvironmentVariable($varName)
        }
        if ($varValue) {
            $resolved = $resolved.Replace($m.Value, $varValue)
        }
    }
    return $resolved
}

function Load-Rules {
    param([string]$Filter = "all")

    $Script:Rules = @()
    $Script:RuleFiles = @()

    if ($Filter -eq "all" -or $Filter -eq "safe") {
        $Script:RuleFiles = Get-ChildItem $Script:RuleDir -Filter "*.json" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
    } else {
        $filters = $Filter -split ',' | ForEach-Object { $_.Trim() }
        foreach ($f in $filters) {
            $file = Join-Path $Script:RuleDir "$f.json"
            if (Test-Path $file) {
                $Script:RuleFiles += "$f.json"
            }
        }
    }

    if ($Script:RuleFiles.Count -eq 0) {
        Write-Log "WARN" "No rule files found in $Script:RuleDir"
        return
    }

    foreach ($rf in $Script:RuleFiles) {
        $path = Join-Path $Script:RuleDir $rf
        Write-Log "INFO" "Loading rules: $rf"
        try {
            $content = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($rule in $content) {
                if ($rule.Count -ge 5) {
                    $Script:Rules += @{
                        Name = $rule[0]
                        PathTemplate = $rule[1]
                        Type = $rule[2].ToString().ToLower()
                        Recycle = [bool]::Parse($rule[3].ToString())
                        Description = $rule[4]
                        Category = [System.IO.Path]::GetFileNameWithoutExtension($rf)
                        IsSafe = ($rule.Count -lt 6) -or ([bool]::Parse($rule[5].ToString()))
                    }
                } elseif ($rule.Count -ge 4) {
                    $Script:Rules += @{
                        Name = $rule[0]
                        PathTemplate = $rule[1]
                        Type = $rule[2].ToString().ToLower()
                        Recycle = [bool]::Parse($rule[3].ToString())
                        Description = $rule[0]
                        Category = [System.IO.Path]::GetFileNameWithoutExtension($rf)
                        IsSafe = $true
                    }
                }
            }
        } catch {
            Write-Log "ERROR" "Failed to load $rf : $_"
        }
    }

    # Safe filter: only include rules where IsSafe=true
    if ($Filter -eq "safe") {
        $Script:Rules = @($Script:Rules | Where-Object { $_.IsSafe })
    }

    Write-Log "INFO" "Loaded $($Script:Rules.Count) rules from $($Script:RuleFiles.Count) files"
}

function Invoke-RuleScan {
    Load-Rules -Filter $RuleFilter

    $results = [System.Collections.ArrayList]::new()
    $Script:TotalScannedBytes = 0

    Write-Log "INFO" "=== SCAN START ==="
    Write-Log "INFO" "Scanning $($Script:Rules.Count) rules..."

    foreach ($rule in $Script:Rules) {
        $path = Resolve-RulePath -PathTemplate $rule.PathTemplate
        $size = Get-ScannableBytes -Path $path -Type $rule.Type

        if ($size -gt 0) {
            $sizeMB = [math]::Round($size / 1MB, 1)
            $sizeGB = [math]::Round($size / 1GB, 2)
            $Script:TotalScannedBytes += $size

            [void]$results.Add([PSCustomObject]@{
                Rule = $rule.Name
                Category = $rule.Category
                Path = $path
                Type = $rule.Type
                SizeMB = $sizeMB
                SizeGB = $sizeGB
                IsSafe = $rule.IsSafe
                Recycle = $rule.Recycle
                Description = $rule.Description
            })
        }
    }

    Write-Log "INFO" "=== SCAN COMPLETE: $([math]::Round($Script:TotalScannedBytes/1GB,2)) GB found ==="
    return $results
}

function Invoke-RuleClean {
    param([switch]$NoDelete, [switch]$UseRecycleBin)

    Load-Rules -Filter $RuleFilter

    $results = [System.Collections.ArrayList]::new()
    $Script:TotalCleanedBytes = 0
    $Script:ErrorSamples = @{}
    $deletedCount = 0
    $failedCount = 0
    $skippedJunctionCount = 0

    if ($NoDelete) {
        Write-Log "INFO" "=== DRY-RUN CLEAN START ==="
        Write-Log "INFO" "Previewing $($Script:Rules.Count) rules (no files will be deleted)..."
    } else {
        $mode = if ($UseRecycleBin) { "Recycle Bin" } else { "Permanent" }
        Write-Log "INFO" "=== CLEAN START (mode: $mode) ==="
        Write-Log "INFO" "Cleaning $($Script:Rules.Count) rules..."
    }

    foreach ($rule in $Script:Rules) {
        $path = Resolve-RulePath -PathTemplate $rule.PathTemplate

        # --- Junction check BEFORE try block (avoids continue-in-try bugs) ---
        if (Test-IsUnderJunction $path) {
            if (Test-Path $path) {
                Write-Log "INFO" "[SKIP] $($rule.Name) — junction to D: (data already migrated)" "Gray"
            }
            $skippedJunctionCount++
            [void]$results.Add([PSCustomObject]@{
                Rule = $rule.Name; Category = $rule.Category; Path = $path
                SizeMB = 0; Status = "skipped-junction"; Error = ""
            })
            continue
        }

        $size = Get-ScannableBytes -Path $path -Type $rule.Type

        if ($size -eq 0) { continue }

        $sizeMB = [math]::Round($size / 1MB, 1)

        if (-not $NoDelete) {
            # Only use recycle bin when explicitly requested via -RecycleBin flag.
            # Never create COM Shell.Application automatically — it hangs in
            # non-interactive PowerShell (bash subprocess, CI, etc).
            $useRecycle = $UseRecycleBin
            $cleaned = $false
            $errorMsg = ""

            try {
                if ($rule.Type -eq "dir" -and (Test-Path $path)) {
                    if ($useRecycle) {
                        # COM Shell.Application may block in headless contexts.
                        # Fall through to direct delete on any failure.
                        try { $null = & {
                            $job = Start-Job -ScriptBlock {
                                param($p) $sh=New-Object -ComObject Shell.Application; $it=$sh.Namespace(0).ParseName($p); if($it){$it.InvokeVerb("delete")}
                            } -ArgumentList $path
                            Wait-Job $job -Timeout 5 | Out-Null
                            Stop-Job $job -ErrorAction SilentlyContinue
                            Remove-Job $job -Force -ErrorAction SilentlyContinue
                        } } catch {
                            Get-ChildItem $path -Recurse -Force -ErrorAction SilentlyContinue |
                                ForEach-Object { try { Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue } catch {} }
                            Remove-Item $path -Recurse -Force -ErrorAction SilentlyContinue
                        }
                    } else {
                        Get-ChildItem $path -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
                            try { Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue } catch {}
                        }
                        Remove-Item $path -Recurse -Force -ErrorAction SilentlyContinue
                    }
                    $cleaned = $true
                } elseif ($rule.Type -eq "file" -and (Test-Path $path)) {
                    if ($useRecycle) {
                        # COM Shell.Application may block in headless contexts.
                        # Fall through to direct delete on any failure.
                        try { $null = & {
                            $job = Start-Job -ScriptBlock {
                                param($p) $sh=New-Object -ComObject Shell.Application; $it=$sh.Namespace(0).ParseName($p); if($it){$it.InvokeVerb("delete")}
                            } -ArgumentList $path
                            Wait-Job $job -Timeout 5 | Out-Null
                            Stop-Job $job -ErrorAction SilentlyContinue
                            Remove-Job $job -Force -ErrorAction SilentlyContinue
                        } } catch {
                            Get-ChildItem $path -Recurse -Force -ErrorAction SilentlyContinue |
                                ForEach-Object { try { Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue } catch {} }
                            Remove-Item $path -Recurse -Force -ErrorAction SilentlyContinue
                        }
                    } else {
                        Remove-Item $path -Force -ErrorAction SilentlyContinue
                    }
                    $cleaned = $true
                } elseif ($rule.Type -eq "glob") {
                    $parent = Split-Path $path -Parent
                    $pattern = Split-Path $path -Leaf
                    if (Test-Path $parent) {
                        Get-ChildItemSafe -Path $parent -Filter $pattern -Recurse -File -Force | ForEach-Object {
                            try {
                                if ($useRecycle) {
                                    $sh = New-Object -ComObject Shell.Application
                                    $it = $sh.Namespace(0).ParseName($_.FullName)
                                    if ($it) { $it.InvokeVerb("delete") }
                                } else {
                                    Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
                                }
                            } catch {}
                        }
                    }
                    $cleaned = $true
                }
            } catch {
                # Error sampling: suppress repeated errors
                $errKey = "$($rule.Name):$($_.Exception.Message)"
                if (-not $Script:ErrorSamples.ContainsKey($errKey)) {
                    $Script:ErrorSamples[$errKey] = $true
                    $errorMsg = $_.Exception.Message
                }
            }

            if ($cleaned) {
                $remaining = Get-ScannableBytes -Path $path -Type $rule.Type
                $actual = $size - $remaining
                if ($actual -gt 0) {
                    $Script:TotalCleanedBytes += $actual
                } else {
                    $Script:TotalCleanedBytes += $size
                }
                $deletedCount++
            } elseif ($errorMsg) {
                $failedCount++
            }
        }

        [void]$results.Add([PSCustomObject]@{
            Rule = $rule.Name; Category = $rule.Category; Path = $path
            SizeMB = $sizeMB
            Status = if ($NoDelete) { "would-delete" } elseif ($errorMsg) { "failed" } else { "deleted" }
            Error = $errorMsg
        })
    }

    if (-not $NoDelete) {
        Write-Log "INFO" "Skipped (junction): $skippedJunctionCount rules"
        Write-Log "INFO" "Deleted: $deletedCount rules, Failed: $failedCount rules"
    }
    Write-Log "INFO" "=== CLEAN COMPLETE: $([math]::Round($Script:TotalCleanedBytes/1GB,2)) GB freed ==="
    return $results
}

function Get-RuleReport {
    param($Results)

    $totalMB = [math]::Round($Script:TotalScannedBytes / 1MB, 1)
    if ($Command -eq "Clean") {
        $totalMB = [math]::Round($Script:TotalCleanedBytes / 1MB, 1)
    }

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    if ($Command -eq "Scan") {
        Write-Host "  Rule Engine Scan Report" -ForegroundColor Cyan
    } elseif ($DryRun) {
        Write-Host "  Rule Engine Dry-Run Report" -ForegroundColor Cyan
    } else {
        Write-Host "  Rule Engine Clean Report" -ForegroundColor Cyan
    }
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Rules loaded : $($Script:Rules.Count)" -ForegroundColor White
    Write-Host "  Rule files   : $($Script:RuleFiles.Count)" -ForegroundColor White
    if ($Command -eq "Scan") {
        Write-Host "  Scannable    : ${totalMB} MB" -ForegroundColor Green
    } else {
        Write-Host "  Freed        : ${totalMB} MB" -ForegroundColor Green
    }
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    if ($Results -and $Results.Count -gt 0) {
        # Group by category
        $byCategory = $Results | Group-Object Category
        foreach ($group in $byCategory) {
            $catTotal = ($group.Group | Measure-Object -Property SizeMB -Sum).Sum
            Write-Host "--- $($group.Name) ($([math]::Round($catTotal,1)) MB) ---" -ForegroundColor Yellow
            $group.Group | Sort-Object SizeMB -Descending | Select-Object -First 15 | Format-Table Rule, SizeMB, Status -AutoSize
            if ($group.Group.Count -gt 15) {
                Write-Host "  ... and $($group.Group.Count - 15) more items" -ForegroundColor Gray
            }
        }
    }
}

# ---- Main Entry Point ----
Write-Log "INFO" "Engine starting: Command=$Command, Filter=$RuleFilter, DryRun=$DryRun, RecycleBin=$RecycleBin, Lang=$Lang"

if ($Command -eq "Scan") {
    $scanResults = Invoke-RuleScan
    Get-RuleReport -Results $scanResults
    Write-Log "INFO" "Engine scan complete"

    # Return as object for programmatic use
    @{
        Command = "Scan"
        TotalBytes = $Script:TotalScannedBytes
        TotalGB = [math]::Round($Script:TotalScannedBytes / 1GB, 2)
        RuleCount = $Script:Rules.Count
        Results = $scanResults
    }
} elseif ($Command -eq "Clean") {
    $cleanResults = Invoke-RuleClean -NoDelete:$DryRun -UseRecycleBin:$RecycleBin
    Get-RuleReport -Results $cleanResults
    Write-Log "INFO" "Engine clean complete"

    @{
        Command = "Clean"
        DryRun = $DryRun
        TotalBytes = $Script:TotalCleanedBytes
        TotalGB = [math]::Round($Script:TotalCleanedBytes / 1GB, 2)
        RuleCount = $Script:Rules.Count
        DeletedCount = @($cleanResults | Where-Object Status -eq "deleted").Count
        Results = $cleanResults
    }
}
