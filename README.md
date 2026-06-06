# 🛟 C-Drive Rescue — 拯救C盘

[![Version](https://img.shields.io/badge/version-3.0.0-blue)](https://github.com/buyicoder/C-Drive-Rescue)
[![Rules](https://img.shields.io/badge/rules-116-green)](https://github.com/buyicoder/C-Drive-Rescue/tree/main/rules)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

> Windows C 盘深度清理 Claude Code 插件。**116 条 BleachBit 兼容规则** + 四引擎驱动 + 三级回退 Junction 搬家。一句「C盘满了」自动触发，安全释放 25–40GB。

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

## 🏗️ 四引擎架构 + 规则库

```
你: "C盘满了"  →  C-Drive Rescue 自动激活
        │
        ▼
┌──────────────────────────────────────────────────────┐
│                    C-Drive Rescue v3                  │
├──────────┬───────────┬───────────┬──────────┬────────┤
│ Engine ①│ Engine ②  │ Engine ③ │ Engine ④ │ Rules  │
│ JSON     │ system-   │ Windows   │Junction  │ Store  │
│ Rule     │ tools.rs  │ Built-in  │Migration │ 116    │
│ Engine   │ 4万⭐     │           │3-Tier    │ rules  │
│----------│-----------│-----------│----------│--------│
│ Primary  │Secondary  │ Fallback  │ Unique   │6 cats  │
│----------│-----------│-----------│----------│--------│
│BleachBit │ Rust CLI  │ dism      │Tier1:    │system  │
│compat    │ 35 rules  │ cleanmgr  │  rename  │browser │
│rule scan │ dry-run   │ vssadmin  │Tier2:    │devtools│
│+ clean   │ + MCP     │           │  robocopy│cn_apps │
│          │           │           │Tier3:    │game    │
│          │           │           │  .partial│creative│
└──────────┴───────────┴───────────┴──────────┴────────┘
```

| 引擎 | 借鉴项目 | 做什么 |
|------|----------|--------|
| ① **JSON 规则引擎** | [c_cleaner_plus](https://github.com/Kiowx/c_cleaner_plus) (1090⭐) | 116 条 BleachBit 兼容规则，规则与代码分离，逐项 DryRun 预览 |
| ② **system-tools.rs** | [system-tools.rs](https://github.com/VDHewei/system-tools.rs) (4万⭐) | 35 条内置清理规则，Rust CLI 零依赖 |
| ③ **Windows 内置** | [Dism++](https://github.com/Chuyu-Team/Dism-Multi-language) (4万⭐) | DISM 组件清理 / cleanmgr / 系统还原点裁剪 |
| ④ **三级回退迁移** | [WindowsClear](https://github.com/tanaer/WindowsClear) (848⭐) | rename→robocopy→.partial 三级搬家 + 回滚 + 进程检测 + 操作历史 |

> 引擎①②③④互相独立——一个挂了不影响其他。首次运行自动下载 system-tools.exe。

---

## 📋 五个阶段

| # | 阶段 | 干了什么 | 需要管理员？ |
|---|------|----------|:---:|
| ① | **磁盘分析** | 116 条规则扫描 + system-tools.rs 35 规则，定位空间大户 | ❌ |
| ② | **安全清理** | JSON 引擎 safe 模式：系统/浏览器/IDE/开发工具/国产软件缓存 | ❌ |
| ③ | **系统清理** | 全部 116 条规则 + DISM 组件 + cleanmgr + NVIDIA + 回收站 | ✅ |
| ④ | **文件夹搬家** | 三级回退 Junction 迁移：rename→robocopy→.partial → D盘 | ✅ |
| ⑤ | **效果报告** | 前后对比表 + 每条规则释放明细 + 剩余大户清单 | ❌ |

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
├── .claude-plugin/plugin.json      # 插件元数据 (v3.0.0)
├── skills/c-drive-rescue/
│   ├── SKILL.md                    # 五阶段清理指令
│   └── scripts/
│       ├── engine.ps1              # 🆕 JSON 规则引擎（核心）
│       ├── migrate_to_d.ps1        # 🆕 三级回退 Junction 搬家
│       ├── safe_cleanup.ps1        # 安全清理（调用 engine）
│       ├── admin_cleanup.ps1       # 系统清理（调用 engine + dism）
│       ├── disk_analyzer.ps1       # 磁盘分析（只读）
│       └── setup_tools.ps1         # 下载 system-tools.exe
├── rules/                          # 🆕 清理规则库
│   ├── system_rules.json           # Windows 系统 (17 条)
│   ├── browser_rules.json          # 浏览器缓存 (16 条)
│   ├── dev_tools_rules.json        # 开发工具 (20 条)
│   ├── cn_apps_rules.json          # 国产软件 (27 条)
│   ├── game_rules.json             # 游戏平台 (18 条)
│   ├── creative_rules.json         # 创意工具 (18 条)
│   └── README.md                   # 规则格式说明
├── i18n/                           # 🆕 国际化
│   ├── zh_cn.json
│   └── en_us.json
├── LICENSE (MIT)
└── README.md
```

---

## 🏅 借鉴项目

本插件的架构设计借鉴了以下优秀开源项目的最佳实践：

| 项目 | Stars | 借鉴的设计 |
|------|-------|------------|
| [c_cleaner_plus](https://github.com/Kiowx/c_cleaner_plus) | 1,090 | JSON 规则引擎、BleachBit 兼容格式、逐规则回收站开关、规则商店 |
| [WindowsClear](https://github.com/tanaer/WindowsClear) | 848 | 三级回退 Junction 迁移、进程锁定检测、操作历史回滚 |
| [Dism++](https://github.com/Chuyu-Team/Dism-Multi-language) | 40,000+ | DISM 组件清理策略、WinSxS 深度清理思路 |
| [system-tools.rs](https://github.com/VDHewei/system-tools.rs) | 40,000+ | 系统垃圾/浏览器/开发工具/国产软件清理规则分类 |
| [WindowsCleaner](https://github.com/darkmatter2048/WindowsCleaner) | 3,800 | 五阶段清理流程、自动清理调度 |

## ⚠️ 注意事项

- 搬家（阶段④）前请关闭目标应用——IDE、剪映、豆包等
- `powercfg -h off` 会禁用 Windows 快速启动，按需选择
- 搬家到 D 盘的前提是 D 盘有足够剩余空间
- 一次清不完可以多次跑——每次扫描结果不同
- 规则库欢迎 PR——格式见 `rules/README.md`
