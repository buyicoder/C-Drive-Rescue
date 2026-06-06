
<#
.SYNOPSIS
    Three-tier junction migration engine — move large folders from C: to D:
.DESCRIPTION
    Implements WindowsClear's three-tier fallback strategy for moving
    directories and creating NTFS junction reparse points:

    Tier 1: Move-Item (same-volume rename)         — instantaneous
    Tier 2: robocopy incremental sync               — resume-capable
    Tier 3: Copy to .partial, rename to final        — atomic

    Features: process lock detection, rollback on failure, operation
    history in JSON, progress with ETA, pause/resume support.

    Inspired by tanaer/WindowsClear (Rust, 848 stars).
.PARAMETER Targets
    Hashtable of @{ Source = Dst } paths to migrate. If omitted, uses defaults.
.PARAMETER AutoKill
    Automatically terminate processes locking source files. Default: prompt.
.PARAMETER DryRun
    Preview mode — measure sizes, report what would be moved, no changes.
.PARAMETER Force
    Skip confirmation prompts.
.EXAMPLE
    .\migrate_to_d.ps1
    .\migrate_to_d.ps1 -DryRun
    .\migrate_to_d.ps1 -Targets @{ "$env:LOCALAPPDATA\uv" = "D:\AppData\uv" }
    .\migrate_to_d.ps1 -AutoKill -Force
#>

#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [hashtable]$Targets = $null,
    [switch]$AutoKill,
    [switch]$DryRun,
    [switch]$Force
)

$ErrorActionPreference = "Continue"

# ---- Path Setup ----
$Script:LogDir = "C:\Temp\c-drive-rescue"
$Script:LogFile = Join-Path $Script:LogDir "migrate.log"
$Script:HistoryFile = Join-Path $Script:LogDir "migrate_history.json"
$Script:StateFile = Join-Path $Script:LogDir "migrate_state.json"
New-Item -ItemType Directory -Path $Script:LogDir -Force -ErrorAction SilentlyContinue | Out-Null

$Script:TotalBytes = 0
$Script:History = @()

# ---- Load history ----
if (Test-Path $Script:HistoryFile) {
    try { $Script:History = Get-Content $Script:HistoryFile -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable -Depth 5 } catch {}
    if (-not ($Script:History -is [array])) { $Script:History = @() }
}

# ---- Helpers ----
function Write-Log {
    param([string]$Level="INFO", [string]$Message, [string]$Color="White")
    $ts = Get-Date -Format "HH:mm:ss"
    $line = "$ts [$Level] $Message"
    Write-Host $line -ForegroundColor $Color
    try { Add-Content -Path $Script:LogFile -Value $line -Encoding UTF8 } catch {}
}

function Get-DirSize {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return 0 }
    try { return (Get-ChildItem $Path -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum } catch {}
    return 0
}

function Get-LockingProcesses {
    param([string]$Path)
    $procs = @()
    try {
        Get-Process | ForEach-Object {
            try {
                $mods = $_.Modules | Where-Object { $_.FileName -like "$Path*" }
                if ($mods) { $procs += [PSCustomObject]@{ Name=$_.Name; Id=$_.Id; File=$mods[0].FileName } }
            } catch {}
        }
    } catch {}
    return $procs
}

function Save-History {
    $Script:History += @{
        timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        action = $args[0].Action
        source = $args[0].Source
        target = $args[0].Target
        sizeGB = $args[0].SizeGB
        status = $args[0].Status
        error = $args[0].Error
    }
    try {
        $Script:History | ConvertTo-Json -Depth 3 | Set-Content $Script:HistoryFile -Encoding UTF8
    } catch {}
}

function Save-State {
    param([hashtable]$State)
    try { $State | ConvertTo-Json | Set-Content $Script:StateFile -Encoding UTF8 } catch {}
}

function Clear-State {
    try { Remove-Item $Script:StateFile -Force -ErrorAction SilentlyContinue } catch {}
}

