---
name: c-drive-rescue
description: 当用户说"清理C盘""C盘满了""C盘红了""释放C盘空间""C drive cleanup"时使用。四引擎架构——JSON规则引擎(116条规则,BleachBit兼容) + system-tools.rs(4万⭐ Rust CLI) + Windows内置命令(dism/cleanmgr) + 三级回退NTFS Junction迁移。借鉴c_cleaner_plus规则商店/WindowsClear三级搬家/Dism++深度清理。五阶段：分析→安全清理→系统清理→搬家→报告。典型效果：200GB C盘从88%降到68%，释放25-40GB。
version: 3.0.0
---

# 🛟 C-Drive Rescue — 拯救C盘 (v3)

## Architecture

```
                      ┌─────────────────────────┐
                      │    C-Drive-Rescue Skill  │
                      └───────────┬─────────────┘
                                  │
       ┌──────────────┬───────────┼───────────┬──────────────┐
       ▼              ▼           ▼           ▼              ▼
  ┌─────────┐  ┌──────────┐ ┌─────────┐ ┌──────────┐ ┌──────────┐
  │ Engine①│  │ Engine②  │ │Engine③  │ │ Engine④  │ │  Rules   │
  │ JSON    │  │ system-  │ │Windows  │ │Junction  │ │  Store   │
  │ Rule    │  │ tools.rs │ │Built-in │ │Migration │ │  116     │
  │ Engine  │  │ 35 rules │ │dism     │ │3-Tier    │ │  rules   │
  │-------- │  │ Rust CLI │ │cleanmgr │ │Fallback  │ │  6 cats  │
  │Primary  │  │Secondary │ │Fallback │ │Unique    │ │BleachBit │
  └─────────┘  └──────────┘ └─────────┘ └──────────┘ └──────────┘
```

**Engine ① — JSON 规则引擎** (Primary, 借鉴 c_cleaner_plus):
- 116 条清理规则，BleachBit 兼容 JSON 格式
- 6 大类：system / browser / dev_tools / cn_apps / game / creative
- 规则与代码分离——改规则不用改脚本
- 支持逐规则 `recycle_bin` 开关、`isSafe` 标记、`DryRun` 预览

