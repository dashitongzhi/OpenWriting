<div align="center">

<img src="OpenWriting/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="132" alt="OpenWriting app icon" />

# OpenWriting

### 原生 macOS 长篇小说创作工作台

**把大纲、记忆、伏笔、节奏、审查和 AI 续写收束到同一个专业写作系统里。**

<p>
  <strong>简体中文</strong> ·
  <a href="README.md">English</a>
</p>

<p>
  <a href="https://www.apple.com/macos/"><img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-111827?style=for-the-badge&logo=apple&logoColor=white&labelColor=000000"></a>
  <a href="https://swift.org/"><img alt="Swift" src="https://img.shields.io/badge/Swift-5.9-F05138?style=for-the-badge&logo=swift&logoColor=white&labelColor=1f2937"></a>
  <a href="https://developer.apple.com/xcode/swiftui/"><img alt="SwiftUI" src="https://img.shields.io/badge/SwiftUI-%E5%8E%9F%E7%94%9F%E4%BD%93%E9%AA%8C-0A84FF?style=for-the-badge&logo=swift&logoColor=white&labelColor=1f2937"></a>
  <img alt="License GPL v3" src="https://img.shields.io/badge/License-GPL%20v3-10B981?style=for-the-badge&labelColor=1f2937">
</p>

<p>
  <a href="#产品愿景">产品愿景</a> ·
  <a href="#核心系统">核心系统</a> ·
  <a href="#技术架构">技术架构</a> ·
  <a href="#对比">对比</a> ·
  <a href="#快速开始">快速开始</a>
</p>

</div>

---

## 产品愿景

OpenWriting 面向的是一个很具体、也很难的场景：作者正在写一部长篇小说，章节会越来越多，人物关系会变复杂，伏笔和世界观会跨越几十甚至上百章，而 AI 不能在第 80 章忘掉第 8 章已经立下的规则。

多数 AI 写作工具把长篇问题当成“多塞一点上下文”。OpenWriting 的判断更工程化：长篇写作不是一个 prompt 问题，而是一个由**结构化记忆、写前约束、写后审查、节奏控制、素材检索和项目同步**共同组成的系统问题。

| 创作现场 | 常见工具的处理方式 | OpenWriting 的处理方式 |
| --- | --- | --- |
| AI 忘记前文设定 | 继续追加上下文，越写越重 | 7-bucket 结构化记忆，按生命周期沉淀与压缩 |
| 章节越来越散 | 靠作者手动回看大纲 | 章节树、故事契约和 Strand Weave 共同约束 |
| 角色行为跑偏 | 生成后靠肉眼发现 | 写前校验 + 九维质量审查 + 阻断问题分类 |
| 伏笔埋了没人管 | 靠笔记或脑内记忆 | openLoop / readerPromise / PlotThread 结构化追踪 |
| 资料太多找不到 | 手动复制相关材料 | BM25 + ContextRanker 排序后注入上下文 |

> OpenWriting 的目标不是替作者“自动写完一本书”，而是让作者拥有一个能长期维护故事一致性的专业工作台。

---

## 产品表面

| 区域 | 作用 | 设计重点 |
| --- | --- | --- |
| 首页工作台 | 项目概览、入口导航、账号状态、素材与创作空间 | 快速回到正在写的项目，减少管理负担 |
| 写作台 | 正文编辑、章节保存、AI 续写、上下文刷新 | 写作优先，工具靠近但不干扰 |
| 章节树工作区 | 大纲层级、章节结构、全局记忆、长篇支撑面板 | 让长篇结构可见、可维护、可回写 |
| 质量审查面板 | 维度评分、阻断问题、非阻断建议 | 把“感觉不对”变成可处理的问题列表 |
| 题材模板库 | 玄幻、都市、言情、悬疑等网文题材参数 | 模板不是标签，而是钩子、爽点、节奏和反模式 |
| 设置与同步 | 外观、模型连接、Apple ID、CloudKit | 原生 macOS 应用的账号隔离和数据同步体验 |

---

## 核心系统

### 1. 7-Bucket 结构化记忆

OpenWriting 把长篇记忆拆成 7 类，并为每一类设置独立优先级、去重策略和生命周期。这样 AI 不再依赖一大坨历史文本，而是拿到“当前章节真正需要知道的事实”。

