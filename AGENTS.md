# Agent Modification Guide

本文件是智能体进入本仓库后的必读说明。修改代码前先读本文件，再读 `INDEX.md` 中对应模块说明。

## Xcode 编译规则

- `OpenWriting.xcodeproj` 使用 `PBXFileSystemSynchronizedRootGroup` 管理 `OpenWriting/` 目录。
- 这意味着 `OpenWriting/` 下新增的 `.swift` 文件会被 Xcode 自动纳入 target 编译，即使没有手动加入 `project.pbxproj`。
- 不要把临时草稿、半成品拆分文件、备份文件或实验性 Swift 文件放进 `OpenWriting/`。
- 如果需要保存非编译参考内容，放到根目录文档、`Tests/` 之外的专用文档目录，或使用非 `.swift` 文件。

## 拆分 Swift 文件时的硬性流程

1. 先确认原文件里是否已经存在同名类型。
   - 常见风险类型包括 `HomeDashboardView`、`PlaceholderWorkspaceView`、`WritingDeskView`、`WritingDeskTextSurface`、`AIWriterTimingSnapshot`、`WritingDeskToolbarAction`。
2. 新文件中迁移类型后，必须从原文件删除对应定义。
3. 不要同时保留“原实现”和“新拆分实现”。
4. 如果新文件只是准备稿，不要放在 `OpenWriting/` 目录下。
5. 拆分跨文件使用的类型时，检查访问级别。
   - 被其他 Swift 文件引用的类型不能是 `private`。
   - 原来只在单文件内使用的 `private` 类型，迁出后通常需要改成 internal 默认级别。
6. 每次拆分后立刻运行 Debug 构建，不要等多个大改混在一起。

## 字符串与中文文案

- Swift 字符串里不要直接嵌套英文双引号。
  - 推荐：`Text("点击“新建项目”开始")`
  - 或者转义：`Text("点击\"新建项目\"开始")`
- 多行字符串 `"""` 的内容必须从下一行开始。
- UI 文案改动后优先跑构建，因为一个未闭合字符串会制造大量假错误。

## 题材模板接口

- `GenreTemplate` 的 prompt 注入统一使用 `formattedForPrompt`。
- 新增模板字段后，同步检查：
  - `GenreTemplateData.swift`
  - `GenreTemplateEngine.swift`
  - `AIWritingService+Prompts.swift`
  - `AIWritingService+Enhanced.swift`
  - `NovelProject+WebnovelIntegration.swift`

## 必跑验证

修改 Swift 源码后运行：

```zsh
./scripts/build-debug.sh
```

注意：系统 `xcode-select` 可能指向 Command Line Tools。仓库脚本会显式使用 `/Applications/Xcode.app/Contents/Developer`，优先用脚本验证。

构建通过后再交付。若构建失败，先处理第一批真实 Swift error，再重新构建；不要只修表层报错。

## Git 操作

- 默认直接在 `main`（或仓库实际远端主分支）修改；不要创建任务分支或 PR，除非用户明确要求 PR。
- 修改前 fetch 并确认主分支与远端的分歧；安全时才切换或快进，不覆盖用户现有改动。
- 验证后只提交本任务相关文件，并直接 push 到主分支。
- 不要 reset、checkout 或 revert 未确认的改动，也不要把无关改动混入提交。
- 如果认证、权限、CI、分支保护、分歧或工作区状态阻止安全直推，汇报 blocker 并保留本地改动；不要退回任务分支或 PR。
- 最终报告使用中文，并说明改动、验证以及主分支 commit/push 状态。
