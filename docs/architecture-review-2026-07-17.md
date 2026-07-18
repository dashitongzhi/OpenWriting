# OpenWriting 架构深度审查报告

> 范围：`/Users/kral/project/OpenWriting`
> 审查时间：2026-07-17
> 性质：仅做评估，未修改任何代码
> 审查方式：主审查 + 4 个并行子代理实证复核（grep 行号、跨文件追踪 caller、统计顶层类型）

---

## 0. 总览

OpenWriting 是一个 macOS 原生长篇小说创作工具，使用 Xcode + SwiftUI + Swift Concurrency，账号同步走 Apple ID / iCloud，AI 走多 provider（OpenAI 兼容 / 自定义 / Anthropic），核心交互是「章节写作会话」 + 「长篇后台投影」。

### 仓库现状速览

| 维度 | 现状 |
| --- | --- |
| 主目录 | 70 个 tracked Swift 源文件，约 34.3k 行；最大文件 `WritingDeskView.swift` **3817 行** |
| 5 大巨型文件 | `WritingDeskView.swift` 3817 / `DomainModels.swift` 2568 / `AppState.swift` 2478 / `LongformStorySystem.swift` 2316 / `PlaceholderWorkspaceView.swift` 1385 |
| 测试 | 8 个测试文件 2930 行；XCTAssert 370 处；**但 `WritingDeskSessionPolicyTests.swift` 未注册到 `project.pbxproj`（幽灵测试）** |
| 双 target | `OpenWriting.xcodeproj` 主 target + `Tests/Package.swift` SwiftPM 占位 target（`XcodeOnlyPlaceholder` 是空壳） |
| 已删文件夹 | `OpenWriting/Managers/` 是空的（git status 显示 5 个 `D`），意味着之前有过「按职责拆分」的尝试但又清掉了 |
| Xcode 工程 | `PBXFileSystemSynchronizedRootGroup` 自动包含 `OpenWriting/` 下新增的 Swift 文件，这是当前拆分能"随便加文件不踩工程"的原因 |

### 总体评分（5 分制）

| 维度 | 评分 | 关键问题 |
| --- | --- | --- |
| 领域语言清晰度 | 4/5 | 「章节写作会话 / 候选稿 / 章节收录 / 长篇后台投影」自洽 |
| 领域模型清晰度 | 2/5 | `NovelProject` 单体 700+ 行，领域规则与运行期关注点交织 |
| 持久化分层 | 2/5 | 三层（StorageKey / ProjectFileStore / 分片 JSON）职责重叠 |
| 持久化安全性 | 3/5 | 写入是 `.atomic`，但缺乏 fsync / 断电保护；恢复路径完备 |
| iCloud 同步健壮性 | 2/5 | 基于 updatedAt 的 LWW 易丢稿，无冲突副本 |
| 多账号隔离 | 2/5 | Scope 命名空间仅覆盖 3 个键 + 5 处漏洞 |
| 代码可演进性 | 2/5 | AppState 2478 行，领域规则四处散落 |
| 测试覆盖 | 3/5 | 域值类型覆盖深，但 AppState / WritingDesk / Longform 零行为测试 |
| 工具链可维护性 | 2/5 | 17 个 scripts 中 PR review 工具链占 5-6 个 |

---

## 1. 顶层架构问题

### 1.1 「AppState 即一切」的单体协调器（核心阻塞点）

**`OpenWriting/AppState.swift:1-2479` 是一个 `@MainActor @Observable final class`，承担：**

- 全局配置状态（`selectedProvider`、`modelName`、`apiKey`、`baseURL`、`autoValidateOnLaunch`、`hasAcceptedAIDataTransfer`、`draftEditorFontSize/LineSpacing`、`showWritingDeskCachePanel/Timeline`、`isWritingFocusModeEnabled` 等）
- 全部写作偏好（写作技能 `writingSkills`）
- 账号信息（`activeAccount: AppleAccountProfile?`，绑定 iCloud scope）
- 项目仓储（`recentProjects: [NovelProject]`）
- 云同步任务编排（`cloudSaveTask`、`cloudSaveGeneration`、`isCloudSynchronizationInProgress`、`recentProjectsPersistTasks`）
- 当前用户界面选择（`selectedSidebarItem`、`selectedProjectID`、`projectSpaceScrollTarget`、`projectSpaceSelectionPulse`、`activeProjectID`）
- AI 模型连接校验（`validateConfiguration()`、`connectionStatus`、`validationMessage`、`resolvedAIConfiguration`）
- 商业化（`commerceEntitlement`、`refreshCommerceEntitlements`、`purchaseCommerceProduct`、`restoreCommercePurchases`）
- 所有"对一个 project 写一条字段"的方法（`updateDraftText / updateCurrentChapterTitle / updateOutlineText / updateForeshadowNotes / ...`），从 `AppState.swift:516` 到 `AppState.swift:1390` 一连串 `updateProject(...)` 包装
- **伏笔字符串解析为结构化条目**（`migrateForeshadowNotesToStructured`，`AppState.swift:631-708`）
- **关键词抽取角色名 / 关系 / 地点 / 伏笔 / 时间线 / 剧情事实**（`extractStructuredMemory`、`extractNamesFromContext`，`AppState.swift:1676-2050`）
- **AI 后台记忆抽取**（`runAIMemoryExtraction`，`AppState.swift:1477-1624`）
- 章节版本/草稿/章节树更新/全局记忆更新/章节保存/版本回滚
- 全文检索（`searchLongformProject`，`AppState.swift:1973-2056`）

加上 `AppState+Persistence.swift`、`AppState+Account.swift`、`AppState+iCloudSync.swift`、`AppState+WritingSkills.swift` 四个 extension，**这个类总暴露面在 300+ 个方法和属性**。

#### AppState 内的领域规则（共 11 处 ~926 行）

| 位置 | 行号 | 体积 | 性质 |
| --- | --- | --- | --- |
| `migrateForeshadowNotesToStructured` | `AppState.swift:631-708` | ~78 行 | 解析 `[新增]/[推进]/[已回收]` 文本转 `ForeshadowEntry` |
| `applyChapterTreeRefresh` | `AppState.swift:833-901` | ~69 行 | 5 段 outline merge 决策 |
| `appendOutlineSummaryToContinuity` | `AppState.swift:1387-1409` | ~23 行 | outlineSummary → globalMemorySnapshot 注入 |
| **`extractStructuredMemory`** | **`AppState.swift:1676-2050`** | **~375 行** | **关键词抽取人物/关系/地点/伏笔/时间线/事实** |
| `runAIMemoryExtraction` | `AppState.swift:1477-1624` | ~148 行 | AI prompt 拼装 + 结果应用（与 `MemoryExtractionService` 重复） |
| `defaultNextChapterFocus` | `AppState.swift:2359-2444` | ~86 行 | 根据 storyLength + longformRuntimeState 拼下一章焦点 |
| `saveCurrentChapterDraft` 内嵌 chapter 匹配 | `AppState.swift:1132-1198` | ~67 行 | 找 existing chapter、version snapshot、trim 12 个历史 |
| `restoreChapterVersion` | `AppState.swift:1304-1352` | ~49 行 | 回滚前 snapshot、版本历史 trim |
| `trimChapterVersionHistory` | `AppState.swift:2209-2212` + 常量在 `line 9` | ~4 行 | 12 条历史上限 |
| `markLongformChapterNeedsRecommit` | `AppState.swift:2214-2237` | ~24 行 | 根据 chapter draft 重建 longform runtime |
| `Template Defaults`（`defaultProjectSummary` 等） | `AppState+Persistence.swift:447-677` | **~230 行** | 按 `NovelLength` 生成模板，寄生在 Persistence 文件里 |