```text
worldRule        Priority 0   设定即物理：世界规则、修炼限制、势力格局
characterState   Priority 1   角色状态：境界、伤势、身份、情绪
relationship     Priority 2   人物关系：师徒、敌对、合作、爱慕
storyFact        Priority 3   剧情事实：已发生事件、关键发现、决策节点
openLoop         Priority 4   未回收伏笔：悬念、谜题、待兑现信息
readerPromise    Priority 5   对读者的承诺：对决、揭示、关系确认
timeline         Priority 6   时间线：季节推进、时间跳跃、历史节点
```

每条记忆都带生命周期：`active`、`outdated`、`contradicted`、`tentative`。新事实不会粗暴覆盖旧事实，而是保留历史以支持冲突检测和后续审查。

### 2. 防幻觉三定律

| 定律 | 产品含义 | 工程落点 |
| --- | --- | --- |
| 大纲即法律 | 没有大纲或章节目标时，不允许 AI 随意发挥 | `PrewriteValidator.checkOutline()` |
| 设定即物理 | 世界观规则优先于生成流畅度 | `PrewriteValidator.checkSettings()` |
| 发明需识别 | 新角色、新地点、新设定必须被识别并纳入管理 | `PrewriteValidator.checkEntityTracking()` |

这不是一句提示词，而是一组写前 gate：在生成正文之前，OpenWriting 会先判断项目是否具备继续写作的结构条件。

### 3. 九维统一质量审查

写完之后，OpenWriting 用 100 分扣分制审查章节，critical 问题直接变成阻断项。

| 维度 | 检查重点 | 价值 |
| --- | --- | --- |
| 爽点密度 | High-point 密度与兑现质量 | 追读和情绪反馈 |
| 设定一致性 | 战力、地点、时间线、规则冲突 | 防止崩设定 |
| 角色 OOC | 行为是否偏离人设 | 保持角色可信 |
| 节奏比例 | 主线、感情线、世界观比例 | 避免审美疲劳 |
| 叙事连贯 | 场景切换、逻辑推进 | 保持沉浸感 |
| 追读力 | 钩子、期待管理、章末势能 | 让读者愿意点下一章 |
| AI 味检测 | 模板句、空泛描写、本地预检 | 降低生成痕迹 |

```text
critical  -35   阻断问题
high      -15   严重问题
medium     -6   中等问题
low        -2   轻微问题

score = max(0, 100 - totalPenalty)
pass  = no critical issues && score >= 60
```

### 4. Strand Weave 节奏系统

OpenWriting 用 Quest / Fire / Constellation 三条叙事线追踪章节节奏，让长篇小说不会只剩推进主线，也不会长期断掉感情线或世界观扩展。

| Strand | 建议占比 | 代表内容 |
| --- | ---: | --- |
| Quest | 60% | 主线目标、冲突推进、阶段性胜负 |
| Fire | 20% | 关系升温、情绪牵引、人物羁绊 |
| Constellation | 20% | 世界观、势力、历史、规则展开 |

红线示例：

- Quest 连续超过 5 章：提醒主线可能过载，读者容易疲劳。
- Fire 断档超过 10 章：提醒关系线可能失温。
- Constellation 断档超过 15 章：提醒世界观可能变薄。
- 累计记录超过 10 章后，比例偏离理想值超过 50%：提示整体节奏失衡。

### 5. 题材模板与反模式

OpenWriting 内置 37 种题材模板，支持最多 2 个题材复合。每个模板不是简单分类，而是一套可注入写作流程的结构参数：

```text
Genre Template
├─ HookStrategy          危机 / 悬念 / 渴望 / 情绪 / 选择
├─ CoolPointPattern      装逼打脸 / 扮猪吃虎 / 身份掉马 / 逆袭兑现
├─ Rhythm Parameters     stagnationThreshold / setupTolerance
├─ Writing Directives    正向写作指令
├─ Anti Patterns         反 AI 写作模式
└─ CBN Nodes             Chapter Beginning / Progression / Ending
```

### 6. 3-Pass AI 写作管线

OpenWriting 不把 AI 续写当成一次性生成，而是拆成更可控的多阶段流程。

```text
Plan       temperature 0.42   生成写作拍点，先定结构
Write      temperature 0.82   生成候选正文，保留创造性
Revise     temperature 0.34   修订精化，压低漂移
Supplement temperature 0.72   字数不足时补齐
```

