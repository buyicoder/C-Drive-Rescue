---
name: c-drive-rescue
description: 当用户说"清理C盘""C盘满了""C盘红了""释放C盘空间""C drive cleanup"时使用。三引擎架构——system-tools.rs(4万⭐ Rust CLI,35条规则)主引擎 + Windows内置命令(dism/cleanmgr)辅助 + PowerShell Junction迁移兜底。覆盖：磁盘分析 → 安全清理 → 系统深度清理 → 大文件夹搬家到D盘 → 效果报告。典型效果：200GB C盘从88%降到68%，释放25-40GB。
version: 2.0.0
---

# 🛟 C-Drive Rescue — 拯救C盘 (v2)

## Architecture

```
                    ┌─────────────────────────┐
                    │    C-Drive-Rescue Skill  │
                    └───────────┬─────────────┘
                                │
              ┌─────────────────┼─────────────────┐
              ▼                 ▼                   ▼
     ┌───────────────┐ ┌──────────────┐ ┌──────────────────┐
     │ system-tools  │ │   Windows    │ │  Custom PS       │
     │    .rs        │ │  Built-ins   │ │  Scripts         │
     │ (primary)     │ │  (secondary) │ │  (junction only)  │
     │ 35 rules      │ │ dism/cleanmgr│ │  robocopy +       │
     │ CLI + MCP     │ │ vssadmin/wsl │ │  mklink           │
     └───────────────┘ └──────────────┘ └──────────────────┘
```

**Engine 1 — [system-tools.rs](https://github.com/VDHewei/system-tools.rs)** (Primary):
- 6 大类 35 条内置清理规则，覆盖系统/浏览器/开发工具/国产软件
- 参考了 360、火绒、腾讯电脑管家的深度清理理念
- Rust 单文件可执行，~5 MB，零依赖
- 安全模式 `--items 0`：不删个人文件，只清系统+应用缓存
- 支持 `--dry-run` 预览，不实际删除

**Engine 2 — Windows 内置命令** (Fallback):
- `dism /online /cleanup-image /startcomponentcleanup` — WinSxS 组件清理
- `cleanmgr /autoclean` — 系统磁盘清理
- `vssadmin resize shadowstorage` — 系统还原点裁剪

**Engine 3 — 自定义 PowerShell** (Junction 迁移):
- `robocopy` + NTFS Junction — 大文件夹搬家到 D 盘
- WSL `--export` / `--import` — WSL 发行版迁移
- 这是 system-tools.rs 不覆盖的能力

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