#### 问题

1. **`AppState` 不再是「协调器」，它是半个产品**。git status 显示 6 个 manager 文件已 `D`（`ProjectManager.swift / ChapterManager.swift / DashboardManager.swift / SearchManager.swift / WritersAICommandsManager.swift / AppStateManagers.swift`）—— 之前显然有过"按职责拆 manager"的努力，但回滚/放弃了。
2. **`AppState.swift:2063` 之后还有约 400 行**包含 `normalizeProjectSelection / refreshIdleValidationMessage / markConfigurationAsEdited / updateProject / makeProjectIdentifier / 静态默认项目生成` —— 全部应该是 `extension` 或独立类型。
3. **`recentProjects` 的 `didSet` 触发 `scheduleCloudSnapshotSave()` + `noteLocalProjectMutation()`**（`AppState.swift:121-128`）。任何写入字段的 `updateProject` 都会改 `recentProjects` → 上报云端。`isHydratingAccountScopedData` 旗标必须小心控制（`AppState.swift:1040`、`AppState.swift:1253`）。

#### 建议方向

```
AppState (root, Observable)
 ├─ WorkspaceCoordinator   // 导航、selectedSidebarItem、activeProjectID
 ├─ ConnectionCoordinator  // AI provider、keychain、validateConfiguration
 ├─ AccountCoordinator     // Apple ID、storage scope
 ├─ SyncCoordinator        // iCloud + scheduleCloudSnapshotSave + cloudSaveGeneration
 ├─ CommerceCoordinator    // entitlements
 ├─ ProjectRepository      // recentProjects、CRUD、章节保存、版本回滚
 └─ ProjectWorkspaceService // 项目聚合读写（与 LongformStorySystem 对接）
```

| 阶段 | 改动 | 风险 |
| --- | --- | --- |
| P0 | 抽出 `AccountCoordinator`（Account + iCloud + commerce） | 低 |
| P0 | 抽出 `ConnectionCoordinator`（AI 配置 + 校验） | 低 |
| P1 | 抽出 `ProjectRepository`（recentProjects、CRUD） | 中 |
| P1 | 抽出 `WorkspaceCoordinator`（导航 + 选中态） | 低 |
| P2 | 把"领域规则"（foreshadow 解析、memory 抽取）从 AppState 搬到对应领域模块 | 中 |

---

### 1.2 写作台 = 单文件 3817 行 = 整个产品的心脏没分层

**`OpenWriting/WritingDeskView.swift` 是 View，但承担了 controller / view-model / coordinator 全部职责：**

- 内部 `@State` 至少有 47 个（`WritingDeskView.swift:13-65`），覆盖：sheet 弹出态、AI 生成/保存任务 token、缓存折叠、滚动锁、查找替换状态、AI 候选稿字符串、`pendingDraftPolishReview`、`latestChapterReview`、`latestAISuggestionAcceptanceContext`、`writingRunState`、`thinkingMode`、`draftSelection`、`timingSnapshot`、`projectContextRefreshTokens`、`isConfigurationCardsCollapsed`、`qualityReviewDashboardPresentation`、`operationAlert` 等
- `private func` 至少 108 个（`WritingDeskView.swift:62-3388`）
- 51 个 `@State` 按职责可分 7 组
- 直接调用了 `appState.saveCurrentChapterDraft(...)`、`appState.runAIMemoryExtraction(...)`、`appState.refreshICloudProjects()`、`appState.applyEnhancedWritingUpdate(...)`、`appState.applyChapterTreeRefresh(...)` 等十多个 AppState 方法
- 直接调用 `aiService.generateText(...)`、`MemoryExtractionService.extractionUserPrompt(...)` 等应该属于 Service 层的调用
- 直接调用 `LongformStorySystem.buildWriteGateReport`、`ChapterQualityReviewer.quickAIFlavorCheck`、`StrandWeaveTracker.evaluate(...)` 等领域规则

#### 3 个伴生文件状态

| 文件 | 行数 | 实际职责 |
| --- | --- | --- |
| `WritingDeskPanels.swift` | 1026 | 14 个独立 View（chapterNavigator、polish 系列、quality、brief rows、status pill、diff sheet 等），本身较干净，但依赖倒置：被 `WritingDeskView` 通过闭包回写 |
| `WritingDeskSessionModels.swift` | 545 | **真正核心的"会话模型"**：可单测、可演进的纯逻辑，但只是被 View 用来构造 token，没发挥价值 |
| `WritingDeskSupportViews.swift` | 634 | `WritingDeskDraftEditor: NSViewRepresentable`（含 NSTextView 桥接，220 行）、`WritingDeskTimelineNode`、`AIWriterThinkingSurface`、`WritingDeskCacheSurface`、`WritingDeskCollapsedLayout` —— 部分共享但部分（如 timeline 与 thinking surface）是写作台独有的渲染，命名误导 |
| `WritingDeskOutlineGeneratorSheet.swift` | 316 | 大纲生成的独立 Sheet，依赖关系相对干净 |

#### SupportViews 名实不符

| 类型 | 定义处 | 跨文件使用 | 真共享？ |
| --- | --- | --- | --- |
| `WritingDeskTextSurface` | `SupportViews.swift:65` | View ×4 + Outlines:308 | 是 |
| `WritingDeskCollapsedLayout` | `SupportViews.swift:4` | View ×2 | 否，仅 View 内部 |
| `WritingDeskInlineField` | `SupportViews.swift:44` | View ×2 | 否，仅 View |
| `WritingDeskDraftSelection` | `SupportViews.swift:106` | View ×8 + SessionModels ×2 | 跨文件共享，但应挪到 SessionModels |
| `WritingDeskDraftEditor` | `SupportViews.swift:117` | View ×1 | 否，仅 View |
| `WritingDeskCacheSurface` | `SupportViews.swift:343` | View ×1 | 否，仅 View |
| `WritingDeskTimelineRow` / `WritingDeskTimelineNode` / `AIWriterTimelineStage` | `SupportViews.swift:389/402/422` | View ×1 each | 否，仅 View |
| `AIWriterThinkingSurface` / `AIWriterThinkingState` | `SupportViews.swift:558/566` | View ×1 | 否，仅 View |

