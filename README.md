<div align="center">

<img src="OpenWriting/Assets.xcassets/AppIcon.appiconset/icon_128x128.png" width="128" alt="OpenWriting Logo" />

# OpenWriting

### AI 驱动的 macOS 原生长篇小说创作工作台

**在最美的写作环境里，讲最好的故事。**

[![macOS](https://img.shields.io/badge/macOS-14+-007AFF.svg?style=flat&logo=apple)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9-F05138.svg?style=flat&logo=swift)](https://swift.org/)
[![SwiftUI](https://img.shields.io/badge/SwiftUI-Apple%20Design-007AFF.svg)](https://developer.apple.com/xcode/swiftui/)
[![License](https://img.shields.io/badge/License-GPL%20v3-blue.svg)](LICENSE)
[![iCloud](https://img.shields.io/badge/iCloud-Sync-3693F5.svg?style=flat&logo=icloud)](https://developer.apple.com/icloud/)

[功能特性](#-核心功能) · [快速开始](#-快速开始) · [架构设计](#-技术架构) · [路线图](#-路线图) · [贡献](#-贡献)

---

</div>

## 🖋️ 一句话介绍

**OpenWriting** 是一款为长篇小说创作者打造的 macOS 原生应用。

它不是一个文本编辑器加上 AI 按钮——它是一套完整的 **创作操作系统**：从灵感萌芽到百万字完稿，管理你的大纲、章节、角色、伏笔、世界观，让 AI 成为你的搭档而非替代者。

---

## ✨ 核心功能

### 📖 多形态小说创作

支持 **短篇 / 中篇 / 长篇** 三种创作模式，新建项目时自动加载对应模板：

- **短篇** — 聚焦单一主题，轻量快速
- **中篇** — 多线叙事，结构化管理
- **长篇** — 百万字级连载，章节树 + 全局记忆

### 🌳 章节树工作区

不只是目录——这是一棵 **活的创作结构树**：

- 可视化章节层级，拖拽重组结构
- 每章独立草稿存档与回载
- 章节树结构化智能刷新（AI 辅助）
- 回写保护机制，防止误覆盖已定稿内容

### 🤖 AI 写作搭档

深度集成的 AI 能力，不是简单的「接一个 API」：

| 能力 | 说明 |
|------|------|
| **智能续写** | 基于上下文的连贯续写，保持角色语气一致 |
| **章节命名** | 根据内容自动生成章节标题 |
| **大纲生成** | 从构思到结构化大纲，一键生成 |
| **全局记忆刷新** | 角色状态、伏笔进展自动更新 |
| **章节树刷新** | 基于已有内容重新梳理章节结构 |

### 🧠 全局记忆系统

长篇连载的终极武器——AI 不会「忘记」：

- **角色弧线追踪** — 每个角色的性格、关系、成长轨迹
- **伏笔管理** — 埋下 → 推进 → 回收，全程追踪
- **场景进度** — 已写 / 进行中 / 待写，一目了然
- **结构备注** — 全局设定、世界观规则随时查阅

### ☁️ iCloud 无缝同步

基于 Apple 生态的原生同步体验：

- **Apple ID 登录** — 零注册，一键接入
- **CloudKit 私有数据库** — 你的创作只属于你
- **多设备同步** — Mac 上写到一半，另一台 Mac 继续
- **账户隔离** — 不同 Apple ID 的项目完全隔离

### 📚 参考资料管理

为你的世界观构建知识库：

- 导入外部文档（TXT / Markdown 等），自动编码识别
- 分类管理参考资料，写作时随时调取
- 文学引言库，灵感枯竭时给你一束光

### 🎨 macOS 原生体验

这不是 Electron，不是 Web 套壳——这是 **真正的 Mac 应用**：

- SwiftUI + AppKit 深度融合
- 原生窗口管理、工具栏、侧边栏
- 暗色 / 亮色主题自适应
- 系统级字体渲染与排版

---

## 🏗️ 技术架构

```
┌─────────────────────────────────────────────────────────────┐
│                      macOS 原生应用                          │
│  ┌───────────────────────────────────────────────────────┐  │
│  │                  SwiftUI 视图层                        │  │
│  │  ┌──────────┐ ┌──────────────┐ ┌───────────────────┐  │  │
│  │  │ 首页仪表 │ │ 写作台       │ │ 大纲工作区        │  │  │
│  │  │ 盘       │ │ WritingDesk  │ │ OutlineWorkspace  │  │  │
│  │  │ Home     │ │              │ │                   │  │  │
│  │  │ Dashboard│ │ · 章节编辑   │ │ · 章节树          │  │  │
│  │  │          │ │ · AI 续写    │ │ · 全局记忆        │  │  │
│  │  │ · 项目库 │ │ · 草稿存档   │ │ · 角色弧线        │  │  │
│  │  │ · 素材库 │ │ · 章节命名   │ │ · 伏笔追踪        │  │  │
│  │  │ · 概览   │ │ · 大纲生成   │ │ · 结构备注        │  │  │
│  │  └────┬─────┘ └──────┬───────┘ └─────────┬─────────┘  │  │
│  │       │              │                    │            │  │
│  │  ┌────▼──────────────▼────────────────────▼──────────┐ │  │
│  │  │              AppWindowCoordinator                  │ │  │
│  │  │         (窗口协调 · 状态注入 · 工具栏)             │ │  │
│  │  └──────────────────────┬─────────────────────────────┘ │  │
│  └─────────────────────────┼───────────────────────────────┘  │
│                            │                                  │
│  ┌─────────────────────────▼───────────────────────────────┐  │
│  │                    AppState 状态中心                      │  │
│  │  ┌─────────────┐ ┌──────────────┐ ┌──────────────────┐  │  │
│  │  │ 项目管理    │ │ 账户与同步   │ │ AI 写作服务      │  │  │
│  │  │ ProjectFile │ │ AccountSync  │ │ AIWritingService │  │  │
│  │  │ Store       │ │ +iCloudSync  │ │                  │  │  │
│  │  └──────┬──────┘ └──────┬───────┘ └────────┬─────────┘  │  │
│  │         │               │                  │            │  │
│  │  ┌──────▼──────┐ ┌──────▼───────┐ ┌────────▼─────────┐  │  │
│  │  │ 本地存储    │ │ CloudKit     │ │ LLM API          │  │  │
│  │  │ UserDefaults│ │ Private DB   │ │ (可配置端点)      │  │  │
│  │  │ + 文件系统  │ │              │ │                   │  │  │
│  │  └─────────────┘ └──────────────┘ └──────────────────┘  │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

**技术栈：**

- **语言：** Swift 5.9
- **UI 框架：** SwiftUI + AppKit (NSWindow / NSToolbar)
- **架构模式：** 协调器模式 (AppWindowCoordinator) + 状态中心 (AppState)
- **数据持久化：** UserDefaults + 文件系统 + CloudKit
- **同步：** Sign in with Apple + CloudKit Private Database
- **AI 集成：** 可配置 LLM 端点 (AIWritingService)
- **工程化：** Xcode 原生构建 + Shell 脚本 CI

---

## 🚀 快速开始

### 环境要求

- **macOS** 14.0+
- **Xcode** 最新稳定版
- **Apple Developer Team**（用于签名和 iCloud 能力）

### 安装与运行

```bash
# 克隆项目
git clone https://github.com/dashitongzhi/OpenWriting.git
cd OpenWriting

# 用 Xcode 打开
open OpenWriting.xcodeproj
```

在 Xcode 中：

1. 选择 `OpenWriting` target
2. 在 `Signing & Capabilities` 中确认：
   - ✅ `Team` — 有效的开发团队
   - ✅ `Sign In with Apple` — 已开启
   - ✅ `iCloud` → `CloudKit` — 已开启
3. 选择 `My Mac` → ▶️ Run

> 💡 如果 capability 或签名不完整，应用仍可本地运行，但账户登录和云同步会回退为本机保存状态。

### 命令行构建

```bash
# Debug 构建（无需签名）
./scripts/build-debug.sh

# 冒烟测试（构建 + diff 检查 + 文档校验）
./scripts/run-smoke-checks.sh
```

---

## 📁 项目结构

```
OpenWriting/
├── OpenWritingApp.swift              # 应用入口，macOS 生命周期
├── AppWindowCoordinator.swift        # 窗口协调、工具栏、运行时装配
├── AppState.swift                    # 应用主状态中心
├── AppState+Account.swift            # Apple 账户绑定与隔离加载
├── AppState+iCloudSync.swift         # iCloud 同步逻辑
├── AppState+Persistence.swift        # 持久化触发
├── AppRootView.swift                 # 根级导航容器（侧边栏 + 详情区）
├── DomainModels.swift                # 领域模型（项目 / 章节 / 角色 / 伏笔）
├── ProjectFileStore.swift            # 本地文件存储 + 账户 scope 隔离
├── ChapterTreeRefresh.swift          # 章节树结构化刷新与回写保护
├── AIWritingService.swift            # AI 写作服务（续写 / 命名 / 大纲 / 记忆）
├── AIWritingService+Prompts.swift    # AI 提示词模板
├── AccountSync.swift                 # Apple ID + CloudKit 快照读写
├── HomeDashboardView.swift           # 首页仪表盘
├── WritingDeskView.swift             # 正文写作主界面
├── WritingDeskSupportViews.swift     # 写作台共享布局组件
├── WritingDeskOutlineGeneratorSheet  # 大纲生成弹窗
├── OutlineWorkspacePanel.swift       # 章节树 + 全局记忆面板
├── AppearanceSettingsView.swift      # 外观与模型连接设置
├── ReferenceDocumentImporting.swift  # 参考资料导入
├── LiteraryQuoteLibrary.swift        # 文学引言库
├── NewProjectSheet.swift             # 新建项目弹窗
├── DashboardComponents.swift         # 仪表盘组件
├── DashboardTheme.swift              # 仪表盘主题
└── ...
├── OpenWriting.xcodeproj             # Xcode 工程配置
└── scripts/
    ├── build-debug.sh                # 命令行 Debug 构建
    ├── run-debug.sh                  # 运行 Debug 版本
    └── run-smoke-checks.sh           # 冒烟测试
```

---

## 🗺️ 路线图

### Phase 1 — 核心创作 ✅
- [x] 多形态小说项目（短篇 / 中篇 / 长篇）
- [x] 章节正文写作与草稿管理
- [x] 章节树工作区与结构化刷新
- [x] AI 续写 / 命名 / 大纲生成
- [x] 参考资料导入与管理
- [x] Apple ID + iCloud 同步

### Phase 2 — 智能记忆 🚧
- [x] 全局记忆刷新
- [ ] 角色关系图谱可视化
- [ ] 伏笔生命周期追踪（埋 → 推 → 回收）
- [ ] 场景时间线与多线叙事管理
- [ ] 世界观规则约束引擎

### Phase 3 — 创作增强
- [ ] 题材模板库（玄幻 / 都市 / 科幻 / 言情 / 悬疑…）
- [ ] 一致性审查（逻辑矛盾 / 角色 OOC / 设定冲突）
- [ ] 追读力分析（Hook 点 / 爽点 / 微兑现）
- [ ] RAG 检索增强（向量 + 关键词混合召回）

### Phase 4 — 生态与协作
- [ ] 可视化 Dashboard（角色关系图 / 剧情时间线 / 世界观地图）
- [ ] iOS / iPadOS 伴侣应用
- [ ] 导出为 EPUB / PDF / DOCX
- [ ] 社区模板与插件市场

---

## 🤝 贡献

欢迎提交 Issue 和 PR！

```bash
# Fork 并克隆
git clone https://github.com/your-username/OpenWriting.git
cd OpenWriting

# 创建功能分支
git checkout -b feature/amazing-feature

# 提交更改
git commit -m "feat: add amazing feature"

# 推送并创建 PR
git push origin feature/amazing-feature
```

---

## 📄 开源协议

本项目使用 [GPL v3](LICENSE) 协议。

---

## 🙏 致谢

- Apple SwiftUI & CloudKit — 提供了构建原生创作体验的基石
- 所有 AI 服务提供商 — 让 AI 写作成为可能

---

<div align="center">

**如果 OpenWriting 对你有帮助，请给一个 ⭐ Star 支持一下！**

Made with ❤️ for writers, by [dashitongzhi](https://github.com/dashitongzhi)

</div>
