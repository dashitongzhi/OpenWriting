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

[功能特性](#-核心功能) · [技术创新](#-技术架构与创新) · [对比分析](#-竞品对比) · [路线图](#-路线图) · [贡献](#-贡献)

---

</div>

## 💡 为什么需要 OpenWriting？

> **全球网络文学市场规模已超过 500 亿美元，中文网文读者超过 5 亿。但创作者依然在用 Word 和记事本写百万字长篇。**

长篇小说创作有三个根本性技术难题，OpenWriting 是**全球首个系统性解决**这三个难题的创作工具：

| 痛点 | 根因 | OpenWriting 的方案 |
|------|------|-------------------|
| **记忆崩溃** | AI 模型上下文窗口有限，长篇写到后期完全遗忘前文设定 | **7-Bucket 结构化记忆 + 三层记忆架构** |
| **节奏失控** | 连载压力下作者无法感知全局叙事平衡，读者逐渐流失 | **Strand Weave 节奏系统 + 红线自动监控** |
| **幻觉泛滥** | AI 写作时擅自编造角色、设定、剧情，与前文矛盾 | **防幻觉三定律 + 写前校验 + 写后审查** |

---

## ✨ 核心功能

### 🧠 7-Bucket 结构化记忆系统

**目前唯一真正解决"AI 写长篇会遗忘"问题的创作工具。**

传统 AI 写作工具的"记忆"只是简单的上下文注入——把前文一段段塞进 prompt，这在大约 3 万字就开始失效了。

OpenWriting 的解决方案是**将记忆结构化、分桶管理、带生命周期**，让 AI 在写长篇时能像人类作者一样"记住重要的，忘记临时的"：

```
┌─────────────────────────────────────────────────────────────┐
│  世界观规则 (worldRule)     Priority 0 — 设定即物理           │
│  · 修炼体系限制 · 势力格局 · 地理设定                        │
├─────────────────────────────────────────────────────────────┤
│  角色状态 (characterState)  Priority 1                       │
│  · 境界变化 · 情绪状态 · 伤势情况 · 身份转变                  │
├─────────────────────────────────────────────────────────────┤
│  人物关系 (relationship)    Priority 2                       │
│  · 师徒/敌对/爱慕 等关系的建立与变化                          │
├─────────────────────────────────────────────────────────────┤
│  剧情事实 (storyFact)       Priority 3                       │
│  · 重要事件 · 转折发现 · 决策节点                            │
├─────────────────────────────────────────────────────────────┤
│  未回收伏笔 (openLoop)      Priority 4                       │
│  · 埋下的悬念 · 待解之谜                                    │
├─────────────────────────────────────────────────────────────┤
│  对读者的承诺 (readerPromise) Priority 5                     │
│  · 承诺的对决 · 揭示 · 关系确认                              │
├─────────────────────────────────────────────────────────────┤
│  时间线 (timeline)          Priority 6                       │
│  · 季节推进 · 时间跳跃 · 历史事件                            │
└─────────────────────────────────────────────────────────────┘
```

**每条记忆带 4 状态生命周期**：`active` → `outdated` → `contradicted` → `tentative`，新值自动覆盖旧值但保留历史用于冲突检测。

**智能去重**：不同 bucket 用不同 dedup key（`subject|field` vs `subject` vs `subject|chapter`），精准去重而非粗暴覆盖。

**阈值压缩**：超过 500 条自动触发三级压缩——保留最新 outdated、清理已回收伏笔、合并 50 章前的旧时间线。

---

### 🛡️ 防幻觉三定律

AI 写长篇最大的敌人是「编」——编一个不存在的设定、编一个死掉的角色复活、编一个矛盾的世界规则。

OpenWriting 用三条铁律从架构层面消灭幻觉：

| 定律 | 执行机制 | 技术实现 |
|------|----------|----------|
| **大纲即法律** | 写前强制校验大纲存在性，空大纲直接阻断写作 | `PrewriteValidator.checkOutline()` |
| **设定即物理** | 写前检查全局记忆，世界观记忆缺失时告警 | `PrewriteValidator.checkSettings()` |
| **发明需识别** | 新实体必须入库管理，章节树结构缺失时告警 | `PrewriteValidator.checkEntityTracking()` |

---

### 🔍 九维统一质量审查

写完即审，告别"感觉还行"——用 severity penalty 模型量化每个问题：

```
阻断 (critical) → -35 分
严重 (high)     → -15 分
中等 (medium)   → -6 分
轻微 (low)      → -2 分

最终分数 = 100 - Σ(penalties)
```

| 维度 | 检查重点 | 为什么重要 |
|------|----------|-----------|
| 🎯 **爽点密度** | High-point 密度与质量 | 读者留存的核心指标 |
| 🔒 **设定一致性** | 战力/地点/时间线矛盾 | 一旦崩设定，读者立刻弃书 |
| 🎭 **角色 OOC** | 人物行为是否偏离人设 | 角色崩坏是长篇第一杀手 |
| 📐 **节奏比例** | 主线/感情线/世界观平衡 | 单调节奏导致审美疲劳 |
| 🔗 **叙事连贯** | 场景切换与逻辑通顺 | 断裂感破坏沉浸体验 |
| 🪝 **追读力** | 钩子强度、期待管理 | 决定读者是否点"下一章" |
| 🤖 **AI 味检测** | 本地预检，无 API 调用 | 识别"缓缓/淡淡/微微"等模板句 |

---

### 🎵 Strand Weave 节奏系统

这是从顶级网文作者的写作模式中提炼出的**数据驱动叙事节奏控制模型**：

```
理想比例：Quest 60% · Fire 20% · Constellation 20%

Quest (主线剧情)   — 推动核心冲突
Fire (感情线)      — 人物关系发展
Constellation (世界观扩展) — 背景/势力/设定
```

**红线自动监控**（超过阈值立即告警）：
- 🚨 Quest 连续超过 5 章 → 警告：读者审美疲劳
- 🚨 Fire 断档超过 10 章 → 警告：感情线读者流失
- 🚨 Constellation 断档超过 15 章 → 警告：世界观单薄
- 🚨 比例偏离理想值超过 50% 且记录 ≥ 10 章 → 警告：节奏失衡

**下一章推荐**：优先级排序——严重告警 > 断档告警 > 比例亏空最大者

---

### 🎨 37 种题材模板

内置主流网文题材，**每个模板是结构化的写作参数集**而非简单分类：

```
题材模板包含：
├── 钩子策略 (HookStrategy) — 5 种钩子类型：危机/悬念/渴望/情绪/选择
├── 爽点模式 (CoolPointPattern) — 8 种爽点：装逼打脸/扮猪吃虎/身份掉马...
├── 节奏参数 — stagnationThreshold / setupTolerance
├── 写作指令 (writingDirectives) — 正向引导
├── 反面模式 (antiPatterns) — 8 条反 AI 写作规则
└── CBN 结构节点 — Chapter Beginning/Progression/Ending 三节点
```

支持**复合题材**（最多 2 个合并），如 `都市脑洞+规则怪谈`、`修仙+系统流`。

---

### 🤖 AI 写作搭档

**3-Pass 写作管线**——不是单次生成，而是分段精化：

```
温度 0.42 → 生成写作拍点（结构化，控制节奏）
温度 0.82 → 生成候选正文（高随机，鼓励创意）
温度 0.34 → 修订精化（低温度，微调）
不足时补充 (0.72) → 字数不够触发补充生成
```

**8 层上下文注入**（按相关性排序）：
1. 草稿箱当前正文
2. 结构化记忆 buckets
3. 全局记忆快照
4. 章节树 focus
5. Strand 节奏上下文
6. 题材模板约束
7. 已积累反模式
8. 参考文档 / 相关章节（BM25 检索）

**BM25 检索**：自实现 Okapi BM25，支持 CJK 字符 unigram + bigram + trigram 分词，无需外部向量库。

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

---

## 🏗️ 技术架构与创新

### 核心技术创新

OpenWriting 的架构设计解决了长篇 AI 写作的三个世界性难题。以下是具体技术实现：

#### 1. BM25 检索系统（[AIWritingService.swift:360-520](OpenWriting/AIWritingService.swift#L360-L520)）

自实现 Okapi BM25，支持 CJK unigram + bigram + trigram 分词：
```swift
private struct BM25Scorer {
    private static let k1: Double = 1.2
    private static let b: Double = 0.75
    // CJK: U+4E00-U+9FFF, Extension A/B/C-F
    // 同时支持 Latin 脚本
}
```
用于 reference document 排名和已保存章节摘要检索，零外部依赖。

#### 2. 上下文排序器 ContextRanker（[ContextRanker.swift](OpenWriting/ContextRanker.swift)）

3D 相关性评分：
- **新鲜度 (30%)**: 每次保存的章节树/记忆权重 > 静态项目配置
- **实体重叠 (40%)**: F1-like 分数衡量章节上下文与各 section 的实体重叠度
- **信号强度 (30%)**: 含警告(+0.08)、伏笔(+0.10)、张力关键词(+0.06)；占位符"暂无"扣-0.15

#### 3. 生命周期感知去重（[WritingMemoryBuckets.swift:38-47](OpenWriting/WritingMemoryBuckets.swift#L38-L47)）

```swift
var dedupKey: String {
    switch category {
    case .characterState, .relationship, .worldRule, .storyFact:
        return "\(subject)|\(field)"  // 复合 key
    case .timeline:
        return "\(subject)|\(sourceChapter)"
    case .openLoop, .readerPromise:
        return subject  // 仅主题
    }
}
```

新值写入时自动将旧 active 降级为 outdated，保留历史用于冲突检测。

#### 4. 质量审查 Penalty 模型（[ChapterQualityReviewer.swift:115-139](OpenWriting/ChapterQualityReviewer.swift#L115-L139)）

```swift
enum ReviewSeverity: Double, Codable, CaseIterable {
    case critical: penalty = 35
    case high: penalty = 15
    case medium: penalty = 6
    case low: penalty = 2
}

func computePenaltyScore() -> Int {
    max(0, 100 - totalPenalty)
}
```

Critical 问题直接 set `hasBlockingIssues = true`，通过率 = `!hasBlockingIssues && overallScore >= 60`。

#### 5. 长篇故事契约系统（[LongformStorySystem.swift](OpenWriting/LongformStorySystem.swift)）

6 个子契约组成完整创作契约束：
- master / volume / chapter / review / prewrite / writingBrief
- 三定律写入每个契约：「大纲即法律」「设定即物理」「发明需识别」
- 章节提交追踪：planned nodes vs covered nodes vs missed nodes

#### 6. AI 记忆提取服务（[MemoryExtractionService.swift](OpenWriting/MemoryExtractionService.swift)）

单次 LLM 调用同时提取 7 类记忆：
```json
{
  "chapter": 42,
  "characterStates": [{"subject": "主角", "field": "境界", "value": "突破到元婴", "evidence": "体内元婴破壳而出"}],
  "relationships": [...],
  "worldRules": [...],
  ...
}
```
Stable ID 使用 FNV-like 64-bit 哈希保证跨模块 ID 一致性。

#### 7. 伏笔生命周期管理（[DomainModels.swift:897-1128](OpenWriting/DomainModels.swift#L897-L1128)）

5 状态完整生命周期：`active` → `advanced` → `resolved/retconned/overdue`，advance 可多次调用，isOverdue 自动检测超时。

#### 8. 结构化叙事线追踪（[DomainModels.swift:1129-1360](OpenWriting/DomainModels.swift#L1129-L1360)）

`PlotThread` 替代 raw `activeThreadsNotes` 字符串：
- 5 种类型：quest / fire / constellation / subplot / character
- 关键事件节点：`ThreadEvent` 含 chapter / title / eventType
- `ThreadEventType`: start / development / climax / resolution / transition

#### 9. 复合题材解析（[GenreTemplateEngine.swift:430-512](OpenWriting/GenreTemplateEngine.swift#L430-L512)）

```swift
// splitCompositeGenre() 只在 "奇幻与冒险的旅程" 时不解体
// 因为"冒险" <= 6chars，"的" 前面不是 "与" 时不触发分割
func splitCompositeGenre(_ input: String) -> [String] {
    // hasYuSeparator() 守卫：只有当 与 左右两边都 <=6 才分割
}
```

#### 10. Per-Project 内存缓存（[NovelProject+WebnovelIntegration.swift:10-65](OpenWriting/NovelProject+WebnovelIntegration.swift#L10-L65)）

```swift
private static var memoryBucketsCache: [String: MemoryBuckets] = [:]
private static var strandWeaveCache: [String: StrandWeaveState] = [:]
private static var antiPatternsCache: [String: [String]] = [:]
// NSLock 保护，避免重复 JSON 解码
```

#### 11. PersistedTimestampCodec 多格式解析（[DomainModels.swift:3-173](OpenWriting/DomainModels.swift#L3-L173)）

支持：Unix timestamp / ISO8601 / "今天 HH:mm" / "昨天 HH:mm" / bare clock time，`nonisolated` 保证并发安全。

---

## 📊 竞品对比

### 与通用 AI 写作工具对比

| 功能 | OpenWriting | Notion AI | Scrivener | Sudowrite | NovelCrafter |
|------|:-----------:|:---------:|:---------:|:---------:|:------------:|
| **长篇记忆架构** | ✅ 7-bucket + 生命周期 | ❌ 无结构 | ❌ 无 | ⚠️ 简单片段 | ⚠️ 有限 |
| **防幻觉机制** | ✅ 三定律 + 写前校验 | ❌ 无 | ❌ 无 | ❌ 无 | ⚠️ 有限 |
| **叙事节奏控制** | ✅ Strand Weave 红线 | ❌ 无 | ❌ 无 | ❌ 无 | ❌ 无 |
| **AI 三阶段管线** | ✅ Plan/Write/Revision | ⚠️ 单次生成 | ❌ 无 | ⚠️ 简单续写 | ⚠️ 有限 |
| **质量审查模型** | ✅ 九维 penalty 评分 | ❌ 无 | ❌ 无 | ⚠️ 模糊反馈 | ⚠️ 有限 |
| **题材模板系统** | ✅ 37 种 + 复合题材 | ❌ 无 | ❌ 无 | ⚠️ 5 种 | ⚠️ 有限 |
| **原生 macOS** | ✅ SwiftUI+AppKit | ❌ Web | ❌ 旧架构 | ❌ Web | ❌ Web |
| **iCloud 同步** | ✅ CloudKit | ❌ 无 | ⚠️ 手动 | ❌ 无 | ❌ 无 |
| **结构化伏笔追踪** | ✅ 5 状态生命周期 | ❌ 无 | ❌ 无 | ❌ 无 | ❌ 无 |
| **BM25 检索** | ✅ 自实现 | ❌ 无 | ❌ 无 | ❌ 无 | ❌ 无 |

### 技术深度对比

| 特性 | OpenWriting | 主流 AI 写作工具 |
|------|-------------|-----------------|
| **记忆去重策略** | 7 bucket 独立 dedup key | 简单文本追加 |
| **冲突检测** | 同 dedup key 多 active 检测 | ❌ 无 |
| **压缩策略** | 三级压缩 + timeline 合并 | ❌ 无 |
| **反模式注入** | 8 条 AntiAIWritingGuide 写入 prompt | ❌ 无 |
| **AI 味本地预检** | ✅ 无 API 调用，检测 5 类特征 | ❌ 无 |
| **上下文排序** | ContextRanker 3D 评分 | ❌ 无 |
| **Stable ID** | FNV-like 64-bit 哈希跨模块一致 | ❌ 无 |

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
| 7-bucket 结构化记忆 | ✅ | 角色状态 · 剧情事实 · 世界观 · 时间线 · 伏笔 · 关系 · 承诺 |
| 防幻觉三定律 | ✅ | 大纲即法律 · 设定即物理 · 发明需识别 |
| 九维统一质量审查 | ✅ | 100分扣分制 + 阻断分类 |
| Strand Weave 节奏 | ✅ | 主线 60% · 感情线 20% · 世界观 20% |
| 37 种题材模板 | ✅ | 玄幻 · 都市 · 言情 · 悬疑 · 复合题材 |
| 增强版 AI 写作 | ✅ | 记忆注入 + 节奏感知 + 反面模式规避 |
| 结构化伏笔追踪 | ✅ | 5 状态生命周期管理 |
| 结构化叙事线追踪 | ✅ | 5 类型 + 关键事件节点 |
| AI 记忆提取 | ✅ | 单次 LLM 调用提取 7 类记忆 |
| BM25 检索 | ✅ | 自实现 CJK 分词 |
| ContextRanker 排序 | ✅ | 3D 相关性评分 |
| 长篇故事契约系统 | ✅ | 6 子契约 + 三定律 |
| 导出 EPUB/PDF | 🔜 | 多格式输出 |
| 角色关系图谱 | 🔜 | 可视化角色关系网络 |

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
- [x] 7-bucket 结构化记忆
- [x] 记忆状态管理：active / outdated / contradicted / tentative
- [x] 自动去重、冲突检测、超阈值压缩
- [x] 写前注入 + 写后沉淀闭环
- [x] AI 记忆提取服务

### Phase 3 — 防幻觉引擎 ✅
- [x] 大纲即法律：写前强制校验
- [x] 设定即物理：一致性审查引擎
- [x] 发明需识别：新实体自动提取入库
- [x] 九维审查系统（100-base 惩罚评分 + 阻断分类）
- [x] Strand Weave 节奏监控与红线告警
- [x] 37 种题材模板（支持复合题材）
- [x] 8 条 AntiAIWritingGuide 反模式注入

### Phase 4 — 创作增强 ✅
- [x] 增强版 AI 写作（记忆 + 节奏 + 反面模式注入）
- [x] 结构化伏笔追踪（5 状态生命周期）
- [x] 结构化叙事线追踪（5 类型 + 关键事件）
- [x] 长篇故事契约系统（6 子契约）
- [x] ContextRanker 3D 上下文排序
- [ ] RAG 检索增强（向量嵌入 + BM25 + Rerank 混合召回）

### Phase 5 — 生态与协作
- [ ] 角色关系图谱可视化
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
├── AppRootView.swift                 # 根级导航容器
├── DomainModels.swift                # 领域模型（项目/章节/伏笔/叙事线）
├── ProjectFileStore.swift            # 本地文件存储 + 账户 scope 隔离
├── ChapterTreeRefresh.swift          # 章节树结构化刷新与回写保护
├── AIWritingService.swift            # AI 服务 + BM25 检索 + 3-Pass 管线
├── AIWritingService+Enhanced.swift   # 增强版 AI 写作（8层上下文注入）
├── AIWritingService+Prompts.swift    # AI 提示词模板
├── ContextRanker.swift               # 3D 相关性评分上下文排序
├── AccountSync.swift                 # Apple ID + CloudKit 快照读写
├── HomeDashboardView.swift           # 首页仪表盘
├── WritingDeskView.swift             # 正文写作主界面
├── WritingDeskSupportViews.swift     # 写作台共享布局组件
├── OutlineWorkspacePanel.swift       # 章节树 + 全局记忆面板
├── AppearanceSettingsView.swift      # 外观与模型连接设置
├── ReferenceDocumentImporting.swift  # 参考资料导入
├── LiteraryQuoteLibrary.swift        # 文学引言库
├── NewProjectSheet.swift             # 新建项目弹窗
├── DashboardComponents.swift         # 仪表盘组件
├── GenreTemplateEngine.swift         # 37 种题材模板 + AntiAIWritingGuide
├── ChapterQualityReviewer.swift      # 九维质量审查（100-base penalty 评分）
├── WritingMemoryBuckets.swift        # 7-bucket 结构化记忆系统
├── StrandWeaveTracker.swift          # Strand Weave 节奏追踪与红线监控
├── MemoryExtractionService.swift     # AI 记忆提取服务
├── LongformStorySystem.swift         # 长篇故事契约系统
├── NovelProject+WebnovelIntegration.swift  # DomainModels 集成扩展
├── PrewriteValidator.swift           # 写前校验（防幻觉三定律）
├── ForeshadowManagementView.swift   # 伏笔管理界面
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