#### 死代码与反模式

1. **`shouldConfirmChapterLoad`（`WritingDeskView.swift:3453-3473`）末尾分支是死代码**：最后两行 `return true` 等价。
2. **`pendingDraftPolishReview` 的 popover `binding` setter 是空实现**（`WritingDeskView.swift:3593-3595`），popover 看似可关闭，实际关不掉。
3. **`acceptAISuggestionIntoDraft`（`WritingDeskView.swift:2332`）直接调用 `appState.appendDraftText`**，没有第二道门禁。**这是写作台最危险的隐藏路径**。

#### 重复实现

- **润色 4 个 mutator 函数同结构**：`keepDraftPolishReview / replaceDraftPolishReview / discardDraftPolishReview / copyDraftPolishReview`（`WritingDeskView.swift:3535/3552/3567/3581`）
- **`applyPolishedSelection`（`WritingDeskView.swift:3600`）与 `draftReplacingSelection`（`WritingDeskView.swift:3625`）几乎重复**
- **`excerpt(from:limit:)` 三处重复**：`SessionModels.swift:540` / `WritingDeskView.swift:2867` / `AIWritingService+Prompts.swift:906`
- **过期校验 7 处重复实现** `currentContext == savedContext`：`WritingDeskView.swift:1961/2082/2372/2616/2755/2783/3118`
- **`AI 候选稿生命周期` 在 5 个文件、4 套职责切片里重复实现**

#### 拆分优先级（按依赖关系自下而上）

| 优先级 | 名称 | 体积 | 依赖 | 风险 |
| --- | --- | --- | --- | --- |
| 1 | `WritingDeskController`（领域 controller） | 27 @State + 6 Task + 800-900 行 | AppState + SessionPolicy | 中 |
| 2 | `WritingDeskReviewFlow`（审稿-接受-改写） | 6 个面板 + 4 个 mutator | #1 | 中 |
| 3 | `WritingDeskFindReplace`（查找替换） | 4 @State + 4 函数 + 3 view 函数 | AppState + Selection | 低 |
| 4 | `WritingDeskChapterLifecycle`（章节保存+后台投影） | ~700 行 | #1 + Longform | 中 |
| 5 | `WritingDeskEditorBridge`（编辑器胶水） | ~8 个 view 函数 | AppKit + View | 低-中 |

执行顺序：**1 → 3 → 5 → 2 → 4**

---

### 1.3 领域模型"全在 DomainModels.swift"，但有"持久化 vs 运行期"混居

**`OpenWriting/DomainModels.swift` 2568 行 / 29 个顶层类型**：

| 区段 | 行号 | 内容 | 性质 |
| --- | --- | --- | --- |
| `PersistedTimestampDisplayStyle` / `PersistedTimestampCodec` | 3 / 8 | 时间戳 | 横切关注点 |
| `NovelLength` / `ModelProvider` / `ConnectionStatus` | 236 / 341 / 413 | 配置相关枚举 | 持久化 + UI 共用 |
| `DashboardStat` / `StoryPillar` / `InspirationSignal` | 446 / 2534 / 2541 | UI 数据 | 纯 UI |
| `ChapterDraftSaveResult` / `ChapterDraftVersion` / `ChapterDraft` / `ChapterDraftMetadata` | 456 / 477 / 546 / 659 | 章节 | 持久化 |
| `OutlineGenerationProfile` | 695 | 大纲生成 profile | 持久化 |
| `LongformSearchResult` / `LongformSearchResultKind` | 793 / 818 | 搜索结果 | 纯 UI |
| `GlobalMemorySnapshot` | 829 | 全局记忆结构 | 持久化 |
| `ForeshadowEntry` / `ForeshadowStatus` / `ForeshadowImportance` / `ForeshadowList` | 1017-1287 | 伏笔 | 持久化 |
| `PlotThread` / `ThreadType` / `ThreadStatus` / `ThreadEvent` / `ThreadEventType` / `PlotThreadList` | 1287-1608 | 线索 | 持久化 |
| **`NovelProject`** | **1608-2363（755 行）** | **项目根类型** | **持久化 + UI + 领域规则** |
| `ReferenceDocument` / `ReferenceMaterialCategory` | 2363 / 2435 | 参考文档 | 持久化 |
| `ChapterTreeSectionMergeDecision` | 2548 | 章节树合并决策 | 纯领域规则 |

**`NovelProject`（755 行）是「项目根」但塞了过多职责：**

- 字段覆盖：基础信息、当前章节、字数统计、各类 outline notes（8 种 `*Notes`）、reference、qualityReviewReports（最近 80 条）、accumulatedAntiPatterns（最近 50 条）、chapterDrafts、chapterCatalog、longformRuntimeState、globalMemorySnapshot、strandWeaveState、genreTemplateId、outlineGenerationProfile、webnovelIntegration
- 它同时被 `Codable`（持久化）、`Sendable`（被 actor 跨线程共享）、`Identifiable`（UI）、还是 `@unchecked Sendable`（`DomainModels.swift:1608`），并通过 `NovelProject.clearIntegrationCache` 静态方法提供内存缓存层

**应独立模块的类型（按风险从高到低）：**
- `ForeshadowEntry` 家族（line 1017-1282）~265 行
- `PlotThread` 家族（line 1287-1607）~320 行
- `GlobalMemorySnapshot`（line 829-1012）~180 行
- `PersistedTimestampCodec`（line 8-234）~227 行
- `OutlineGenerationProfile`（line 695-791）~100 行

#### 建议方向

```
NovelProject               // Codable 持久化壳
NovelProjectRuntimeView    // 计算字段 + UI 状态 + 缓存
```

---

### 1.4 长篇后台投影集中在 `LongformStorySystem.swift` 2316 行

**`OpenWriting/LongformStorySystem.swift:397-2191` 是单个 `enum LongformStorySystem`（静态方法）**

#### 状态机实际是 5 步而不是 3 步

1. `buildRuntimeContract(for:)`（`LongformStorySystem.swift:451-543`）—— 计算合同
2. `buildCommit(project, chapterDraft, review, reviewFailureReason, extractedMemoryItems, contract)`（`LongformStorySystem.swift:545-635`）—— 决定 accepted/rejected
3. `apply(commit, contract, to: &project)`（`LongformStorySystem.swift:1406-1476`）—— 写回 project
4. `buildWriteGateReport(commit, contract)`（`LongformStorySystem.swift:660-803`）—— 把 commit 状态映射成 4 阶段展示
5. `buildRuntimeHealth(for:)`（`LongformStorySystem.swift:897-1242`）—— 健康诊断