上下文注入按相关性排序，包含草稿、结构化记忆、全局记忆、章节树 focus、Strand 节奏、题材模板、反模式和参考资料检索结果。

---

## 技术架构

OpenWriting 是一个 SwiftUI + AppKit 混合的原生 macOS 应用。SwiftUI 负责主要界面表达，AppKit 负责窗口生命周期、工具栏与 macOS 级体验协调。

```text
OpenWritingApp
  └─ AppWindowCoordinator
      └─ AppRuntime
          ├─ AppState
          │   ├─ ProjectFileStore
          │   ├─ ICloudProjectStore
          │   ├─ AIWritingService
          │   └─ ModelConnectionConfigurationStore
          ├─ AppRootView
          │   ├─ HomeDashboardView
          │   ├─ WritingDeskView
          │   ├─ OutlineWorkspacePanel
          │   └─ QualityReviewDashboardView
          └─ Domain Layer
              ├─ NovelProject / ChapterDraft / ReferenceDocument
              ├─ WritingMemoryBuckets
              ├─ StrandWeaveTracker
              ├─ ChapterQualityReviewer
              ├─ ContextRanker
              └─ LongformStorySystem
```

### 技术亮点

| 模块 | 文件 | 亮点 |
| --- | --- | --- |
| AI 服务与 BM25 | `OpenWriting/AIWritingService.swift` | 自实现 Okapi BM25，支持 CJK unigram / bigram / trigram |
| 上下文排序 | `OpenWriting/ContextRanker.swift` | 新鲜度、实体重叠、信号强度三维评分 |
| 记忆桶 | `OpenWriting/WritingMemoryBuckets.swift` | bucket 独立 dedup key，生命周期感知去重 |
| 质量审查 | `OpenWriting/ChapterQualityReviewer.swift` | severity penalty 模型与阻断问题分类 |
| 故事契约 | `OpenWriting/LongformStorySystem.swift` | master / volume / chapter / review / prewrite / writingBrief |
| 记忆提取 | `OpenWriting/MemoryExtractionService.swift` | 单次 LLM 调用提取 7 类结构化记忆 |
| 题材模板 | `OpenWriting/GenreTemplateEngine.swift` | 37 种题材模板与复合题材解析 |
| 项目导出 | `OpenWriting/ProjectExportService.swift` | 备份 JSON、Markdown、DOCX、EPUB 成书文件 |
| CloudKit 同步 | `OpenWriting/AccountSync.swift` | Apple ID 状态识别与私有数据库快照 |

---

## 对比

### 与通用 AI 写作工具相比

| 能力 | OpenWriting | Notion AI | Scrivener | Sudowrite | NovelCrafter |
| --- | :---: | :---: | :---: | :---: | :---: |
| 原生 macOS 工作台 | 是 | Web | 桌面端 | Web | Web |
| 结构化长篇记忆 | 7 buckets + 生命周期 | 否 | 否 | 部分 | 部分 |
| 写前防幻觉 gate | 是 | 否 | 否 | 否 | 部分 |
| 九维质量审查 | 是 | 否 | 否 | 部分 | 部分 |
| Strand 节奏监控 | 是 | 否 | 否 | 否 | 否 |
| 伏笔生命周期 | 是 | 否 | 手动 | 否 | 部分 |
| 题材模板参数化 | 37 templates | 否 | 否 | 有限 | 部分 |
| BM25 参考资料检索 | 内置 | 否 | 否 | 否 | 部分 |
| iCloud 私有同步 | CloudKit | 否 | 手动 | 否 | 否 |

### 技术深度对比

| 领域 | OpenWriting | 常见实现 |
| --- | --- | --- |
| 记忆管理 | 分类、去重、生命周期、压缩、冲突检测 | 追加文本片段 |
| 上下文选择 | BM25 + ContextRanker + 项目状态信号 | 最近几段历史文本 |
| 写作流程 | Plan / Write / Revise / Supplement | 单次生成 |
| 质量模型 | 维度化审查 + severity penalty | 模糊建议 |
| 长篇约束 | 故事契约 + 三定律 + 阻断 gate | 靠 prompt 约束 |
| 原生体验 | SwiftUI、AppKit、CloudKit、Apple ID | Web UI 或通用编辑器 |

