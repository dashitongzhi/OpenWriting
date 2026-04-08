# Code Index

本索引只收录人工维护的 Swift 源码文件。

不收录：
- `.build/`
- `DerivedData/`
- `.swiftpm/`
- `.xcodeproj/xcuserdata/`
- `Assets.xcassets`
- `Resources/`
- 任何编译产物、缓存、签名输出和 Xcode 自动生成内容

## 应用入口与装配

| File | Lines | Key Types | Role |
| --- | ---: | --- | --- |
| `OpenWriting/OpenWritingApp.swift` | 48 | `OpenWritingApp`, `OpenWritingAppDelegate` | 应用入口，接管 macOS 生命周期，启动主窗口与设置入口。 |
| `OpenWriting/AppWindowCoordinator.swift` | 422 | `AppRuntime`, `AppWindowCoordinator`, `MainWindowController`, `SettingsWindowController` | 负责根状态注入、主窗口/设置窗口创建、工具栏和窗口外观协调。 |
| `OpenWriting/AppRootView.swift` | 753 | `AppRootView`, `SidebarItem` | 根级导航容器，承接侧边栏、详情区域、账户面板和 Apple ID 登录入口。 |
| `OpenWriting/AppearanceSettingsView.swift` | 202 | `AppAppearance`, `AppearanceSettingsView`, `ModelConnectionSettingsForm` | 设置界面，负责外观和模型连接参数配置。 |
| `OpenWriting/ContentView.swift` | 24 | `ContentView` | Xcode 模板残留文件，当前不参与主应用入口。 |

## 状态、数据与同步

| File | Lines | Key Types | Role |
| --- | ---: | --- | --- |
| `OpenWriting/AppState.swift` | 2300 | `AppState`, `NovelProject`, `ChapterDraft`, `ReferenceDocument`, `GlobalMemorySnapshot` 等 | 应用主状态中心，管理项目、配置、导航、持久化、同步触发和大部分领域模型。 |
| `OpenWriting/AccountSync.swift` | 353 | `AppleAccountProfile`, `AccountProjectSnapshot`, `ICloudProjectStore` | Apple ID 状态识别、entitlement 检测、CloudKit 快照读写与 iCloud 可用性判断。 |
| `OpenWriting/AIWritingService.swift` | 634 | `AIConnectionConfiguration`, `AIWritingMode`, `AIWritingLength`, `AIWritingService` | AI 请求封装，提供续写、润色、章节命名、大纲生成和全局记忆刷新。 |
| `OpenWriting/LiteraryQuoteLibrary.swift` | 124 | `LiteraryQuote`, `LiteraryQuoteLibrary` | 文学引言加载与随机抽取工具，供界面展示引用内容。 |

## 主要功能视图

| File | Lines | Key Types | Role |
| --- | ---: | --- | --- |
| `OpenWriting/HomeDashboardView.swift` | 4033 | `HomeDashboardView`, `PlaceholderWorkspaceView` 及大量界面子组件 | 首页工作台、项目概览、快捷入口、参考资料导入与多个工作区占位视图。 |
| `OpenWriting/WritingDeskView.swift` | 1991 | `WritingDeskView` | 正文写作主界面，聚焦章节编辑、草稿保存、参考资料与 AI 写作工作流。 |
| `OpenWriting/OutlineWorkspacePanel.swift` | 290 | `OutlineWorkspacePanel` | 大纲工作区面板，负责章节结构、摘要和相关编辑视图。 |

## 阅读顺序建议

1. `OpenWriting/OpenWritingApp.swift`
2. `OpenWriting/AppWindowCoordinator.swift`
3. `OpenWriting/AppState.swift`
4. `OpenWriting/AccountSync.swift`
5. `OpenWriting/AppRootView.swift`
6. `OpenWriting/HomeDashboardView.swift`
7. `OpenWriting/WritingDeskView.swift`
8. `OpenWriting/OutlineWorkspacePanel.swift`
9. `OpenWriting/AIWritingService.swift`
10. `OpenWriting/LiteraryQuoteLibrary.swift`