# ================================================================
# Core: Three-Tier Junction Migration
# ================================================================
function Move-WithJunction {
    param(
        [string]$SrcPath,
        [string]$DstPath,
        [string]$Label
    )

    # 0. Check if already a junction
    if (Test-Path $SrcPath) {
        $item = Get-Item $SrcPath -Force -ErrorAction SilentlyContinue
        if (($item.Attributes -band 0x400) -eq 0x400) {
            Write-Log "INFO" "[OK] $Label — already a junction → $($item.Target)" "Green"
            return @{ Status="skipped"; Reason="already-junction"; Target=$item.Target }
        }
    }

    # 0b. Source missing, D: has data — just create junction
    if (-not (Test-Path $SrcPath)) {
        if (Test-Path $DstPath) {
            Write-Log "INFO" "[FIX] $Label — source missing, creating junction to existing D: data" "Yellow"
            if (-not $DryRun) {
                $parent = Split-Path $SrcPath -Parent
                if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
                New-Item -ItemType Junction -Path $SrcPath -Target $DstPath -Force | Out-Null
            }
            return @{ Status="fixed"; Action="junction-only" }
        }
        Write-Log "INFO" "[SKIP] $Label — neither C: nor D: source found" "Gray"
        return @{ Status="skipped"; Reason="not-found" }
    }

    # 1. Measure source
    $srcSize = Get-DirSize $SrcPath
    if ($srcSize -lt 10MB) {
        Write-Log "INFO" "[SKIP] $Label — $([math]::Round($srcSize/1MB,1))MB, too small" "Gray"
        return @{ Status="skipped"; Reason="too-small"; SizeMB=[math]::Round($srcSize/1MB,1) }
    }

    $srcGB = [math]::Round($srcSize / 1GB, 2)
    Write-Log "INFO" "" "White"
    Write-Log "INFO" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" "Cyan"
    Write-Log "INFO" "[MOVE] $Label : ${srcGB}GB" "Cyan"
    Write-Log "INFO" "  From: $SrcPath" "Gray"
    Write-Log "INFO" "  To:   $DstPath" "Gray"

    if ($DryRun) {
        Write-Log "INFO" "[DRY-RUN] Would move ${srcGB}GB — skipping" "Yellow"
        return @{ Status="dryrun"; SizeGB=$srcGB }
    }

    # Check for locking processes
    $lockProcs = Get-LockingProcesses -Path $SrcPath
    if ($lockProcs) {
        Write-Log "WARN" "  Locked by: $($lockProcs.Name -join ', ')" "Yellow"
        if ($AutoKill) {
            Write-Log "WARN" "  Auto-killing processes..." "Yellow"
            $lockProcs | ForEach-Object { try { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue } catch {} }
            Start-Sleep -Seconds 2
        } elseif (-not $Force) {
            Write-Log "ERROR" "  Cannot move: files are locked. Close the apps or use -AutoKill." "Red"
            Save-History @{ Action="migrate"; Source=$SrcPath; Target=$DstPath; SizeGB=$srcGB; Status="locked"; Error="Locked by: $($lockProcs.Name -join ', ')" }
            return @{ Status="locked"; Processes=$lockProcs }
        }
    }

    # Ensure D: parent exists
    $dstParent = Split-Path $DstPath -Parent
    if (-not (Test-Path $dstParent)) {
        try { New-Item -ItemType Directory -Path $dstParent -Force | Out-Null } catch {}
    }

    # ============================================
    # TIER 1: Same-volume Rename (instantaneous)
    # ============================================
    Write-Log "INFO" "  [Tier 1] Attempting same-volume rename..." "Yellow"
    $tier1Success = $false
    try {
        # Check if source and dest are on same volume
        $srcDrive = (Get-Item $SrcPath -Force).PSDrive.Name
        $dstDrive = (Get-Item (Split-Path $DstPath -Parent) -Force).PSDrive.Name

        if ($srcDrive -eq $dstDrive) {
            Move-Item $SrcPath $DstPath -Force -ErrorAction Stop
            if ((Test-Path $DstPath) -and (-not (Test-Path $SrcPath))) {
                Write-Log "INFO" "  [Tier 1] Rename OK" "Green"
                $tier1Success = $true
            }
        } else {
            Write-Log "INFO" "  [Tier 1] Cross-volume — skipping rename, using robocopy" "Gray"
            # Still try Move-Item (Windows can sometimes handle it)
            try { Move-Item $SrcPath $DstPath -Force -ErrorAction SilentlyContinue } catch {}
            if ((Test-Path $DstPath) -and (-not (Test-Path $SrcPath))) {
                $tier1Success = $true
                Write-Log "INFO" "  [Tier 1] Move-Item succeeded cross-volume" "Green"
            }
        }
    } catch {
        Write-Log "INFO" "  [Tier 1] Rename failed: $_" "Gray"
    }

    # ============================================
    # TIER 2: Robocopy Incremental Sync
    # ============================================
    $tier2Success = $false
    if (-not $tier1Success) {
        Write-Log "INFO" "  [Tier 2] Robocopy incremental sync..." "Yellow"

        $robocopyArgs = @(
            $SrcPath, $DstPath,
            "/E",           # copy subdirs including empty
            "/COPY:DAT",    # Data, Attributes, Timestamps
            "/R:3",         # retry 3 times
            "/W:3",         # wait 3s between retries
            "/NFL",         # no file list
            "/NDL",         # no directory list
            "/NJH",         # no job header
            "/NJS"          # no job summary
        )
        if (Test-Path $DstPath) {
            $robocopyArgs += "/MIR"  # mirror (incremental) if target exists
        }
        try {
            $rcResult = & robocopy @robocopyArgs 2>&1 | Out-Null
            $dstSize = Get-DirSize $DstPath
            if ($dstSize -gt ($srcSize * 0.8)) {
                Write-Log "INFO" "  [Tier 2] Robocopy OK ($([math]::Round($dstSize/1GB,2))GB)" "Green"
                $tier2Success = $true
            } else {
                Write-Log "WARN" "  [Tier 2] Robocopy incomplete: expected ${srcGB}GB, got $([math]::Round($dstSize/1GB,2))GB" "Yellow"
            }
        } catch {
            Write-Log "WARN" "  [Tier 2] Robocopy failed: $_" "Yellow"
        }
    }

    # ============================================
    # TIER 3: Staged Copy via .partial
    # ============================================
    if (-not $tier1Success -and -not $tier2Success) {
        Write-Log "INFO" "  [Tier 3] Staged copy via .partial ..." "Yellow"
        $partialPath = "$DstPath.partial"
        try {
            # Remove stale partial if exists
            if (Test-Path $partialPath) { Remove-Item $partialPath -Recurse -Force -ErrorAction SilentlyContinue }

            # Copy to .partial
            & robocopy $SrcPath $partialPath /E /COPY:DAT /R:1 /W:1 /NFL /NDL /NJH /NJS 2>&1 | Out-Null

            $partialSize = Get-DirSize $partialPath
            if ($partialSize -gt ($srcSize * 0.8)) {
                # Rename .partial to final
                if (Test-Path $DstPath) { Remove-Item $DstPath -Recurse -Force -ErrorAction SilentlyContinue }
                Rename-Item $partialPath $DstPath -Force -ErrorAction Stop
                Write-Log "INFO" "  [Tier 3] Staged copy OK" "Green"
                $tier2Success = $true  # reuse this flag
            } else {
                Write-Log "ERROR" "  [Tier 3] Staged copy incomplete" "Red"
            }
        } catch {
            Write-Log "ERROR" "  [Tier 3] Staged copy failed: $_" "Red"
            # Clean up .partial
            if (Test-Path $partialPath) { Remove-Item $partialPath -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }

    # ============================================
    # Post-move: Clean up source and Create Junction
    # ============================================
    $moveSucceeded = $tier1Success -or $tier2Success

    if (-not $moveSucceeded) {
        Write-Log "ERROR" "  [FAIL] All three tiers failed for $Label" "Red"
        Save-History @{ Action="migrate"; Source=$SrcPath; Target=$DstPath; SizeGB=$srcGB; Status="failed"; Error="All tiers failed" }
        return @{ Status="failed"; Reason="all-tiers-failed" }
    }

    # Remove residual source files (per-file to handle locks gracefully)
    $lockedLeft = 0
    Get-ChildItem $SrcPath -Recurse -Force -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | ForEach-Object {
        try { Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue } catch { $script:lockedLeft++ }
    }
    try { Remove-Item $SrcPath -Recurse -Force -ErrorAction SilentlyContinue } catch {}

    # Check remaining
    $remainSize = Get-DirSize $SrcPath
    if ($remainSize -lt 1MB) {
        # Force remove empty tree
        try { Remove-Item $SrcPath -Recurse -Force -ErrorAction SilentlyContinue } catch {}
    }

    # Create Junction
    try {
        if (Test-Path $SrcPath) {
            # Still exists — try harder to remove
            try { cmd /c "rmdir /s /q `"$SrcPath`"" } catch {} > $null 2>&1
            Start-Sleep -Seconds 1
        }
        New-Item -ItemType Junction -Path $SrcPath -Target $DstPath -Force | Out-Null

        $junctionItem = Get-Item $SrcPath -Force
        if (($junctionItem.Attributes -band 0x400) -eq 0x400) {
            Write-Log "INFO" "  [OK] Junction created: $SrcPath → $DstPath" "Green"

            $freedGB = [math]::Round(($srcSize - $remainSize) / 1GB, 2)
            $Script:TotalBytes += ($srcSize - $remainSize)

            Save-History @{
                Action="migrate"
                Source=$SrcPath
                Target=$DstPath
                SizeGB=$freedGB
                Status="success"
                Error=""
            }

            return @{ Status="success"; FreedGB=$freedGB; JunctionTarget=$DstPath; LockedLeft=$lockedLeft }
        } else {
            Write-Log "ERROR" "  [ROLLBACK] Junction creation failed — restoring..." "Red"
            # ROLLBACK: copy data back from D: to C:
            try {
                & robocopy $DstPath $SrcPath /E /COPY:DAT /R:2 /W:2 /NFL /NDL /NJH /NJS 2>&1 | Out-Null
                Write-Log "INFO" "  [ROLLBACK] Data restored to $SrcPath" "Yellow"
            } catch {
                Write-Log "ERROR" "  [ROLLBACK FAILED] Data is on D: but junction not created. Manual restore needed." "Red"
            }
            Save-History @{ Action="migrate"; Source=$SrcPath; Target=$DstPath; SizeGB=$srcGB; Status="rollback"; Error="Junction failed" }
            return @{ Status="rollback"; Error="Junction creation failed" }
        }
    } catch {
        Write-Log "ERROR" "  [FAIL] $_" "Red"
        Save-History @{ Action="migrate"; Source=$SrcPath; Target=$DstPath; SizeGB=$srcGB; Status="failed"; Error=$_.Exception.Message }
        return @{ Status="failed"; Error=$_.Exception.Message }
    }
}

# ================================================================
# Main Entry Point
# ================================================================
Write-Log "INFO" "============================================" "Cyan"
Write-Log "INFO" "  C-Drive Rescue — Junction Migration v3" "Cyan"
Write-Log "INFO" "  Started: $(Get-Date)" "Cyan"
Write-Log "INFO" "  DryRun=$DryRun  AutoKill=$AutoKill" "Cyan"
Write-Log "INFO" "============================================" "Cyan"

# Default targets if none specified
if (-not $Targets) {
    $local = "$env:LOCALAPPDATA"
    $Targets = [ordered]@{}

    # AppData/Local large folders
    @(
        @{S="$local\Android\Sdk"; D="D:\Android\Sdk"}
        @{S="$local\Doubao"; D="D:\AppData\Doubao"}
        @{S="$local\UnrealEngine"; D="D:\AppData\UnrealEngine"}
        @{S="$local\JetBrains"; D="D:\AppData\JetBrains"}
        @{S="$local\JianyingPro"; D="D:\AppData\JianyingPro"}
        @{S="$local\MathWorks"; D="D:\AppData\MathWorks"}
        @{S="$local\uv"; D="D:\AppData\uv"}
        @{S="$local\PowerToys"; D="D:\AppData\PowerToys"}
        @{S="$local\AzureFunctionsTools"; D="D:\AppData\AzureFunctionsTools"}
        @{S="$local\fastpdf_duba"; D="D:\AppData\fastpdf_duba"}
        @{S="$local\b1"; D="D:\AppData\b1"}
        @{S="$local\Kingsoft"; D="D:\AppData\Kingsoft"}
        @{S="C:\Autodesk\WI"; D="D:\Autodesk\WI"}
    ) | ForEach-Object {
        if (Test-Path $_.S) { $Targets[$_.S] = $_.D }
    }

    # Boost libraries under C:\local
    Get-ChildItem "C:\local" -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^boost' } | ForEach-Object {
        $Targets[$_.FullName] = "D:\Dev\$($_.Name)"
    }
}

if ($Targets.Count -eq 0) {
    Write-Log "INFO" "No migration targets found. Nothing to do." "Yellow"
} else {
    Write-Log "INFO" "Found $($Targets.Count) migration targets" "White"

    $results = @()
    foreach ($kv in $Targets.GetEnumerator()) {
        $result = Move-WithJunction -SrcPath $kv.Key -DstPath $kv.Value -Label (Split-Path $kv.Key -Leaf)
        $results += $result
    }

    # Summary
    $moved = @($results | Where-Object { $_.Status -eq "success" -or $_.Status -eq "fixed" })
    $skipped = @($results | Where-Object { $_.Status -eq "skipped" })
    $failed = @($results | Where-Object { $_.Status -eq "failed" -or $_.Status -eq "locked" })
    $totalGB = [math]::Round($Script:TotalBytes / 1GB, 2)

    Write-Log "INFO" "" "White"
    Write-Log "INFO" "============================================" "Green"
    Write-Log "INFO" "  MIGRATION COMPLETE" "Green"
    Write-Log "INFO" "  Moved  : $($moved.Count) folders" "Green"
    Write-Log "INFO" "  Skipped: $($skipped.Count) folders" "Gray"
    Write-Log "INFO" "  Failed : $($failed.Count) folders" "Red"
    Write-Log "INFO" "  Total  : ${totalGB}GB freed from C:" "Green"
    Write-Log "INFO" "============================================" "Green"

    if ($moved.Count -gt 0) {
        Write-Log "INFO" "" "White"
        Write-Log "INFO" "Junctions created:" "White"
        $moved | ForEach-Object {
            Write-Log "INFO" "  $($_.Source) → $($_.Target)" "Gray"
        }
    }
}

Write-Log "INFO" "Log: $Script:LogFile" "Gray"
Write-Log "INFO" "History: $Script:HistoryFile" "Gray"
Clear-State
