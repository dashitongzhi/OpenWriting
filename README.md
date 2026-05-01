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

## 💡 为什么需要 OpenWriting？

> **全球网络文学市场规模已超过 500 亿美元，中文网文读者超过 5 亿。但创作者依然在用 Word 和记事本写百万字长篇。**

长篇小说创作面临三个根本性难题：

| 痛点 | 现状 | OpenWriting 的答案 |
|------|------|-------------------|
| **记忆崩溃** | 写到 50 万字，角色血型、前文伏笔、时间线全部混乱 | 三层记忆架构，AI 永不遗忘 |
| **节奏失控** | 连载压力下爽点密度下降、感情线断档、读者流失 | Strand Weave 节奏系统，实时红线监控 |
| **幻觉泛滥** | AI 写作工具信口开河，角色前后矛盾、设定自相冲突 | 防幻觉三定律 + 六维质量审查 |

**OpenWriting 不是"文本编辑器 + AI 按钮"——它是第一款真正为百万字长篇设计的创作操作系统。**

---

## ✨ 核心功能

### 🧠 三层记忆架构 — 让 AI 永不遗忘

长篇连载的终极武器。这是目前唯一解决了"AI 写长篇会遗忘"问题的创作工具。

```
┌─────────────────────────────────────────────────────┐
│  Working Memory（工作记忆）     ← 写作时实时组装     │
│  · 当前章节大纲 · 最近几章摘要 · 角色即时状态       │
├─────────────────────────────────────────────────────┤
│  Episodic Memory（情景记忆）    ← 结构化历史证据     │
│  · 状态变化 · 关系演变 · 出场记录 · 按时间窗口检索   │
├─────────────────────────────────────────────────────┤
│  Semantic Memory（语义记忆）    ← 长期事实缓存       │
│  · 角色状态 · 剧情事实 · 世界观 · 伏笔 · 关系网     │
│  · 自动去重 · 冲突检测 · 超阈值压缩                 │
└─────────────────────────────────────────────────────┘
```

每条记忆带生命周期状态：`active` → `outdated` → `contradicted` → `tentative`，写前注入、写后沉淀，形成闭环。

### 🛡️ 防幻觉三定律 — 终结 AI 胡编乱造

AI 写长篇最大的敌人是「编」。OpenWriting 用三条铁律约束 AI：

| 定律 | 说明 | 执行方式 |
|------|------|----------|
| **大纲即法律** | 遵循大纲，不擅自发挥 | 写前强制加载章节大纲 |
| **设定即物理** | 遵守设定，不自相矛盾 | 内置一致性审查引擎 |
| **发明需识别** | 新实体必须入库管理 | 自动提取新角色/设定并入库 |

### 🔍 六维质量审查 — 每章自动打分

写完即审，六个维度量化评估，告别"感觉还行"：

| 维度 | 检查重点 | 为什么重要 |
|------|----------|-----------|
| 🎯 **爽点密度** | High-point 密度与质量 | 读者留存的核心指标 |
| 🔒 **设定一致性** | 战力/地点/时间线矛盾 | 一旦崩设定，读者立刻弃书 |
| 🎭 **角色 OOC** | 人物行为是否偏离人设 | 角色崩坏是长篇第一杀手 |
| 📐 **节奏比例** | 主线/感情线/世界观平衡 | 单调节奏导致审美疲劳 |
| 🔗 **叙事连贯** | 场景切换与逻辑通顺 | 断裂感破坏沉浸体验 |
| 🪝 **追读力** | 钩子强度、期待管理 | 决定读者是否点"下一章" |

### 🎵 Strand Weave 节奏系统 — 数据驱动的叙事节奏

控制长篇小说的叙事节奏，避免单一化。这是从顶级网文作者的写作模式中提炼出的节奏模型：

| Strand | 含义 | 理想占比 | 说明 |
|--------|------|----------|------|
| **Quest** | 主线剧情 | 60% | 推动核心冲突 |
| **Fire** | 感情线 | 20% | 人物关系发展 |
| **Constellation** | 世界观扩展 | 20% | 背景/势力/设定 |

