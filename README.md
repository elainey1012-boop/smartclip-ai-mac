# ✨ SmartClip AI for Mac

> 中文名：剪贴板助手 · 专属于 macOS 的智能剪贴板


> Mac 上的 Win+V 式多剪贴板 · 菜单栏常驻 · Swift 原生 · 零依赖 · 纯本地运行不上传任何数据

**SmartClip AI** is a Win+V style smart clipboard manager for macOS — with a unique AI-era feature: it auto-filters voice-to-text noise from your clipboard history. Pure Swift, zero dependencies.

![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-black) ![Language](https://img.shields.io/badge/language-Swift-orange) ![License](https://img.shields.io/badge/license-MIT-green)

## ✨ 功能特性

- **多条剪贴板**：自动记录最近 500 条复制内容（文本 / 图片 / 文件），重启不丢
- **卡片面板**：`⌥V` 全局快捷键呼出 / 收起，Win+V 同款手感；点菜单栏 📋 图标也可以
- **点卡片直接粘贴**：点击任意卡片 = 复制 + 自动粘贴进你刚才的输入框，不用再按 ⌘V
- **图片支持**：图片卡片直接显示缩略图，点击粘贴 PNG+TIFF 双格式（兼容微信等只认 TIFF 的应用）
- **文件支持**：Finder 里 ⌘C 复制的文件可记录、可恢复
- **置顶 / 删除 / 搜索**：悬停卡片出 📌 置顶和 ✕ 删除按钮；顶部搜索框实时过滤
- **🛡 语音转文字智能过滤**：独创功能——语音输入工具借道剪贴板粘贴的文字（macOS 语音工具的通病）会被自动识别并拦截，不污染剪贴板历史。原理：识别「旧内容 → 语音文字 → 旧内容还原」三连击指纹
- **智能去重**：同一内容只存一份，刚用过的自动挪到最前
- **开机自启**：面板内一键开关

## 📦 安装

```bash
git clone https://github.com/你的用户名/smartclip-ai-mac.git
```


### 方式一：一键安装（推荐）

1. 下载本仓库（Code → Download ZIP），解压
2. 双击 **`一键安装.command`**（如提示"无法验证开发者"，右键 → 打开 → 再点「打开」）
3. 脚本会自动编译并安装到 `~/Applications/剪贴板助手.app`

> 首次运行如果没有编译器，系统会弹窗引导安装 Apple 命令行工具，装完再双击一次安装脚本即可。

### 方式二：手动编译

```bash
swiftc -O main.swift -o 剪贴板助手 \
  -framework AppKit -framework ServiceManagement -framework Carbon

# 打包成 .app（目录结构见下）后运行，或直接运行二进制
./剪贴板助手 &
```

<details>
<summary>.app 目录结构</summary>

```
剪贴板助手.app/
└── Contents/
    ├── Info.plist          # 参考一键安装.command 内的模板
    └── MacOS/
        └── 剪贴板助手       # 编译产物
```
</details>

## 🔑 权限说明（每台 Mac 一次性设置）

| 权限 | 作用 | 设置位置 |
|---|---|---|
| 辅助功能 | 点卡片自动粘贴（模拟 ⌘V） | 系统设置 → 隐私与安全性 → 辅助功能 → 添加本应用 |
| 菜单栏显示 | 显示 📋 图标（macOS 26 Tahoe 需要） | 系统设置 → 菜单栏 → 允许在菜单栏中显示 |

> 💡 如果你自己修改代码重新编译后发现权限失效：macOS 按「代码签名」匹配授权，重新编译会改变临时签名。解决办法是用固定证书签名（`codesign --sign <证书> <app>`），或重新在辅助功能里添加一次。

## 🎮 使用

| 操作 | 效果 |
|---|---|
| `⌥V` | 呼出 / 收起面板 |
| 点卡片 | 复制并自动粘贴到刚才的输入框 |
| 悬停卡片 → 📌 / ✕ | 置顶 / 删除该条 |
| 顶部搜索框 | 实时过滤历史记录 |
| 💬 开头的条目 | 语音转文字的临时条目，15 分钟自动消失（点击可转永久） |

## 🛠 技术细节

- Swift + AppKit + Carbon（全局热键）+ CryptoKit（图片去重），**无任何第三方依赖**
- 20Hz 轮询剪贴板 + `CGEventSource` 键鼠时间戳判断 + 还原指纹识别，实现语音过滤
- 面板尺寸用约束钉死 `contentLayoutGuide`（防止 Auto Layout 把未激活面板压瘪的坑）
- 数据本地存储（UserDefaults + Application Support），不上传任何数据

## 📄 License

[MIT](LICENSE)