---

## 快速开始

### 环境要求

- macOS 14.0+
- Xcode 最新稳定版
- Apple Developer Team，用于 Sign in with Apple 与 iCloud/CloudKit 能力

### 本地运行

```zsh
git clone https://github.com/dashitongzhi/OpenWriting.git
cd OpenWriting
open OpenWriting.xcodeproj
```

在 Xcode 中：

1. 选择 `OpenWriting` target。
2. 在 `Signing & Capabilities` 中确认 `Team`、`Sign In with Apple`、`iCloud` 与 `CloudKit`。
3. 选择 `My Mac`，点击 Run。

### 命令行构建

```zsh
./scripts/build-debug.sh
```

常用脚本：

| 命令 | 用途 |
| --- | --- |
| `./scripts/build-debug.sh` | Debug 构建 |
| `./scripts/run-debug.sh` | 运行 Debug 版本 |
| `./scripts/git-preflight.sh` | 本地 Git ref / 默认分支前置检查 |
| `./scripts/run-smoke-checks.sh` | 冒烟检查 |
| `./scripts/run-longform-quality-checks.sh` | 长篇质量检查 |
| `./scripts/run-longform-evals.sh` | 长篇管线评测 |
| `./scripts/run-all-checks.sh` | 聚合检查 |

---

## 项目结构

```text
OpenWriting/
├─ OpenWriting.xcodeproj
├─ OpenWriting/
│  ├─ OpenWritingApp.swift
│  ├─ AppWindowCoordinator.swift
│  ├─ AppState.swift
│  ├─ AppRootView.swift
│  ├─ HomeDashboardView.swift
│  ├─ WritingDeskView.swift
│  ├─ OutlineWorkspacePanel.swift
│  ├─ QualityReviewDashboardView.swift
│  ├─ AIWritingService.swift
│  ├─ AIWritingService+Enhanced.swift
│  ├─ AIWritingService+Prompts.swift
│  ├─ DomainModels.swift
│  ├─ WritingMemoryBuckets.swift
│  ├─ StrandWeaveTracker.swift
│  ├─ ChapterQualityReviewer.swift
│  ├─ ContextRanker.swift
│  ├─ LongformStorySystem.swift
│  ├─ MemoryExtractionService.swift
│  ├─ GenreTemplateEngine.swift
│  ├─ ProjectExportService.swift
│  └─ AccountSync.swift
├─ LongformEvals/
├─ Tests/
├─ scripts/
├─ INDEX.md
├─ README.md
└─ README.zh-CN.md
```

更多源码职责说明见 [`INDEX.md`](INDEX.md)。

---

## 路线图

| 阶段 | 状态 | 重点 |
| --- | :---: | --- |
| 核心工作台 | 已完成 | 多形态小说项目、写作台、章节树、参考资料、iCloud 同步 |
| 结构化记忆 | 已完成 | 7-bucket 记忆、生命周期、去重、冲突检测、压缩 |
| 防幻觉引擎 | 已完成 | 三定律、写前校验、九维质量审查、阻断分类 |
| 长篇智能系统 | 已完成 | Strand Weave、题材模板、反模式、故事契约、ContextRanker |
| 评测体系 | 进行中 | 长篇管线评测、质量检查脚本、回归样例 |
| 成书发布 | 计划中 | 更完整的 EPUB / PDF / DOCX 导出与成书流程 |
| 生态扩展 | 计划中 | 角色关系图谱、社区模板、插件与跨端伴侣应用 |

---

## 贡献

欢迎提交 Issue 和 PR。这个项目的核心价值来自真实创作压力，所以最有价值的反馈通常是：

- 长篇项目写到中后期时，哪里还会记忆断裂。
- 哪些审查结果不够准确或不够可执行。
- 哪些题材模板缺少关键爽点、钩子或反模式。
- 哪些 macOS 原生体验仍然不够顺手。

开发前建议先阅读：

- [`INDEX.md`](INDEX.md)
- [`Tests/README.md`](Tests/README.md)

---

## 开源协议

OpenWriting 使用 GPL v3 开源协议。

---

<div align="center">

**OpenWriting 为按章节、弧线、承诺与后果思考的长篇作者而生。**

<sub>用 SwiftUI、CloudKit 和对故事连续性的固执尊重打造。</sub>

</div>