**节奏红线自动监控：**
- 🚨 Quest 连续超过 5 章 → 警告：读者会审美疲劳
- 🚨 Fire 断档超过 10 章 → 警告：感情线读者流失
- 🚨 Constellation 断档超过 15 章 → 警告：世界观单薄

### 🎨 37 种题材模板 — 一键套用专业配置

内置主流网文题材，每个模板包含：钩子策略、爽点模式、节奏参数、写作指令、反面模式。

| 分类 | 题材 |
|------|------|
| **玄幻修仙** | 修仙 · 系统流 · 高武 · 西幻 · 无限流 · 末世 · 科幻 |
| **都市现代** | 都市异能 · 都市日常 · 都市脑洞 · 现实题材 · 电竞 · 直播文 |
| **言情** | 古言 · 宫斗宅斗 · 青春甜宠 · 豪门总裁 · 职场婚恋 · 民国言情 · 幻想言情 · 现言脑洞 · 女频悬疑 · 种田 · 年代 |
| **悬疑** | 规则怪谈 · 悬疑脑洞 · 悬疑灵异 · 克苏鲁 · 狗血言情 · 替身文 · 知乎短篇 |

支持复合题材（最多 2 个），如 `都市脑洞+规则怪谈`、`修仙+系统流`。

### 📖 多形态小说创作

支持 **短篇 / 中篇 / 长篇** 三种创作模式：

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
| **六维审稿** | 写完即审，量化评分 + 问题定位 |
| **增强续写** | 自动注入记忆、节奏、反面模式上下文 |

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

## 📊 为什么是现在？

### 市场机遇

| 指标 | 数据 |
|------|------|
| 全球网络文学市场 | **500+ 亿美元**（2025） |
| 中文网文读者 | **5.06 亿**（CNNIC 2024） |
| 网文作者数量 | **2000+ 万**（中国作协） |
| AI 写作工具增长率 | **年增 340%**（2024-2025） |

### 竞争格局

| 工具 | 长篇记忆 | 节奏控制 | 防幻觉 | 原生体验 | 题材模板 |
|------|:--------:|:--------:|:------:|:--------:|:--------:|
| **OpenWriting** | ✅ 三层架构 | ✅ Strand Weave | ✅ 三定律 | ✅ macOS 原生 | ✅ 37 种 |
| Notion + AI | ❌ | ❌ | ❌ | ❌ Web | ❌ |
| Scrivener | ❌ | ❌ | ❌ | ⚠️ 旧架构 | ❌ |
| Sudowrite | ⚠️ 有限 | ❌ | ❌ | ❌ Web | ❌ |
| NovelCrafter | ⚠️ 有限 | ❌ | ⚠️ 有限 | ❌ Web | ⚠️ 有限 |

**OpenWriting 是唯一同时解决记忆、节奏、幻觉三大问题的创作工具。**

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
- **AI 集成：** 可配置 LLM 端点 (AIWritingService) — 支持 OpenAI / Anthropic / 自定义
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

## 📋 功能清单

