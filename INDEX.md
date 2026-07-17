# Code Index

本索引收录当前 `OpenWriting/` 下全部人工维护的 Swift 源码文件，用于快速定位职责边界。新增 Swift 文件后应同步更新本文件。

不收录：
- `Assets.xcassets`
- `Resources/`
- `.xcodeproj/xcuserdata/`
- `.build/`、`DerivedData/`、签名输出和其他编译产物

## 应用入口与窗口

| File | Role |
| --- | --- |
| `OpenWriting/OpenWritingApp.swift` | 应用入口、macOS 生命周期和设置命令。 |
| `OpenWriting/AppWindowCoordinator.swift` | 主窗口、设置窗口、toolbar 和 AppRuntime 装配。 |
| `OpenWriting/AppRootView.swift` | 根级导航、侧边栏、账户中心和 Apple ID 登录入口。 |
| `OpenWriting/AppearanceSettingsView.swift` | 设置页、模型连接、隐私授权、写作台显示、排版和帮助。 |
| `OpenWriting/AppLogger.swift` | OSLog 分类入口。 |
| `OpenWriting/UserFacingError.swift` | AI、同步、导出和持久化错误的用户可读文案。 |

## 状态、账户与同步

| File | Role |
| --- | --- |
| `OpenWriting/AppState.swift` | 应用主状态协调器，承接项目、模型配置、导航、搜索和写作台状态。 |
| `OpenWriting/AppState+Account.swift` | Apple 账户绑定、登出、账号 scope 项目加载和本机账号资料清理。 |
| `OpenWriting/AppState+Persistence.swift` | UserDefaults/Keychain 存储键、迁移和持久化 helper。 |
| `OpenWriting/AppState+WritingSkills.swift` | 写作技能启用、禁用、导入和项目注入。 |
| `OpenWriting/AppState+iCloudSync.swift` | iCloud 可用性、快照推拉、云端状态和云端/本地合并。 |
| `OpenWriting/AccountSync.swift` | Apple ID profile、CloudKit 快照索引、payload 分片和 fallback 读取。 |
| `OpenWriting/CommerceEntitlements.swift` | 商业化权益模型、产品描述和延后 StoreKit 接入 provider。 |
| `OpenWriting/ModelConnectionConfigurationStore.swift` | 模型连接配置、托管 OpenWriting endpoint、Keychain API key 存储。 |

## 领域模型与长篇系统

| File | Role |
| --- | --- |
| `OpenWriting/DomainModels.swift` | 小说、章节、参考文档、章节版本、全局记忆、时间戳和核心 Codable 模型。 |
| `OpenWriting/LongformStorySystem.swift` | 长篇合同、章节提交验证、阻断规则和运行时状态。 |
| `OpenWriting/ChapterTreeRefresh.swift` | 章节树刷新结构、解析结果和安全回写结果。 |
| `OpenWriting/StrandWeaveTracker.swift` | Quest/Fire/Constellation 节奏追踪和 AI 分析入口。 |
| `OpenWriting/WritingMemoryBuckets.swift` | 七类长篇记忆桶、记忆项和合并/裁剪逻辑。 |
| `OpenWriting/MemoryExtractionService.swift` | 章节记忆抽取 prompt、解析和提取结果模型。 |
| `OpenWriting/NovelProject+WebnovelIntegration.swift` | Webnovel 写作集成字段、旧 UserDefaults 双写兼容和清理入口。 |
| `OpenWriting/PrewriteValidator.swift` | 写前验证、阻断项和 checklist。 |
| `OpenWriting/ContextRanker.swift` | 上下文片段排序、实体抽取和引用权重。 |

## AI 与质量

| File | Role |
| --- | --- |
| `OpenWriting/AIWritingService.swift` | 模型请求、连接验证、基础续写、文本改写、拟标题和 BM25 引用检索。 |
| `OpenWriting/AIWritingService+Enhanced.swift` | 增强续写、写前验证、题材模板注入、审查和记忆更新上下文。 |
| `OpenWriting/AIWritingService+Prompts.swift` | AI prompt 构造和写作支持上下文文本。 |
| `OpenWriting/AIWritingServicing.swift` | AI 服务协议和默认静态服务适配器，用于依赖注入和测试 mock。 |
| `OpenWriting/ChapterQualityReviewer.swift` | 统一章节质量审查、JSON 解析、启发式问题和反 AI 味检查。 |
| `OpenWriting/QualityReviewService.swift` | 旧质量审查入口的兼容说明与转接。 |

## 写作台与工作区 UI

