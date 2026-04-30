# Code Index

本索引只收录人工维护的 Swift 源码文件，重点说明职责分工，不再维护易失真的精确行数。

不收录：
- `.build/`
- `DerivedData/`
- `.swiftpm/`
- `.xcodeproj/xcuserdata/`
- `.claude/settings.json`
- `Assets.xcassets`
- `Resources/`
- 任何编译产物、缓存、签名输出和 Xcode 自动生成内容

## 应用入口与装配

| File | Key Types | Role |
| --- | --- | --- |
| `OpenWriting/OpenWritingApp.swift` | `OpenWritingApp`, `OpenWritingAppDelegate` | 应用入口，接管 macOS 生命周期，启动主窗口与设置入口。 |
| `OpenWriting/AppWindowCoordinator.swift` | `AppRuntime`, `AppWindowCoordinator`, `MainWindowController`, `SettingsWindowController` | 根状态注入、主窗口/设置窗口创建、工具栏和窗口外观协调。 |
| `OpenWriting/AppRootView.swift` | `AppRootView`, `SidebarItem` | 根级导航容器，承接侧边栏、详情区域、账户面板和 Apple ID 登录入口。 |
| `OpenWriting/AppearanceSettingsView.swift` | `AppAppearance`, `AppearanceSettingsView`, `ModelConnectionSettingsForm` | 设置界面，负责外观和模型连接参数配置。 |

## 状态、数据与同步

| File | Key Types | Role |
| --- | --- | --- |
| `OpenWriting/AppState.swift` | `AppState` | 应用主状态中心，负责项目编辑、界面导航、持久化触发与状态协同。 |
| `OpenWriting/AppState+Account.swift` | `AppState` 扩展 | Apple 账户绑定、账号隔离项目加载、旧存储迁移辅助。 |
| `OpenWriting/AppState+iCloudSync.swift` | `AppState` 扩展 | iCloud 可用性检查、快照推送与拉取、云端状态回写。 |
| `OpenWriting/AccountSync.swift` | `AppleAccountProfile`, `AccountProjectSnapshot`, `ICloudProjectStore` | Apple ID 状态识别、entitlement 检测、CloudKit 快照读写与 iCloud 可用性判断。 |
| `OpenWriting/DomainModels.swift` | `NovelLength`, `NovelProject`, `ChapterDraft`, `ReferenceDocument`, `GlobalMemorySnapshot`, `PersistedTimestampCodec` 等 | 领域模型、兼容时间戳编解码与项目核心数据结构。 |
| `OpenWriting/DateFormatting.swift` | `TimestampLabel` | 首页与工作区复用的时间标签辅助。 |
| `OpenWriting/ProjectFileStore.swift` | `ProjectFileStore` | 本地项目文件存储、按账号 scope 隔离读写、旧 `UserDefaults` 项目数据承接。 |
| `OpenWriting/ProjectExportService.swift` | `ProjectExportService`, `ZipArchiveBuilder` | 项目本地导出，生成备份 JSON、Markdown、DOCX 与 EPUB 成书文件。 |
| `OpenWriting/TextFileDecoding.swift` | `TextFileDecoding` | 文本导入编码识别与解码兜底，兼容 UTF 系列与常见中文编码。 |
| `OpenWriting/ChapterTreeRefresh.swift` | `ChapterTreeRefresh`, `ChapterTreeRefreshBaseline`, `ChapterTreeRefreshApplyOutcome` | 章节树结构化刷新结果、解析和回写保护模型。 |
| `OpenWriting/AIWritingService.swift` | `AIConnectionConfiguration`, `AIWritingMode`, `AIWritingLength`, `AIWritingService` | AI 请求封装，提供续写、章节命名、大纲生成、全局记忆刷新和章节树结构化刷新。 |
| `OpenWriting/LiteraryQuoteLibrary.swift` | `LiteraryQuote`, `LiteraryQuoteLibrary` | 文学引言加载与随机抽取工具，供界面展示引用内容。 |

## 主要功能视图

| File | Key Types | Role |
| --- | --- | --- |
| `OpenWriting/HomeDashboardView.swift` | `HomeDashboardView`, `PlaceholderWorkspaceView` 及首页子视图 | 首页工作台、项目概览、项目空间、素材库和多个工作区入口。 |
| `OpenWriting/WritingDeskView.swift` | `WritingDeskView` | 正文写作主界面，负责章节编辑、保存、AI 续写和保存后上下文刷新。 |
| `OpenWriting/WritingDeskSupportViews.swift` | `WritingDeskCollapsedLayout`, `WritingDeskTextSurface`, `WritingDeskBounceLockView` 等 | 写作台共享布局、编辑器表面、时间线和滚动锁定视图。 |
| `OpenWriting/WritingDeskOutlineGeneratorSheet.swift` | `WritingDeskOutlineGeneratorSheet` | 大纲生成弹窗与其表单子组件。 |
| `OpenWriting/OutlineWorkspacePanel.swift` | `OutlineWorkspacePanel` | 章节目录、章节树工作区、全局记忆和长中短篇支撑面板。 |
| `OpenWriting/ProjectSavedChaptersSheet.swift` | `ProjectSavedChaptersSheet` | 项目空间中的已创作章节弹窗。 |
| `OpenWriting/SavedChapterBrowserComponents.swift` | `SavedChapterDirectoryList`, `SavedChapterPreviewPanel`, `SavedChapterPreviewSurface` | 章节目录与章节预览的共享组件。 |

## 阅读顺序建议

1. `OpenWriting/OpenWritingApp.swift`
2. `OpenWriting/AppWindowCoordinator.swift`
3. `OpenWriting/AppState.swift`
4. `OpenWriting/AppState+Account.swift`
5. `OpenWriting/AppState+iCloudSync.swift`
6. `OpenWriting/DomainModels.swift`
7. `OpenWriting/ProjectFileStore.swift`
8. `OpenWriting/TextFileDecoding.swift`
9. `OpenWriting/AccountSync.swift`
10. `OpenWriting/ChapterTreeRefresh.swift`
11. `OpenWriting/AppRootView.swift`
12. `OpenWriting/HomeDashboardView.swift`
13. `OpenWriting/WritingDeskView.swift`
14. `OpenWriting/WritingDeskSupportViews.swift`
15. `OpenWriting/WritingDeskOutlineGeneratorSheet.swift`
16. `OpenWriting/OutlineWorkspacePanel.swift`
17. `OpenWriting/ProjectSavedChaptersSheet.swift`
18. `OpenWriting/SavedChapterBrowserComponents.swift`
19. `OpenWriting/AIWritingService.swift`
20. `OpenWriting/LiteraryQuoteLibrary.swift`
