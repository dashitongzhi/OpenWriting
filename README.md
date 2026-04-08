# OpenWriting

OpenWriting 是一个面向长篇小说创作的 macOS 原生写作工作台。当前工程已经迁移为 Xcode App 工程，核心能力包括项目管理、章节写作、大纲整理、参考资料导入、AI 辅助写作，以及基于 Apple ID + iCloud/CloudKit 的账户同步。

## 当前状态

- 平台：macOS
- UI：SwiftUI + AppKit 窗口协调
- 工程形态：Xcode 工程 `OpenWriting.xcodeproj`
- 同步方案：`Sign in with Apple` + `CloudKit private database`
- 本地数据：`UserDefaults` + 账户隔离的项目快照

## 核心能力

- 小说项目创建、切换与多项目工作区管理
- 章节正文写作、章节草稿存档与回载
- 大纲、结构备注、场景进度、角色弧线、伏笔追踪
- 世界观/参考资料导入与分类管理
- AI 续写、润色、章节命名、大纲生成、全局记忆刷新
- Apple ID 登录与 iCloud 项目同步

## 运行要求

- Xcode
- 可用的 Apple Developer Team
- 若要验证 Apple ID 登录和 iCloud 同步，需要在 target 上启用：
  - `Sign In with Apple`
  - `iCloud` -> `CloudKit`

## 本地运行

1. 用 Xcode 打开 [OpenWriting.xcodeproj](/Users/kral/Desktop/OpenWriting/OpenWriting.xcodeproj)。
2. 选择 `OpenWriting` target。
3. 在 `Signing & Capabilities` 中确认：
   - `Team` 为有效开发团队
   - `Bundle Identifier` 与容器配置一致
   - `Sign In with Apple` 已开启
   - `iCloud` 与 `CloudKit` 已开启
4. 选择 `My Mac` 运行。

如果 capability 或签名不完整，应用仍可本地运行，但账户登录和云同步会回退为本机保存状态。

## 仓库结构

- [OpenWriting](/Users/kral/Desktop/OpenWriting/OpenWriting)：人工维护的应用源码
- [OpenWriting.xcodeproj](/Users/kral/Desktop/OpenWriting/OpenWriting.xcodeproj)：Xcode 工程
- [INDEX.md](/Users/kral/Desktop/OpenWriting/INDEX.md)：源码索引，只收录代码文件

## 代码阅读建议

- 先看 [OpenWriting/OpenWritingApp.swift](/Users/kral/Desktop/OpenWriting/OpenWriting/OpenWritingApp.swift)：应用入口
- 再看 [OpenWriting/AppWindowCoordinator.swift](/Users/kral/Desktop/OpenWriting/OpenWriting/AppWindowCoordinator.swift)：窗口与运行时装配
- 然后看 [OpenWriting/AppState.swift](/Users/kral/Desktop/OpenWriting/OpenWriting/AppState.swift)：应用状态与核心数据模型
- 最后看 [OpenWriting/AppRootView.swift](/Users/kral/Desktop/OpenWriting/OpenWriting/AppRootView.swift)、[OpenWriting/HomeDashboardView.swift](/Users/kral/Desktop/OpenWriting/OpenWriting/HomeDashboardView.swift)、[OpenWriting/WritingDeskView.swift](/Users/kral/Desktop/OpenWriting/OpenWriting/WritingDeskView.swift)：主界面与功能视图

## 说明

- [INDEX.md](/Users/kral/Desktop/OpenWriting/INDEX.md) 故意不收录构建产物、Xcode 用户态文件、资源文件和编译输出。
- 当前仓库里保留了 [OpenWriting/ContentView.swift](/Users/kral/Desktop/OpenWriting/OpenWriting/ContentView.swift)，它是 Xcode 模板残留，不参与主界面入口。