**Engine ② — [system-tools.rs](https://github.com/VDHewei/system-tools.rs)** (Secondary):
- 40,000+ Stars Rust CLI，35 条内置规则
- `--dry-run` 预览、`--items 0` 安全模式
- MCP 服务器模式可对接 AI Agent

**Engine ③ — Windows 内置** (Fallback):
- `dism /online /cleanup-image /startcomponentcleanup /resetbase`
- `cleanmgr /autoclean`
- `vssadmin resize shadowstorage`

**Engine ④ — 三级回退 Junction 迁移** (Unique, 借鉴 WindowsClear):
- Tier 1: Move-Item 同盘 rename（瞬时）
- Tier 2: robocopy /MIR 增量同步（支持续传）
- Tier 3: .partial 分阶段复制（原子操作）
- 进程锁定检测 + 失败回滚 + 操作历史 JSON

## Cleanup Phases

### Phase 0: Setup & Tool Check

Check if `system-tools.exe` exists in `tools/` directory:
- **If found**: Use it as primary engine for Phase 1-3
- **If not found**: Offer to download from GitHub Releases
  - URL: `https://github.com/VDHewei/system-tools.rs/releases/latest/download/system-tools.exe`
  - Save to `tools/system-tools.exe`
  - If download fails, fall back to PowerShell scripts

Run `scripts/setup_tools.ps1` to automate this.

### Phase 1: Disk Analysis

**With system-tools.rs**:
```bash
# Full scan of C: drive
tools\system-tools.exe -d C:\
# Or programmatic:
tools\system-tools.exe scan --drive C: --output json
```
Shows: total/used/free, 35 rule hits with per-rule size estimates, top space consumers

**Fallback (PowerShell)**: Run `scripts/disk_analyzer.ps1`

### Phase 2: Safe Cleanup

**With system-tools.rs**:
```bash
# Preview first (no actual deletion)
tools\system-tools.exe clean --items 0 --dry-run

# Run all safe rules (if user confirms)
tools\system-tools.exe clean --items 0
```
`--items 0` = all safe rules: temp files, browser caches, Windows caches, app caches, dev tool caches — everything that's safe to delete without affecting personal data.

Individual rules available:
- `1,2,4,5` = system temp files
- `13,14` = browser caches
- `20-28` = dev tool caches (JetBrains, VS, npm, etc.)

**Fallback (PowerShell)**: Run `scripts/safe_cleanup.ps1`

### Phase 3: Admin Cleanup

**With system-tools.rs** (run as admin):
```bash
# Dangerous items (recycle bin 32, hibernation 34)
tools\system-tools.exe clean --items 32,34
```

**Windows built-ins** (always used, not in system-tools):
```powershell
dism /online /cleanup-image /startcomponentcleanup /resetbase
cleanmgr /autoclean
vssadmin resize shadowstorage /on=C: /for=C: /maxsize=5GB
```

**Fallback (PowerShell)**: Run `scripts/admin_cleanup.ps1`

### Phase 4: Junction Migration

Run `scripts/migrate_to_d.ps1` with admin. This is unique to this skill — no open-source tool handles AppData junction migration for Chinese apps (剪映/豆包/WPS etc.).

Pattern per folder: `robocopy /MOVE` → `New-Item -ItemType Junction`

| Source | Target |
|--------|--------|
| `%LOCALAPPDATA%\Android\Sdk` | `D:\Android\Sdk` |
| WSL distros (via wsl --export/--import) | `D:\WSL\<distro>` |
| `%LOCALAPPDATA%\Doubao` | `D:\AppData\Doubao` |
| `%LOCALAPPDATA%\UnrealEngine` | `D:\AppData\UnrealEngine` |
| `%LOCALAPPDATA%\JetBrains` | `D:\AppData\JetBrains` |
| `%LOCALAPPDATA%\JianyingPro` | `D:\AppData\JianyingPro` |
| `%LOCALAPPDATA%\MathWorks` | `D:\AppData\MathWorks` |
| `%LOCALAPPDATA%\uv` | `D:\AppData\uv` |
| `%LOCALAPPDATA%\PowerToys` | `D:\AppData\PowerToys` |
| `C:\Autodesk\WI` | `D:\Autodesk\WI` |
| `C:\local\boost_*` | `D:\Dev\boost_*` |

### Phase 5: Report

Present before/after table. List junctions created. Show remaining large items.

## MCP Integration (Optional, for AI Agent mode)

Add to `~/.claude/settings.json` or project `.mcp.json`:
```json
{
  "mcpServers": {
    "system-tools": {
      "command": "<skill-dir>/tools/system-tools.exe",
      "args": ["mcp"]
    }
  }
}
```

Then Claude Code can call MCP tools directly:
- `scan_disk` — scan disk with all 35 rules
- `list_clean_rules` — enumerate rules with descriptions
- `execute_clean` — execute specific rules
- `get_disk_info` — disk usage summary
- `clean_path` — clean a specific path

When MCP is configured, skip CLI and call MCP tools directly for richer interaction.

## Scripts

| Script | Engine | Admin | Purpose |
|--------|--------|-------|---------|
| `scripts/setup_tools.ps1` | - | No | Download system-tools.exe |
| `scripts/disk_analyzer.ps1` | Fallback | No | PowerShell disk scan |
| `scripts/safe_cleanup.ps1` | Fallback | No | PowerShell safe cleanup |
| `scripts/admin_cleanup.ps1` | Fallback | Yes | PowerShell admin cleanup |
| `scripts/migrate_to_d.ps1` | Primary | Yes | Junction migration |

## Typical Results

On a 200 GB C: drive at 88% usage:
- system-tools.rs safe rules: ~5-10 GB
- DISM + cleanmgr: ~2-5 GB
- Junction migration: ~15-25 GB
- **Total: 25-40 GB recovered**
