# 🛟 C-Drive Rescue — 拯救C盘

[![Version](https://img.shields.io/badge/version-2.0.0-blue)](https://github.com/buyicoder/C-Drive-Rescue)

> Windows C 盘深度清理 Claude Code 插件。三引擎驱动，一句「C盘满了」自动触发，安全释放 25–40GB。

---

## ⚡ 安装（10 秒）

在 Claude Code 中输入：

```
/plugin install github.com/buyicoder/C-Drive-Rescue
```

或者直接把这句话甩给 Claude Code：

> **帮我把 github.com/buyicoder/C-Drive-Rescue 安装为插件**

装完就能用。不用配环境变量，不用手动下载任何东西。

---

## 🗣️ 怎么用

安装后，对 Claude Code 说下面任意一句即可触发：

- `C盘满了`
- `清理C盘`
- `释放C盘空间`
- `C盘红了`
- `clean C drive`

插件会自动：扫描→清理→系统深度清理→大文件夹搬家→出报告。

---

## 🏗️ 它怎么做到的（三引擎）

```
你: "C盘满了"
        │
        ▼
┌──────────────────────────────────┐
│        C-Drive Rescue            │
├───────────┬──────────┬───────────┤
│ Engine ①  │ Engine ② │ Engine ③  │
│ system-   │ Windows  │ Junction  │
│ tools.rs  │ Built-in │ Migration │
│           │          │           │
│ 35 条规则  │ dism     │ robocopy  │
│ Rust CLI  │ cleanmgr │ + mklink  │
│ 自动下载   │ 系统自带  │ 搬家到D盘  │
└───────────┴──────────┴───────────┘
```

| 引擎 | 来源 | 干什么 |
|------|------|--------|
| ① **system-tools.rs** | [GitHub 4万⭐](https://github.com/VDHewei/system-tools.rs) | 主力清理：系统垃圾、浏览器缓存、IDE缓存、微信/QQ/剪映/Steam等35条规则 |
| ② **Windows 内置** | 系统自带 | DISM组件清理、cleanmgr磁盘清理、系统还原点裁剪 |
| ③ **Junction 迁移** | 本插件独有 | robocopy + NTFS 软链接，把 AppData 大文件夹透明搬家到 D 盘 |

> ① 首次运行自动下载（~5MB），下载失败自动降级为纯 PowerShell → 清理能力不减。

---

## 📋 五个阶段

| # | 阶段 | 干了什么 | 需要管理员？ |
|---|------|----------|:---:|
| ① | **磁盘分析** | 扫描所有驱动器，定位空间大户，展示前因后果 | ❌ |
| ② | **安全清理** | 临时文件、浏览器/IDE/应用缓存、pip/npm/NuGet | ❌ |
| ③ | **系统清理** | Windows更新缓存、DISM组件、NVIDIA驱动、回收站 | ✅ |
| ④ | **文件夹搬家** | robocopy + Junction 把大文件夹搬到 D 盘 | ✅ |
| ⑤ | **效果报告** | 前后对比表，每条释放了多少，还剩什么 | ❌ |

---

## 🎯 真实效果

> 在一台 200GB C 盘、使用率 88% 的电脑上实测：

| | 清理前 | 清理后 | 变化 |
|------|--------|--------|------|
| C 盘已用 | 176 GB | 137 GB | **-39 GB** |
| C 盘可用 | 24 GB | 63 GB | **+39 GB** |
| 使用率 | 88% 🔴 | **68.5%** 🟢 | -19.5% |

---

## 📁 文件结构

```
C-Drive-Rescue/
├── .claude-plugin/plugin.json      # 插件元数据
├── skills/c-drive-rescue/
│   ├── SKILL.md                    # 五阶段清理指令
│   └── scripts/
│       ├── setup_tools.ps1         # 自动下载 system-tools.exe
│       ├── disk_analyzer.ps1       # 磁盘扫描（降级用）
│       ├── safe_cleanup.ps1        # 安全清理（降级用）
│       ├── admin_cleanup.ps1       # 系统清理（降级用）
│       └── migrate_to_d.ps1        # Junction 搬家（独有）
├── README.md
└── .gitignore
```

---

## ⚠️ 注意事项

- 搬家（阶段④）前请关闭目标应用——IDE、剪映、豆包等
- `powercfg -h off` 会禁用 Windows 快速启动，按需选择
- 搬家到 D 盘的前提是 D 盘有足够剩余空间
- 一次清不完可以多次跑——每次扫描结果不同