**关键问题**：`buildRuntimeContract` 一次调用会触发 `PrewriteValidator.validate`（`LongformStorySystem.swift:452`），每次 `buildRuntimeHealth` 又会再跑一次（`LongformStorySystem.swift:899`）。**一次写作流程里 PrewriteValidator 可能被调用 2~3 次**——这是隐藏的 N×CPU 开销。

调用方有 5 处：`AppState.swift:1457-1466, 1606, 1645, 2227-2236` + `WritingDeskView.swift:2376, 2590, 2894, 3644`。

#### PrewriteValidator 与 LongformStorySystem.buildWriteGateReport 的关系

| 阶段 | 阻断条件 | 位置 |
| --- | --- | --- |
| prewrite | `contract.prewrite.isBlocked` | `LongformStorySystem.swift:668-681`（直接消费 `PrewriteValidator.validate` 结果）|
| review | `rejectionReasons` 含"审查"或 `reviewSummary == "暂无写后审查结果。"` | `LongformStorySystem.swift:683-706` |
| fulfillment | `requiresMandatoryNodeCoverage` 且 `missedNodes` 非空 | `LongformStorySystem.swift:708-723` |
| projection | 后台投影状态含 blocked/warning | `LongformStorySystem.swift:725-754` |

**结论**：
1. prewrite 阶段不重复——它就是直接消费 `PrewriteValidator.validate(...)` 结果
2. 但 `PrewriteValidator.checkLongformReadiness`（`PrewriteValidator.swift:220-291`）的 3 条阻断规则，与 `LongformStorySystem.buildRuntimeHealth`（`LongformStorySystem.swift:1127-1134, 1136-1145, 1014-1116`）中的多个 warning/blocked 条目有重叠

#### 配套文件

| 文件 | 行数 | 职责 |
| --- | --- | --- |
| `WritingMemoryBuckets.swift` | 681 | 7 类 `MemoryItem`、`MemoryBuckets` 容器、合并/裁剪 |
| `StrandWeaveTracker.swift` | 619 | 三股线（Quest/Fire/Constellation）跟踪 |
| `ChapterTreeRefresh.swift` | ~150 | 章节树刷新结构 |
| `PrewriteValidator.swift` | 519 | 写前校验 |
| `ContextRanker.swift` | 248 | 上下文片段排序 |
| `MemoryExtractionService.swift` | 288 | AI 抽取记忆 |
| `ChapterQualityReviewer.swift` | 964 | 统一质量审查 |
| `QualityReviewService.swift` | 299 | 看起来是 `ChapterQualityReviewer` 的兼容 shim |

#### `StrandWeaveTracker` 双实现问题

- **`StrandWeaveTracker`（class）**：`StrandWeaveTracker.swift:113-394`，**整体是死代码**——全工程只有 2 处构造它（`DomainModels.swift:1646, 1790, 1842`），`classifyChapter`、`checkRedLines`、`suggestNextStrand` 没有任何 caller
- **`StrandWeaveState`（struct）**：`StrandWeaveTracker.swift:414-619`，**实际在跑**

驱动时机：
1. **每次 enhanced 续写结束**（`AIWritingService+Enhanced.swift:185-192`）：本地关键词分类（不发 AI）
2. **每次保存章节**（`LongformStorySystem.apply` 路径，`LongformStorySystem.swift:1463-1468`）

→ **删除 `StrandWeaveTracker` class 整体可以减 281 行死代码**。

#### `WritingMemoryBuckets` 护栏实证

| 维度 | 护栏 | 触发条件 | 风险 |
| --- | --- | --- | --- |
| 条目数 | `compact(threshold: 500)` | **仅显式调用** | 任何路径省略 `compact` 就会无限增长 |
| 单条 `value` 字符数 | **无** | — | 单条 value 可以无限长 |
| `writingBrief` 总字符数 | **无** | — | 12 段拼接不限制总字符数 |
| `enhancedMemoryContext` | `enhancedMemoryContextCharacterLimit = 4000` | — | 聚合后限制，**不约束单条 value** |
| `relevantActiveItems(for:limit:30)` | `limit: 30` 默认 | 调用方常传 `limit: 24/12` | 实际更少，安全 |
| `workingContextItems(for:relevantLimit:16, totalLimit:26)` | `totalLimit: 26` | 默认 | 安全 |

→ **实际是 7 类不是 6 类**（`WritingMemoryBuckets.swift:103-146` `MemoryCategory` 有 `readerPromise`）

#### 建议方向

```
LongformStoryContract.swift  // 合同构造、纯计算
LongformChapterCommit.swift  // commit 构造 + 状态机
LongformGateReport.swift     // 写前闸门
LongformProjector.swift      // apply(commit:to:) + 长篇投影
LongformHealth.swift         // 健康诊断
PrewriteChecklist.swift      // 写前 checklist
QualityReviewModels.swift    // ChapterReviewResult、Issue、Report
```

---

### 1.5 AI 服务层：拆分得"看起来对，但 Enhanced 太胖"

#### `AIWritingService.swift`（1025 行）

- L4-9：`ModelAPIFormat`、`AIConnectionConfiguration`
- L31：`AIWritingMode`、`AIWritingLength`
- L117：`enum AIWritingService`（static 工具方法 + 默认实现）
- L943-1018：`AIWritingError`、`ChatCompletionsRequest`、`ChatCompletionsResponse`、`AnthropicMessagesRequest`、`AnthropicMessagesResponse`

#### `AIWritingService+Enhanced.swift`（776 行）

- `extension AIWritingService`（L8-704）：所有增强型方法
- L705-704 末尾：`EnhancedWritingSupport`、`EnhancedWritingResult`、`MemoryUpdateContext`

#### `AIWritingService+Prompts.swift`（994 行）

prompt 模板与上下文装配。9 段 systemPrompt 字符串 + 11 个 `static func` 用户 prompt 构造器。

#### `AIWritingServicing.swift`（139 行）

协议 + `DefaultAIWritingService` static adapter。

#### 协议是否真的允许 mock？

**协议目前只允许"包装"DefaultAIWritingService，不允许真正的替换。**

- `bm25Scorer`、`completeOpenAIText` 等全部是 `private static`，mock 无法复用这些实现
- `EnhancedWritingSupport.init` 在 `AIWritingService+Enhanced.swift:715-725` 直接调 `AIWritingService.WritingSupportContext(project:)`，这意味着 mock 还得覆盖 Service 内部类型

→ **典型的"协议接口窄、实现细节深"反模式**。

#### `+Enhanced` 4 个 inline prompt 没有走 +Prompts 模板化

| inline prompt | 行号 | 体积 |
| --- | --- | --- |
| `enhancedWritingRevisionUserPrompt` | `AIWritingService+Enhanced.swift:207-268` | 62 行 |
| `enhancedWritingReviewRepairUserPrompt` | `AIWritingService+Enhanced.swift:270-329` | 60 行 |
| `enhancedWritingSupplementUserPrompt` | `AIWritingService+Enhanced.swift:331-374` | 44 行 |
| `enhancedWritingPlanPrompt` | `AIWritingService+Enhanced.swift:581-633` | 53 行 |

