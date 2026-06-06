# C-Drive Rescue — 清理规则库

## 规则格式

采用 **BleachBit 兼容 JSON 格式**，每条规则是一个长度为 4-6 的数组：

```json
[
  ["规则名称", "路径模板", "类型", "是否移到回收站", "描述文字", "危险标记"],
  ...
]
```

## 字段说明

| 索引 | 字段 | 类型 | 说明 |
|------|------|------|------|
| 0 | name | string | 规则显示名称 |
| 1 | path | string | 清理路径，支持 `%ENVVAR%` 环境变量展开 |
| 2 | type | `"dir"` / `"file"` / `"glob"` | 清理类型：整个目录、单个文件、通配符匹配 |
| 3 | recycle | bool | `true`=移到回收站，`false`=直接永久删除 |
| 4 | description | string | 规则描述文字 |
| 5 | isSafe (可选) | bool | `true`=安全规则（不删个人数据），默认 true |

## 路径模板变量

| 模板 | 展开示例 |
|------|----------|
| `%WINDIR%` | `C:\Windows` |
| `%TEMP%` | `C:\Users\{user}\AppData\Local\Temp` |
| `%LOCALAPPDATA%` | `C:\Users\{user}\AppData\Local` |
| `%APPDATA%` | `C:\Users\{user}\AppData\Roaming` |
| `%ALLUSERSPROFILE%` | `C:\ProgramData` |
| `%PROGRAMFILES%` | `C:\Program Files` |
| `%PROGRAMFILES(X86)%` | `C:\Program Files (x86)` |
| `%USERPROFILE%` | `C:\Users\{user}` |

## 分类文件

| 文件 | 覆盖范围 | 规则数 |
|------|----------|--------|
| `system_rules.json` | Windows 临时文件、更新缓存、错误报告、回收站 | 17 |
| `browser_rules.json` | Edge / Chrome / Firefox / IE 浏览器缓存 | 16 |
| `dev_tools_rules.json` | JetBrains / VS Code / VS / pip / npm / Cargo / Go / Maven | 20 |
| `cn_apps_rules.json` | 微信 / QQ / 钉钉 / 飞书 / 剪映 / 豆包 / WPS / 迅雷等 | 27 |
| `game_rules.json` | Steam / Epic / Unity / Unreal / NVIDIA / AMD | 18 |
| `creative_rules.json` | Autodesk / Adobe / Blender / DaVinci / Figma / VS Code | 18 |
| `large_drive_rules.json` | 非系统盘大文件清理：UE缓存、百度网盘安装包、Steam、录屏 | 16 |
| **合计** | | **132 条规则** |

## 贡献新规则

欢迎 PR！添加规则只需：

1. 在对应的 `.json` 文件中新增一行数组
2. 确保路径使用 `%ENVVAR%` 模板变量（不要硬编码绝对路径）
3. 对可能包含用户数据的路径，把 `recycle` 设为 `true`
4. 真正危险的规则，把 `isSafe` 设为 `false`（索引 5）

## 致谢

规则格式借鉴 [BleachBit](https://www.bleachbit.org/) 和 [c_cleaner_plus](https://github.com/Kiowx/c_cleaner_plus) 的设计。
