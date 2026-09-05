<div align="center">

<img src="docs/hero.svg" alt="滴答 Dida" width="720" />

**Dock 常驻的眼药水 & 护眼提醒 · 为干眼症与过敏性结膜炎而生**

[![CI](https://github.com/blueDaydreaming725/dida/actions/workflows/ci.yml/badge.svg)](https://github.com/blueDaydreaming725/dida/actions/workflows/ci.yml)
[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-black?logo=apple&logoColor=white)](https://github.com/blueDaydreaming725/dida)
[![Swift](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white)](https://swift.org)
[![Release](https://img.shields.io/github/v/release/blueDaydreaming725/dida?include_prereleases&color=5A70FA)](https://github.com/blueDaydreaming725/dida/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-A05CF5.svg)](LICENSE)

原生 Swift。无菜单栏图标——面板住在 Dock 里；1Hz 单计时器 + 事件驱动，空闲 CPU ≈ 0%。

</div>

---

## 为什么是滴答

> 我有过敏性结膜炎和干眼症，一天要滴三次眼药水：先「富马」（抗过敏），间隔几分钟再滴「聚乙二醇」（人工泪液）。
> 现有番茄钟不懂"两步用药"，系统闹钟每次只提醒一半——于是有了滴答。

它只做三件事，并把每件事做到不打扰：

- 💊 **两步用药提醒** —— 到点弹出置顶确认窗：先滴富马 → 等待间隔 → 再弹聚乙二醇 → 本轮完成。不抢键盘焦点，但必须你亲自点「已滴完」。
- 👀 **20-20-20 护眼** —— 每 20 分钟一条轻量横幅：「看远处 20 秒」，20 秒自动消失。该法则有 2023 年临床研究支持（[文献](https://pubmed.ncbi.nlm.nih.gov/35963776/)）。
- 🤫 **会议模式** —— `⌥⌘M` 一键静音全部提醒，永不自动恢复，开会零尴尬。

## ✨ 特性

| | |
|---|---|
| 💊 **两步用药流程** | 富马 → 可调间隔（默认 5 分钟）→ 聚乙二醇，两步分色（蓝/紫），强制确认才消失 |
| ⌨️ **全局快捷键** | `⌥⌘B` 休息/回来 · `⌥⌘M` 静音/恢复，Carbon 实现，**无需辅助功能权限** |
| 🧘 **休息不评判** | 提前结束休息？没问题。应用只报告你实际休了多久（"闭眼眨眼也有效"），绝不说"未完成" |
| 🌙 **错过宽限** | 合盖睡眠唤醒后，30 分钟内错过的用药提醒立即补弹，超过则静默顺延 |
| 🔧 **完全可配置** | 时间点（1–6 个）、两药间隔、护眼间隔、休息时长、静音时长、药名——适配任何作息、任何人 |
| 🧊 **真·毛玻璃** | NSVisualEffectView behindWindow 实时模糊，蓝紫渐变主题，深浅色外观自适应 |
| 🔔 **可关音效** | 弹窗带 Glass 提示音，设置里一键关闭 |
| 🚀 **登录自启** | LaunchAgent 实现，无需签名，设置里一个开关 |

## ⌨️ 快捷键

| 快捷键 | 功能 |
|:---:|---|
| <kbd>⌥</kbd> <kbd>⌘</kbd> <kbd>B</kbd> | 开始休息 / 提前回来（默认 5 分钟自动回来，面板里可「再休 5 分钟」） |
| <kbd>⌥</kbd> <kbd>⌘</kbd> <kbd>M</kbd> | 静音所有提醒 / 恢复（会议模式，**手动恢复**） |

## 📦 安装

### 方式一：下载 Release（推荐）

从 [Releases](https://github.com/blueDaydreaming725/dida/releases) 下载 **`Dida-x.x.x.dmg`**，打开后把 **Dida** 拖入 **Applications** 文件夹（也可选 `zip` 压缩包，解压即用）。

> [!IMPORTANT]
> 应用采用 ad-hoc 签名（未加入 Apple 开发者计划），首次打开若提示"无法验证开发者"：
> ```bash
> xattr -cr /Applications/Dida.app
> ```
> 或在「系统设置 → 隐私与安全性」中点击「仍要打开」。

### 方式二：源码构建

需要 Xcode Command Line Tools（`xcode-select --install`）。

```bash
git clone https://github.com/blueDaydreaming725/dida.git
cd dida
./scripts/build.sh
open dist/Dida.app
```

首次启动会自动打开面板，Dock 常驻 HW 图标：**单击 Dock 图标**随时打开面板（关窗后提醒继续）。

![图标](docs/hero.svg)

## ⚙️ 配置

所有设置都在面板窗口的「设置」区，持久化于 `UserDefaults`：

| 配置项 | 默认值 | 范围 | 说明 |
|---|:---:|:---:|---|
| 用药时间点 | 11:00 / 15:00 / 20:00 | 1–6 个 | 每日用药时刻，可自由增删 |
| 两药间隔 | 5 分钟 | 1–30 分钟 | 滴完富马到聚乙二醇的等待 |
| 护眼提醒间隔 | 每 20 分钟 | 5–60 分钟 | 20-20-20 法则的"20 分钟" |
| 休息时长 | 5 分钟 | 1–30 分钟 | ⌥⌘B 主动休息的自动恢复时间 |
| 药名 | 富马 / 聚乙二醇 | 自由文本 | 换成你的药，给别人用也成立 |
| 提醒音效 | 开 | 开/关 | 用药弹窗的 Glass 提示音 |
| 登录时启动 | 关 | 开/关 | LaunchAgent 自启动 |

## 🧠 设计原则

1. **坚持但不纠缠** —— 用药必须确认，但绝不抢键盘焦点（你可以在弹窗上继续打字）；
2. **休息是你的，应用只记账** —— 提前结束永远被允许，且只报告事实（"已休息 2 分 04 秒"）；
3. **不怕忘** —— 一切暂停都会自动恢复：静音 60 分钟后回来，休息 5 分钟后回来，错过 30 分钟内补弹；
4. **性能即尊重** —— 无 Electron、无 WebView、无常驻轮询网络。1Hz 单计时器 + 事件驱动，点开面板即现。

<details>
<summary><strong>🏗️ 项目结构</strong></summary>

```
dida/
├── Sources/dida/
│   ├── DidaApp.swift        # @main 入口，accessory 模式
│   ├── AppDelegate.swift    # 菜单栏图标 / Popover / 热键接线 / 音效
│   ├── AppState.swift       # 核心状态机：1Hz tick、两步用药、静音/休息、错过宽限
│   ├── Store.swift          # 设置持久化 + LaunchAgent 登录自启
│   ├── Models.swift         # MedTime / nextOccurrence / 时间格式化
│   ├── HotKeys.swift        # Carbon RegisterEventHotKey
│   ├── Windows.swift        # TopPanel（置顶/不抢焦点/滑入）、弹窗与横幅控制器
│   └── Views.swift          # SwiftUI：毛玻璃、蓝紫主题、脉冲环、震动、面板
├── scripts/build.sh         # swift build + 手工组装 .app + ad-hoc 签名
├── docs/hero.svg            # README 横幅
└── .github/workflows/ci.yml # macOS 构建 + --demo 冒烟测试
```

</details>

## ❓ FAQ

<details>
<summary>到点了没弹提醒？</summary>

点 Dock 图标打开面板看状态徽标（提醒中/已静音/休息中）；已静音时 ⌥⌘M 恢复。另外确认系统时间与用药时间点设置。
</details>

<details>
<summary>想看一眼所有动效？</summary>

demo 模式：5 秒后弹用药确认窗（含震动+脉冲环+音效），15 秒后弹护眼横幅，各自动效完整播放：

```bash
dist/Dida.app/Contents/MacOS/dida --demo
```

</details>

<details>
<summary>睡眠唤醒后漏掉的提醒去哪了？</summary>

30 分钟内：立即补弹；超过 30 分钟：静默顺延到下一个时间点（半夜醒来不会再被凌晨的提醒轰炸）。
</details>

<details>
<summary>眼药水开封后能用多久？</summary>

多数滴眼液开封后 **4 周** 即应更换，即使没滴完。滴答在每轮完成时也会顺便提醒这一点。
</details>

<details>
<summary>为什么不用 SwiftUI 声明式生命周期 / 为什么自己组 .app？</summary>

为了让它只依赖 SwiftPM 和 Command Line Tools——不需要完整 Xcode 工程就能克隆构建。
AppKit 侧用 NSStatusItem + NSPanel 直接控制窗口层级与焦点行为，比多包装一层更少意外。
</details>

## 🗺️ Roadmap

- [ ] 导出/导入配置（JSON）
- [ ] 用药历史统计与 4 周开封倒计时
- [ ] 多语言（English UI）
- [ ] Homebrew Cask 一键安装

## 🤝 贡献

欢迎 Issue 与 PR。本地验证：

```bash
swift build && ./scripts/build.sh
```

改 UI 请保持两条底线：**弹窗永远不抢键盘焦点**，**休息永远可以随时结束**。

## 📄 License

[MIT](LICENSE) © 2026 blueDaydreaming725

## 🙏 致谢

- [impeccable](https://github.com/pbakaus/impeccable) —— 本项目的设计方法与质量底线
- [Talens-Estarelles et al., 2023](https://pubmed.ncbi.nlm.nih.gov/35963776/) —— 20-20-20 法则对数字眼疲劳与干眼有效性的临床证据
- [Al-Mohtaseb et al., 2021](https://pmc.ncbi.nlm.nih.gov/articles/PMC8439964/) —— 屏幕使用与干眼症关系的系统综述

<div align="center">
<sub>如果你也被干眼困扰，愿这滴「滴答」帮你把药准时点上。⭐️</sub>
</div>