这 4 个与 +Prompts 中已有同名函数几乎逐字一致，只是额外插入了 4 个 enhanced 段落。**最优先的抽取目标**。

#### `AIWritingError` 缺 4 类典型失败

| 失败场景 | 当前覆盖 |
| --- | --- |
| 网络/超时 | ✅（重试存在但超时本身被吞）|
| 解析失败 | ✅ `.invalidResponse` / `.emptyResult` |
| 限流 | ✅ `.rateLimited` |
| 取消 | ✅ `CancellationError` 透传 |
| **内容安全（content_filter / refusal）** | ❌ 进 `.serverError` |
| **账号欠费 / 余额** | ❌ 进 `.serverError` |
| **模型下架（404 model_not_found）** | ❌ 进 `.serverError` |
| **输入超长（context_length_exceeded）** | ❌ 进 `.serverError` |

#### 续写 7 次 HTTP 调用

| 阶段 | HTTP 调用次数 |
| --- | --- |
| 续写主流程 | 1 planning + 1 draft + 1 revision = 3 次 |
| 可选 review | 1 次 |
| 可选 review-repair | 1 次 |
| 可选 supplement | 1 次 |
| 可选 review again | 1 次 |
| **最大单次续写** | **7 次 HTTP** |

#### `runAIMemoryExtraction` 缺并发控制

子代理实证 `AppState.swift:1477-1624`：
- ✅ 有重试：3 次重试 + 指数退避
- ✅ 有超时：120 秒硬超时
- ❌ **无节流 / debounce / 信号量**：用户连续保存多个章节会并发跑 N 个 AI 抽取请求
- ✅ 有隐式 fallback：依赖 `extractAndStoreMemoryItems` 在保存时已跑过关键词抽取

#### 死代码

- `AIWritingService.continueChapter` 旧版（`AIWritingService.swift:135-210`）—— 协议没声明，全工程 0 个 caller
- `AIWritingService.reviewChapter`（`AIWritingService.swift:923-937`）—— caller 路径已死
- `QualityReviewService.swift`（299 行）整体是 compat shim

#### 建议方向

```
AIWritingServicing.swift  // 协议 + 错误模型扩充
AIWritingProvider.swift   // 每个 provider 的实现（OpenAI 兼容 / Anthropic / OpenWriting）
AIWritingClient.swift     // URLSession + 流式 + 重试 + 限流
AIPromptLibrary.swift     // 全部 prompt 模板
AIPromptContext.swift     // 上下文组装
AIMemoryExtraction.swift  // 迁出 AppState.runAIMemoryExtraction
```

---

### 1.6 测试与脚本：覆盖空白 + 双 target 互相干扰

#### 测试现状（Tests/OpenWritingTests/）

| 文件 | 行数 | 覆盖范围 |
| --- | --- | --- |
| `DomainModelsTests.swift` | 1496 | 领域类型编解码 + 解析 |
| `ProjectFileStoreTests.swift` | 551 | 文件存储原子写、健康检查 |
| `ProjectExportServiceTests.swift` | 147 | 导出 |
| `NovelProjectTests.swift` | 353 | 项目模型 |
| `WritingDeskSessionPolicyTests.swift` | 79 | **5 个 case，但没注册到 `project.pbxproj`（幽灵测试）** |
| `SearchTests.swift` | 150 | 检索 |
| `HostedXCTestLaunchGuardTests.swift` | 52 | 启动守卫（烟雾测试） |
| `TestFactories.swift` | 102 | 测试工厂 |

XCTAssert 共 370 处，138 个 test 方法。

#### 关键发现：`WritingDeskSessionPolicyTests.swift` 是"幽灵测试"

子代理用 grep `project.pbxproj` 各编号实测：
- 文件存在，但 `project.pbxproj` 里没有 `PBXFileReference` 和 `PBXBuildFile`（对照 `:32-38` 其它 7 个测试文件都有 `B001…03` … `B001…18` 编号）
- `scripts/run-all-checks.sh:19-23` 的 `rg XCTEST_CLASS_PATTERN` 自动发现机制能找到它（因为文件存在 + 含 `XCTestCase`），但 Xcode 实际编译时**不会**把它打进 `OpenWritingTests.xctest`（`project.pbxproj:208-219` 的 sources 列表里没有它）
- **结果**：5 个 session policy case 在 `xcodebuild test` 下永远跑不到

#### 完全没覆盖（按重要性排序）

1. **SwiftUI 视图层零测试**—— `WritingDeskView` 3817 行、`WritingDeskPanels` 1026 行、`HomeDashboardView` 1077 行、`AppRootView` 796 行、`AppearanceSettingsView` 421 行等
2. **`AppState` 协作流**：仅 `DomainModelsTests.swift:441-492` 测了 logout 边界
3. **`PrewriteValidator` 零测试**
4. **`MemoryExtractionService.extractMemoryItems` 端到端无测试**
5. **iCloud `mergeCloudProjects` 测试与生产 fixture 耦合**

#### Hidden time-bomb

1. **`DomainModelsTests.makeIsolatedProjectStore` 没有 `tearDown`**（`DomainModelsTests.swift:658-663`）：写到 `/tmp/OpenWritingTests-<UUID>`，**会一直累积**
2. **`testClearIntegrationCacheRemovesLegacyDefaults`**（`DomainModelsTests.swift:1359-1373`）写 `UserDefaults.standard`
3. **`seedRawOpenWritingAPIKey / deleteRawOpenWritingAPIKey`**（`DomainModelsTests.swift:692-726`）写**真实 Keychain**

#### 烟雾测试 / 价值低的区域

- `HostedXCTestLaunchGuardTests.swift:1-52`（1 个 case）
- `SearchTests.swift:1-150`（16 case）纯文本算法
- `ConnectionStatus` 字符串字面量测试（`DomainModelsTests.swift:1-94`）
- `MockAIWritingService`（`DomainModelsTests.swift:1414-1496`）所有方法抛 `MockError.unused`，**不是真测试**

#### CI 覆盖盲区

| 脚本 | CI 状态 |
| --- | --- |
| `run-smoke-checks.sh` → `run-longform-quality-checks.sh`（grep 守卫） | ✅ 在 `pr-merge-checks.yml:60` |
| `run-longform-evals.sh`（30 chapters mock eval） | ❌ 仅本地手工 |
| `run-memory-continuity-soak.sh`（200 万字符 / 30+ 分钟） | ❌ 仅通过 quality-checks.sh 嵌套调用 |
| `run-all-checks.sh`（含 hosted test） | ❌ 仅本地手工 |

#### `Tests/Package.swift` + `SwiftPMPlaceholder/`

