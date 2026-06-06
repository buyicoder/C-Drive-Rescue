# 🛟 C-Drive Rescue — 拯救C盘

[![Version](https://img.shields.io/badge/version-2.0.0-blue)](https://github.com/buyicoder/C-Drive-Rescue)

一个 Claude Code 插件，专治 Windows C 盘爆红。三引擎架构，五阶段清理，安全释放 25–40GB。

## 🏗️ 架构

```
用户说 "C盘满了"
        │
        ▼
┌──────────────────────────────────┐
│        C-Drive Rescue            │
├───────────┬──────────┬───────────┤
│ Engine 1  │ Engine 2 │ Engine 3  │
│ system-   │ Windows  │ Junction  │
│ tools.rs  │ Built-in │ Migration │
│ 35 rules  │ dism     │ robocopy  │
│ Rust CLI  │ cleanmgr │ + mklink  │
└───────────┴──────────┴───────────┘
```

## 🔧 依赖的开源项目

| 项目 | 用途 | Stars |
|------|------|-------|
| [system-tools.rs](https://github.com/VDHewei/system-tools.rs) | 主力清理引擎，35条规则 | 40,000+ |
| [Dism++](https://github.com/Chuyu-Team/Dism-Multi-language) | 可选，GUI 系统维护 | 40,000+ |

## 📋 五个阶段

| 阶段 | 内容 | 权限 |
|------|------|------|
| ① 磁盘分析 | 扫描所有驱动器、定位空间大户 | 无需 |
| ② 安全清理 | 临时文件、浏览器/IDE/应用缓存 | 无需 |
| ③ 系统清理 | Windows更新、DISM组件、NVIDIA缓存 | 管理员 |
| ④ 文件夹搬家 | robocopy + NTFS Junction → D盘 | 管理员 |
| ⑤ 效果报告 | 前后对比，释放空间明细 | 无需 |

## 🚀 使用方式

1. 安装此插件到 Claude Code 的 plugins 目录
2. 重启 Claude Code
3. 说：**「清理C盘」** 或 **「C盘满了」**

首次使用自动下载 system-tools.exe（~5MB），下载失败则降级为纯 PowerShell 方案。

## 📁 文件结构

```
c-drive-rescue/
├── .claude-plugin/plugin.json
├── skills/c-drive-rescue/
│   ├── SKILL.md
│   └── scripts/
│       ├── setup_tools.ps1       # 下载 system-tools.exe
│       ├── disk_analyzer.ps1     # 磁盘扫描（降级）
│       ├── safe_cleanup.ps1      # 安全清理（降级）
│       ├── admin_cleanup.ps1     # 系统清理（降级）
│       └── migrate_to_d.ps1      # Junction 搬家
├── README.md
└── .gitignore
```

## ⚠️ 注意事项

- Junction 迁移前请关闭目标应用（IDE、剪映、豆包等）
- `powercfg -h off` 会禁用快速启动，按需执行
- 迁移到 D 盘的前提是 D 盘有足够空间