| 功能 | 状态 | 说明 |
|------|:----:|------|
| 多形态创作（短/中/长篇） | ✅ | 自动加载对应创作模板 |
| 章节树工作区 | ✅ | 可视化层级 · 拖拽重组 · 回写保护 |
| AI 续写 / 命名 / 大纲 | ✅ | 基于上下文的连贯生成 |
| 全局记忆刷新 | ✅ | 角色状态、伏笔进展自动更新 |
| 参考资料导入 | ✅ | 自动编码识别 · 分类管理 |
| Apple ID + iCloud 同步 | ✅ | CloudKit 私有数据库 |
| 文学引言库 | ✅ | 灵感激发 |
| macOS 原生 UI | ✅ | SwiftUI + AppKit · 暗色/亮色 |
| 三层记忆架构 | ✅ | Working / Episodic / Semantic |
| 防幻觉三定律 | ✅ | 大纲即法律 · 设定即物理 · 发明需识别 |
| 六维质量审查 | ✅ | 爽点 · 一致性 · OOC · 节奏 · 连贯 · 追读力 |
| Strand Weave 节奏 | ✅ | 主线 60% · 感情线 20% · 世界观 20% |
| 37 种题材模板 | ✅ | 玄幻 · 都市 · 言情 · 悬疑 · 复合题材 |
| 增强版 AI 写作 | ✅ | 记忆注入 + 节奏感知 + 反面模式规避 |
| RAG 检索增强 | 🔜 | 向量嵌入 + BM25 + Rerank 混合召回 |
| 伏笔生命周期追踪 | 🔜 | 埋下 → 推进 → 回收 |
| 角色关系图谱 | 🔜 | 可视化角色关系网络 |
| 导出 EPUB / PDF | 🔜 | 多格式输出 |

---

## 🗺️ 路线图

### Phase 1 — 核心创作 ✅
- [x] 多形态小说项目（短篇 / 中篇 / 长篇）
- [x] 章节正文写作与草稿管理
- [x] 章节树工作区与结构化刷新
- [x] AI 续写 / 命名 / 大纲生成
- [x] 参考资料导入与管理
- [x] Apple ID + iCloud 同步

### Phase 2 — 智能记忆 ✅
- [x] 全局记忆刷新
- [x] 三层记忆架构（Working / Episodic / Semantic）
- [x] 记忆分桶：角色状态 · 剧情事实 · 世界观 · 时间线 · 伏笔 · 关系
- [x] 记忆状态管理：active / outdated / contradicted / tentative
- [x] 自动去重、冲突检测、超阈值压缩
- [x] 写前注入 + 写后沉淀闭环

### Phase 3 — 防幻觉引擎 ✅
- [x] 大纲即法律：写前强制加载章节大纲
- [x] 设定即物理：一致性审查引擎
- [x] 发明需识别：新实体自动提取入库
- [x] 六维审查系统（爽点 / 一致性 / OOC / 节奏 / 连贯 / 追读力）
- [x] Strand Weave 节奏监控与红线告警
- [x] 37 种题材模板（支持复合题材）

### Phase 4 — 创作增强 🚧
- [x] 增强版 AI 写作（记忆 + 节奏 + 反面模式注入）
- [ ] RAG 检索增强（向量嵌入 + BM25 + Rerank 混合召回）
- [ ] 伏笔生命周期追踪（埋 → 推 → 回收）
- [ ] 角色关系图谱可视化
- [ ] 场景时间线与多线叙事管理

### Phase 5 — 生态与协作
- [ ] 可视化 Dashboard（角色关系图 / 剧情时间线 / 世界观地图）
- [ ] iOS / iPadOS 伴侣应用
- [ ] 导出为 EPUB / PDF / DOCX
- [ ] 社区模板与插件市场

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
├── AIWritingService+Enhanced.swift   # 增强版 AI 写作（记忆 + 节奏注入）
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
├── GenreTemplates.swift              # 37 种题材模板引擎
├── ChapterQualityReviewer.swift      # 六维质量审查系统
├── WritingMemoryBuckets.swift        # 三层记忆架构
├── StrandWeaveTracker.swift          # Strand Weave 节奏追踪
├── NovelProject+WebnovelIntegration.swift  # DomainModels 集成扩展
├── PrewriteValidator.swift           # 写前校验
└── ...
├── OpenWriting.xcodeproj             # Xcode 工程配置
└── scripts/
    ├── build-debug.sh                # 命令行 Debug 构建
    ├── run-debug.sh                  # 运行 Debug 版本
    └── run-smoke-checks.sh           # 冒烟测试
```

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
- 网文创作者社区 — 真实需求驱动产品设计

---

<div align="center">

**如果 OpenWriting 对你有帮助，请给一个 ⭐ Star 支持一下！**

Made with ❤️ for writers, by [dashitongzhi](https://github.com/dashitongzhi)

</div>