是只为了让 `swift test` 不误把 app target 当成 library 的占位 manifest，`SwiftPMPlaceholder/Placeholder.swift:1-4` 只有一个空 `enum XcodeOnlyPlaceholder {}`。意图是"防误跑"，但 `Tests/SwiftPMPlaceholderTests/` 是空目录。

---

## 2. 持久化与同步的具体漏洞

### 2.1 iCloud 同步基于 `updatedAt` 的 LWW 易丢稿

**`mergeCloudProject`（`AppState+iCloudSync.swift:288`）：**

```swift
var merged = remote.updatedAtDate >= local.updatedAtDate ? remote : local
```

**真正的丢稿场景**：A 设备离线编辑 10 分钟（`t1`），B 设备离线编辑 10 分钟（`t2`），B 先上传到 iCloud（`t2 > t1`），A 上线时 `t1 < t2` 被覆盖 → **A 的整本草稿丢失**。

**`mergeCloudChapterDrafts`（`AppState+iCloudSync.swift:311-326`）**对**同一章节 ID** 用 `savedAtDate` LWW：两个设备对同一章节离线编辑时，**一方被静默丢弃，没有写入 conflicts/**。

### 2.2 CloudKit 索引与 payload 原子性不一致

`AccountSync.swift:440` 索引记录用 `atomically: true`，但 `AccountSync.swift:433` 的 payload 保存是 `atomically: false`。**索引与 payload 之间如果中途失败，索引会指向不存在的 payload**。

### 2.3 持久化安全性的具体风险

**良好**：
- `.atomic` 写入保证单文件不会半写（`ProjectFileStore.swift:614`）
- `ProjectFileWriteCache`（`line 1001-1031`）基于 size + SHA256 前 8 字节
- 完整 chapter → catalog 双索引一致性检查（`line 264-317`）
- `backupExistingChapterFileIfNeeded`（`line 865-891`）覆盖前会备份到 `recovery-backups/`

**风险点**：
1. **多文件非事务**：`saveProject`（`line 561-589`）依次写 project.json → chapters/index.json → 每个章节文件。**任何中间断电会留下不一致状态**
2. **删除策略过于激进**：`removeDeletedProjectDirectories`（`line 632-644`）会在每次保存后清理孤儿文件
3. **未使用 `FileProtectionType.complete`**：line 614 未指定
4. **未使用 `URLResourceKey.isExcludedFromBackupKey`**：备份目录 `recovery-backups/` 持续累积
5. **冲突标记文件夹不清理**：`conflicts/`（line 834-842）写入后永不清理

### 2.4 4 个 `sanitizedStorageComponent` 独立实现

- `ProjectFileStore.swift:955-968`（允许 `.` `_` `-`）
- `AppState+Account.swift:173-186`（同样规则）
- `AccountSync.swift:719-732`（同样规则，但函数叫 `sanitized(_:)`）
- `ProjectExportService.swift:227-240`（叫 `sanitizedFileComponent`，**只允许 `-` `_`，其他字符替换为 `-`**）

→ **4 个不同的 sanitize 函数，行为不完全一致**。**CloudKit record 名称碰撞风险**：例如 `a@b.com` 和 `a-b.com` 在前 3 个 sanitizer 下都变成 `a_b_com`，写到同一条 record。

### 2.5 跨账号数据隔离的 5 处漏洞

子代理 grep 实证：**`currentStorageScope` 只覆盖 3 个键**（`activeProjectID / recentProjects / projectSnapshotTimestamp`）+ ProjectFileStore 内部目录。

**未分 scope 的字段**：

1. **写作 Skills（`StorageKey.writingSkills`）**：A 账号编辑 5 条 → 切 B 账号看到同样 5 条
2. **AI 配置（`selectedProvider / modelName / apiKey / baseURL / customModelName / customBaseURL / anthropicModelName / anthropicBaseURL`）**：两个账号共享同一份 API Key（Keychain 里按 provider 不按账号 keychain-account）
3. **`hasAcceptedAIDataTransfer`**：全局同意 flag
4. **`longformRuntime_<projectID>`**：`clearIntegrationCache` 没清理
5. **WebnovelIntegration 的 4 个 key**（`memoryBuckets_<projectID>` / `strandWeave_<projectID>` / `lastReview_<projectID>` / `antiPatterns_<projectID>`）：**完全无视 storage scope**

→ A 账号创建的 project X 切换到 B 账号，如果 B 恰好创建了同 ID 的 project，会读到 A 的 memory buckets / strandWeave / lastReview / antiPatterns。**这是跨账号数据泄漏**。

### 2.6 ProjectExportService 的具体风险

1. **DOCX/EPUB 手写 zip 不支持压缩**：`ZipArchiveBuilder` 只支持 `CompressionMethod.stored`，百万字导出文件比 zip 压缩版本大 3-5 倍
2. **OOXML 转义不全**：`xmlEscaped` 替换 5 个字符，但 `&apos;` 不需要替换
3. **EPUB 缺少 OPS 校验**：不校验章节文件名，中文标题 sanitize 后可能空
4. **DOCX 标题样式未定义**：`paragraph(project.title, style: "Title")` 引用 `Title` 样式但 styles.xml 中没有该样式定义
5. **没有 manifest 版本字段**：下游升级时无法识别旧 manifest
6. **导出阻塞 UI**：所有导出在 `MainActor` 同步执行

---

## 3. 写作台子系统核心循环

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ 1. 用户配置                                                                       │
│   writingDeskOutlineCard / Reference / Requirements                          │
│   → outlineBinding / referenceContextBinding / specialRequirementsBinding    │
│   → appState.updateOutlineText / updateReferenceContextText / …             │
└─────────────────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ 2. 用户点"开启写作"                                                              │
│   writingDeskAIActions (View:1655) -> startWriting (View:2004)                │
│   preflight: writingPreflightBlockingMessage (View:2148)                     │
│   构造 DraftGenerationRequestContext (SessionModels:22)                      │
│   → appState.aiService.continueChapterEnhanced (View:2059)                   │
│   on return:                                                                  │
│     - isApplied?  clear reviewed text; set latestChapterReview               │
│     - stale?     context hash != -> 丢弃 (View:2082)                        │
└─────────────────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ 3. AI 面板渲染                                                                   │
│   writingDeskAIColumn (View:831)                                              │
│   → AIWriterThinkingSurface (SupportViews:566) or TextEditor (View:863)      │
└─────────────────────────────────────────────────────────────────────────────┘
                                │
        ┌───────────────────────┼───────────────────────┐
        ▼                       ▼                       ▼
┌─────────────┐         ┌─────────────────┐    ┌────────────────────┐
│ 接受进草稿箱  │         │ 重写 / 调正润色   │    │ 清空 / 关闭 AI     │
│ View:2332   │         │ View:2327/2397 │    │ View:928-936        │
│ gate:       │         │ polish path    │    └────────────────────┘
│ View:2358   │         │ 进入 §4 polish  │
│ 草稿箱更新    │         └─────────────────┘
│ View:2340   │
└─────────────┘
        │
        ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ 4. 用户继续在草稿箱编辑                                                              │
│   WritingDeskDraftEditor (SupportViews:117)                                  │
│   + 查找替换 View:766-829                                                     │
│   + 选区润色 polishDraftSelection (View:2478) -> pendingDraftPolishReview     │
│   + 整篇润色 polishEntireDraft (View:2397)                                   │
└─────────────────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ 5. 用户点"保存当前章"                                                            │
│   saveCurrentChapterDraft (View:2564)                                         │
│   - short/no-planning: -> completeChapterDraftSave (View:2907)                │
│   - longform:                                                                 │
│     1) PrewriteValidator.validate (View:2152)                                 │
│     2) Contract build -> missingMandatoryNodes (LongformStorySystem)         │
│     3) ChapterQualityReviewer.reviewChapter (View:2607)                      │
│     4) applyEnhancedWritingUpdate (AppState) + extractAndStoreMemoryItems    │
│        -> LongformStorySystem.apply (View:2939)                              │
└─────────────────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ 6. 后台投影（refreshProjectContextAfterChapterSave）                                   │
│   并发三任务：                                                                   │
│     - refreshGlobalMemory (View:3037)                                         │
│     - refreshChapterTree (View:3049)                                          │
│     - reviewChapter (View:3065) / preSaveReview 重用                          │
│   → applyChapterTreeRefresh (AppState) -> ChapterTreeRefreshApplyOutcome    │
│   → runAIMemoryExtraction (AppState.swift:1477) -> MemoryExtractionService  │
│   → appendLocalAntiPatterns (AppState)                                        │
│   → beginNextChapter 可选                                                     │
└─────────────────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ 7. 循环回到 §1                                                                  │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 4. AI 服务层输入/输出契约

| 方法 | 调用方 | 频率 | 副作用 |
| --- | --- | --- | --- |
| `continueChapterEnhanced` | `WritingDeskView.swift:2059` | 用户每次点续写 | 1 planning + 1 draft + 1 revision + 可选 review/repair/supplement（最多 7 次 HTTP）|
| `polishFullDraft` | `WritingDeskView.swift:2420` | 用户点"全文润色" | 1 次 HTTP |
| `polishSelection` | `WritingDeskView.swift:2503` | 用户点"局部润色" | 1 次 HTTP |
| `suggestChapterTitle` | `WritingDeskView.swift:2746` | 用户点"拟章名" | 1 次 HTTP |
| `refreshGlobalMemory` | `WritingDeskView.swift:3037` | 用户点"刷新全局记忆" | 1 次 HTTP |
| `refreshChapterTree` | `WritingDeskView.swift:3049` | 用户点"刷新章节树" | 1 次 HTTP |
| `generateStoryOutline` | `WritingDeskView.swift:1945` | 用户点"生成大纲" | 1 次 HTTP |
| `validateConnection` | `AppState.swift:346` | 配置测试连接 | 1 次 HTTP |
| `generateText` | `AppState.swift:1545`（memory extraction）、`UnifiedQualityReviewer.reviewChapter` | 保存章节后异步 | 1 次 HTTP，无并发控制 |
| `UnifiedQualityReviewer.reviewChapter` | `WritingDeskView.swift:2607, 3065` | 用户点"写后审查" | 1 次 HTTP + 本地启发式合并 |
| `LongformStorySystem.buildRuntimeContract` | 7 处 | 每次写门禁相关流程 | 无 |
| `LongformStorySystem.buildCommit` | `AppState.swift:1458, 2228` | 每次保存章节 | 无 |
| `LongformStorySystem.apply` | `AppState.swift:1466, 2236` | 每次保存 | 写 project + UserDefaults JSON |
| `StrandWeaveState.recordChapter` | `AIWritingService+Enhanced.swift:188`、`LongformStorySystem.swift:1463` | 每次续写 + 每次保存 | 写 project + UserDefaults |
| `MemoryBuckets.upsert` | `AppState.swift:1592, 1595`、`LongformStorySystem.swift:1450` | 每次 apply + AI 抽取成功 | 写 buckets |
| `MemoryBuckets.compact` | 3 处 | 显式触发 | 写 buckets |

---

## 5. 具体可立即动手的小重构（按风险从低到高）

### P0（1 周内，最高 ROI）

1. **`WritingDeskSessionPolicyTests.swift` 加进 `project.pbxproj`**（幽灵测试修复，5 处 diff）
2. **`DomainModelsTests.makeIsolatedProjectStore` 加 `tearDownBlock`**（/tmp 累积）
3. **`testClearIntegrationCacheRemovesLegacyDefaults` 改用 suite-name UserDefaults**（真实污染风险）
4. **WebnovelIntegration 的 4 个 userdefaults key 加 scope 后缀**（跨账号数据泄漏）
5. **`clearIntegrationCache` 补 `longformRuntime_` 缺失**（5 行 diff）
6. **修 `WritingDeskView.swift:3453-3473` 死代码**
7. **修 `WritingDeskView.swift:3593-3595` popover 不可关闭反模式**
8. **给 `WritingDeskView.swift:2332` 加二级 `canAcceptAISuggestion` 防御**
9. **`AIWritingError` 加 4 case + `UserFacingError` 同步**（contentFiltered / billingRequired / modelUnavailable / inputTooLong）
10. **`LongformEvals/runs/` 加入 `.gitignore`**
11. **`excerpt(from:limit:)` 合并到单一来源**（3 处重复）
12. **迁 `WritingDeskView.swift:2825-2866` 的 prompt 字符串到 `AIWritingService+Prompts.swift`**

### P1（1-2 周）

13. **抽出 `WritingDeskController`**（剥离 27 @State + 6 Task + 800-900 行）
14. **合并 4 个润色 mutator 为 `applyDraftPolishReview(action:)`**
15. **把过期校验 7 处 ad-hoc 实现合并为 `ChapterWritingSessionPolicy.isStillValid(saved:current:)`**
16. **抽 `AppState` 的 AccountCoordinator / ConnectionCoordinator**
17. **`defaultNextChapterFocus` 搬到 `NovelProject.nextChapterFocus(after:)`**
18. **`applyChapterTreeRefresh` 搬到 `NovelProject.applyChapterTreeRefresh(_:baseline:timestamp:)`**
19. **`migrateForeshadowNotesToStructured` 搬到 `ForeshadowList`**
20. **`extractStructuredMemory` 抽出 `KeywordMemoryExtractor` 服务**（375 行减负）
21. **`runAIMemoryExtraction` 迁出 `AppState` 到 `MemoryExtractionService`**
22. **4 个 `sanitizedStorageComponent` 统一**
23. **`mergeCloudProjects` 移到 `ICloudProjectStore`**
24. **`MemoryItem.value` 加 maxLength + `compact` 二级阈值**
25. **`runAIMemoryExtraction` 加并发信号量**
26. **+Enhanced 4 个 inline prompt 提到 +Prompts**
27. **中文章节编号解析统一到 `ChineseChapterMarker`**
28. **删死代码**：`AIWritingService.continueChapter` 旧版 + 4 个相关 +Prompts 模板 + `StrandWeaveTracker` class + `AIWritingService.reviewChapter` + `WritingDeskView` 死分支（总计 ~500 行）
29. **`run-memory-continuity-soak.sh` 加 `--quick` 选项**

### P2（1-2 月）

30. **拆 `LongformStorySystem` 为 Contract / Commit / GateReport / Projector / Health**
31. **`PrewriteValidator` 与 `LongformStorySystem.buildRuntimeHealth` 阻断规则合并**
32. **`NovelProject` 按职责分组（持久化壳 + 运行时视图）**
33. **PR review 工具链独立到 `.tools/`**
34. **iCloud `mergeCloudProject` LWW 改 LWW + 冲突副本**
35. **CloudKit 索引与 payload 原子性统一**
36. **多文件持久化事务化 / WAL**
37. **测试补强**：`AppState` 并发 / Longform 端到端 / iCloud merge / AccountSync 跨账号 / FileStore 崩溃恢复
38. **引入 `ProjectStoring` protocol + `InMemoryProjectStore`**
39. **SwiftLint 落地（file_length + type_length 规则）**
40. **CI 增加 `run-longform-evals.sh --mode mock` 必跑**
41. **持久化加 `FileProtectionType.complete` + `URLResourceKey.isExcludedFromBackupKey`**
42. **`recovery-backups/` 与 `conflicts/` 清理策略**
43. **项目 file 头加迁移引导**：跨 scope 字段迁移到 scoped key

### P3（3-6 月，长期演进）

44. **目录结构按 `INDEX.md` 6 大类拆分**（`App/`、`State/`、`Domain/`、`AI/`、`Desk/`、`Resources/`）
45. **`WritingDeskFindReplace` 子模块抽离**
46. **`WritingDeskReviewFlow` 子模块抽离**
47. **`WritingDeskChapterLifecycle` 子模块抽离**
48. **`WritingDeskEditorBridge` 子模块抽离**
49. **`AIWritingService` 抽 `HTTPAIClient` 协议 + OpenAI/Anthropic 各一份**
50. **`LongformStoryContractBundle` 子结构独立文件**
51. **ProjectExportService async 化 + DOCX/EPUB 压缩支持**
52. **ViewInspector / SwiftUI snapshot 测试**

---

## 6. 「长期可迭代」治理建议（架构之外）

1. **SwiftLint 引入**：仓库当前没有 `.swiftlint.yml`。`WritingDeskView.swift` 3817 行、`AppState.swift` 2478 行——一个 type_length / file_length 规则就能强制拆分
2. **强制"加字段时改 N 处"的清单化**：`AGENTS.md:36-41` 已经对题材模板有"加字段必改 5 文件"的要求。类似清单应该扩展到 `NovelProject`、`ChapterDraft`、`WritingSkill`、`AccountProjectSnapshot`、`LongformChapterCommit` 等核心类型
3. **领域类型命名空间**：`INDEX.md` 已经分了 6 类——把 `OpenWriting/` 子目录按这个分类拆开，Xcode `PBXFileSystemSynchronizedRootGroup` 仍然能自动包含
4. **CI 必跑长篇脚本**：把 `run-longform-evals.sh --mode mock` 加入 CI nightly
5. **gitignore 调整**：
   ```
   *.bundle
   .codex/
   .git.corrupt-*/
   scripts/README*.md
   LongformEvals/runs/
   ```
6. **Contributors 协作面**：`AGENTS.md` 明确"直接在 main 改，不要 PR"。一旦加入第二个长期协作者就要重新评估——`main` 直推 + 缺少 review 流程 + 缺少 CI 强制，意味着任何人 commit 都能直接 break 用户
7. **测试运行入口**：8 个测试文件，Xcode test target 是主要入口，**`scripts/` 里没有任何 run-tests.sh 入口**。建议加 `scripts/run-tests.sh` 复用 `build-debug.sh` 的 Xcode 路径

---

## 7. 总结

**整体评价：** 这是一个**领域语言清晰、产品想法扎实**的代码库，"章节写作会话 → 候选稿 → 章节收录 → 长篇后台投影"这条主线从 `CONTEXT.md` 到 `LongformStorySystem` 都自洽。但在「工程层面」**还没有经过为「长期迭代」设计的临界质量**——具体表现是：

1. **「AppState 即一切」**是最大的债务：2478 行协调器 + 4 个 extension 加上 ≈600 行扩展，已经达到"无法整体重构、只能增量修补"的程度
2. **写作台单文件 3817 行**是第二大的债务：View/Controller/StateMachine 没分层，Session/Prompt 逻辑埋在私有方法中
3. **PR review 工具链比产品复杂**是第三大债务：17 个脚本里有 5-6 个是 review 流水线，需要拆分或独立
4. **测试空白**集中在最危险的区域：并发写章节、AI session 过期、跨账号切换、幽灵测试
5. **跨账号数据隔离有 5 处漏洞**：最严重的是 WebnovelIntegration 的 4 个 userdefaults key 泄漏账号数据
6. **iCloud 同步的 LWW 无冲突副本**：silent loss-of-work 风险

### 如果只能做一件事

**抽 `KeywordMemoryExtractor` 服务**（`AppState.swift:1676-2050` 的 375 行 `extractStructuredMemory` + `extractNamesFromContext`）——一次性消除 375 行 AppState 越界代码 + 关闭中文停用词表漂移风险 + 把最复杂的领域规则变成可单测的纯函数。

### 如果只能做两件事

加上 **`WritingDeskSessionPolicyTests` 加进 `project.pbxproj`**——5 分钟修，但立刻解锁 5 个 session policy 真实测试用例，是写作台过期校验的兜底护栏。

### 第一个月（P0 + 部分 P1）

抽出 AccountCoordinator / ConnectionCoordinator，把 `runAIMemoryExtraction` 迁出 AppState，修 5 处跨账号漏洞，修 4 处 AIWritingError，修 3 处幽灵测试 / 污染路径，修 3 处死代码 / 反模式。

### 第二个月（P1 主线）

抽出 WritingDeskController，把 WritingDeskView 控制在 ≤1500 行，4 个润色 mutator 合并，7 处过期校验合并。

### 第三到第六个月（P2 + 部分 P3）

拆 LongformStorySystem，拆 NovelProject，补 5 个关键测试，SwiftLint 落地，PR review 工具链外迁，目录结构按 INDEX.md 6 大类拆分。

### 第六个月以后

引入 ProjectStoring protocol，ProjectExportService async 化，多文件持久化事务化，AI 服务抽 HTTPAIClient 协议，ViewInspector / SwiftUI snapshot 测试。