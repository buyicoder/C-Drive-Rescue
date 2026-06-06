<#
.SYNOPSIS
    Safe cleanup — user-level, no admin required.
.DESCRIPTION
    Calls rule engine with Safe filter. Only cleans rules where IsSafe=true.
    These are temp files, caches, logs — all regenerate automatically.
.EXAMPLE
    .\safe_cleanup.ps1                  # Clean all safe rules
    .\safe_cleanup.ps1 -DryRun           # Preview only
    .\safe_cleanup.ps1 -RecycleBin       # Move to recycle bin
#>

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$RecycleBin,
    [string]$CategoryFilter = "safe"
)

$enginePath = Join-Path $PSScriptRoot "engine.ps1"
$ruleDir = Join-Path (Split-Path $PSScriptRoot -Parent) "..\..\..\rules"

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  C-Drive Rescue — Safe Cleanup (Phase 2)" -ForegroundColor Cyan
Write-Host "  Filter: $CategoryFilter" -ForegroundColor Cyan
if ($DryRun) { Write-Host "  MODE: DRY-RUN (preview only)" -ForegroundColor Yellow }
if ($RecycleBin) { Write-Host "  MODE: Recycle Bin" -ForegroundColor Yellow }
Write-Host "============================================" -ForegroundColor Cyan

$result = & $enginePath -Command Clean -RuleFilter $CategoryFilter -RuleDir $ruleDir -DryRun:$DryRun -RecycleBin:$RecycleBin

Write-Host ""
Write-Host "Next: Run admin_cleanup.ps1 with Administrator privileges" -ForegroundColor Yellow
return $result