| File | Role |
| --- | --- |
| `OpenWriting/WritingDeskView.swift` | 正文写作主界面、用户交互和章节写作会话调用。 |
| `OpenWriting/WritingDeskSessionModels.swift` | 章节写作会话状态、请求上下文、过期结果校验和字数策略。 |
| `OpenWriting/WritingDeskNavigationViews.swift` | 写作台章节导航、章节载入确认和正文差异预览。 |
| `OpenWriting/WritingDeskDraftProcessingViews.swift` | 写作台草稿处理请求、进度和结果交互。 |
| `OpenWriting/WritingDeskStatusViews.swift` | 写作台状态、长篇提示和质量审查面板。 |
| `OpenWriting/WritingDeskSupportViews.swift` | 写作台共享布局、文本表面、NSTextView 正文编辑器和弹层组件。 |
| `OpenWriting/WritingDeskOutlineGeneratorSheet.swift` | 大纲生成 sheet 和参数表单。 |
| `OpenWriting/OutlineWorkspacePanel.swift` | 章节目录、章节树、全局记忆和长篇支撑面板。 |
| `OpenWriting/ProjectSavedChaptersSheet.swift` | 项目已保存章节 sheet。 |
| `OpenWriting/SavedChapterBrowserComponents.swift` | 已保存章节目录、预览和共享列表组件。 |
| `OpenWriting/ReferenceDocumentImporting.swift` | 参考文本导入模型与结果。 |
| `OpenWriting/ScrollTopBounceLockView.swift` | 写作台滚动回弹控制。 |

## 首页、资源与模板

| File | Role |
| --- | --- |
| `OpenWriting/HomeDashboardView.swift` | 首页工作台、项目概览、入口卡片和项目空间。 |
| `OpenWriting/PlaceholderWorkspaceView.swift` | 尚未展开工作区的占位页。 |
| `OpenWriting/NewProjectSheet.swift` | 新建项目 sheet。 |
| `OpenWriting/WritingSkill.swift` | 写作技能模型、导入格式和 prompt 注入。 |
| `OpenWriting/WritingSkillLibraryView.swift` | 写作技能库 UI。 |
| `OpenWriting/GenreTemplateData.swift` | 新题材模板基础枚举和参数类型。 |
| `OpenWriting/GenreTemplateEngine.swift` | 新题材模板库、旧模板迁移和模板匹配。 |
| `OpenWriting/GenreTemplates.swift` | 旧题材模板库和别名 lookup。 |
| `OpenWriting/GenreTemplateBrowserView.swift` | 题材模板浏览 UI。 |
| `OpenWriting/LiteraryQuoteLibrary.swift` | 文学引言 TSV 加载和随机引用。 |

## 导入、导出与文件存储

| File | Role |
| --- | --- |
| `OpenWriting/ProjectFileStore.swift` | 本地项目分片存储、原子写、健康检查和恢复动作。 |
| `OpenWriting/ProjectExportService.swift` | JSON/Markdown/DOCX/EPUB 导出、ZIP 构建和导出校验。 |
| `OpenWriting/TextFileDecoding.swift` | 文本文件编码识别和解码兜底。 |
| `OpenWriting/DateFormatting.swift` | 时间标签格式化视图。 |

## Dashboard 与审查组件

| File | Role |
| --- | --- |
| `OpenWriting/QualityReviewDashboardView.swift` | 完整质量审查报告 dashboard。 |
| `OpenWriting/DashboardComponents.swift` | Dashboard 复用视觉组件。 |
| `OpenWriting/DashboardTheme.swift` | Dashboard 色彩和主题 token。 |
| `OpenWriting/AntiPatternsSection.swift` | 反模式 section。 |
| `OpenWriting/BlockingIssueCard.swift` | 阻断问题卡片。 |
| `OpenWriting/DimensionBarRow.swift` | 维度分数条。 |
| `OpenWriting/DimensionScoresPanel.swift` | 维度分数面板。 |
| `OpenWriting/IssuesSection.swift` | 问题列表 section。 |
| `OpenWriting/NonBlockingIssueRow.swift` | 非阻断问题行。 |
| `OpenWriting/PassStatusBadge.swift` | 通过状态徽标。 |
| `OpenWriting/ReviewSummarySection.swift` | 审查摘要 section。 |
| `OpenWriting/ScoreGaugeRing.swift` | 分数环形仪表。 |
| `OpenWriting/SidebarItem.swift` | 侧边栏枚举和显示信息。 |

## 阅读顺序建议

1. `OpenWriting/OpenWritingApp.swift`
2. `OpenWriting/AppWindowCoordinator.swift`
3. `OpenWriting/AppState.swift`
4. `OpenWriting/AppState+Persistence.swift`
5. `OpenWriting/DomainModels.swift`
6. `OpenWriting/ProjectFileStore.swift`
7. `OpenWriting/AccountSync.swift`
8. `OpenWriting/AppState+iCloudSync.swift`
9. `OpenWriting/AIWritingServicing.swift`
10. `OpenWriting/AIWritingService.swift`
11. `OpenWriting/AIWritingService+Enhanced.swift`
12. `OpenWriting/WritingDeskView.swift`
