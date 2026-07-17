# OpenWriting 项目架构深度审查报告

本报告由资深软件工程师针对 `OpenWriting` 仓库的当前代码架构、数据流管理、持久化设计、AI 写作流水线及项目长期可迭代性进行深度审查，旨在确保项目作为一个可以长期高频迭代、管理方便的优秀软件系统。

---

## 1. 架构总览与核心设计亮点

`OpenWriting` 作为一个以 AI 辅助为核心、面向长篇叙事创作的 macOS 原生应用，在架构设计上具有不少可圈可点的亮点，体现了对业务场景与 macOS 系统特性的深度理解：

*   **业务领域驱动设计 (Domain-Driven Design)**：通过 `CONTEXT.md` 明确规范了“章节写作会话”、“候选稿”、“章节收录”及“长篇后台投影”等专有领域词汇，代码命名（如 `continueChapterEnhanced`、`ChapterSaveValidationContext`）能高度对应业务场景。
*   **出色的持久化分片设计 (Sharded File Store)**：`ProjectFileStore` 抛弃了将整本小说（百万字级别）打包存入单一 JSON 的低效方案，而是采用 `index.json`（索引） + `project.json`（元数据） + `chapters/<id>.json`（章节内容分片懒加载）的设计。这在海量文本场景下能极大地降低文件 I/O 开销与序列化延迟。
*   **指纹防重写过滤 (Write Cache)**：在 `writeIfChanged` 中引入了基于 `SHA256` 内存指纹的防重写缓存机制，有效避免了无修改时的冗余磁盘写入，保护了 SSD 并减少了系统 I/O 损耗。
*   **严密的本地守护门禁 (Guard & Verification)**：拥有本地 Git 预检脚本 (`git-preflight.sh`)、类型检查以及 Xcode 宿主测试驱动，能有效降低多人或智能体协作时的代码合并风险。

---

## 2. 核心架构痛点与潜在风险

为了让项目能够支撑长期的高频迭代、方便管理与新功能的无缝扩展，我们需要关注以下五个核心架构痛点：

### 2.1 状态管理：`AppState` 逐渐演变成“神级对象” (God Object)
*   **现状分析**：
    `AppState` (`AppState.swift`) 承担了过多的职责：
    1.  **用户偏好配置**：字体大小、行间距、是否开启聚焦模式等。
    2.  **网络与 AI 连接配置**：API Key、Base URL、提供商状态以及连接检测。
    3.  **iCloud 同步协调**：快照推拉、网络可用性、账号绑定状态以及同步进度维护。
    4.  **底层存储调用**：管理 `ProjectFileStore` 数据的载入、保存和数据校正。
    5.  **业务逻辑流转**：小说项目列表、活跃项目、内购权益状态。
*   **潜在风险**：
    *   **破坏单一职责原则 (SRP)**：随着业务增长，该类体积会无限膨胀（目前已达 2500 行），类之间的逻辑高度耦合，难以单独编写 Mock 单元测试。
    *   **视图过度重绘**：在 SwiftUI `@Observable` 机制下，如果所有 View 都绑定同一个巨大的 `AppState`，部分细微的状态改变（如配置项或云端同步状态变更）可能会引发不必要的全局视图关联计算。
*   **重构建议**：
    *   将偏好设置（字体、行距、界面折叠）归入 `EditorSettingsStore`（使用 `@Observable`）。
    *   将 iCloud 云端同步状态、Apple 账号验证剥离到 `SyncCoordinator`。
    *   `AppState` 降级为轻量级的应用根状态和导航协调器，不再插手具体的文件读写和业务逻辑。

### 2.2 UI 逻辑堆积：`WritingDeskView` 超大视图 (Massive View)
*   **现状分析**：
    `WritingDeskView.swift` 文件长达 3800 多行，且在类内部定义了超过 50 个 `@State` 状态变量，包含了从选区润色弹窗、搜索替换逻辑、到各种后台 Swift Concurrency Task 异步任务的生命周期管理。
*   **潜在风险**：
    *   **编译速度劣化**：Swift 编译器在解析包含大量闭包、类型推导和复杂 SwiftUI 组件层级的超长文件时，性能会急剧下降。
    *   **重构与维护成本极高**：界面排版代码和生成控制逻辑交织在一起。例如，AI 生成时的 Loading 状态、倒计时、中途打断、分流处理全部通过局部变量控制，其他类无法复用或感知。
    *   **代码坏味道**：一些面板虽然已经被物理拆分（如 `WritingDeskDraftProcessingViews.swift` 等），但由于数据状态未解耦，主视图仍需要通过传递极其繁琐的 `Binding` 或者回调 Closure 来与其通信。
*   **重构建议**：
    *   创建一个由 `@MainActor` 标记的 `WritingDeskViewModel`，托管 `isGenerating`、`aiStatusMessage`、`timingSnapshot` 以及相关的异步请求 Task。
    *   组件拆分：将正文 NSTextView 包装层完全独立成 `DraftEditorContainer`；将 AI 候选稿展示和参数配置面板拆离成 `AISuggestionCardView`。主界面只负责骨架排版，具体逻辑全部通过 ViewModel 与子视图契约式流转。

### 2.3 数据 schema 演进：缺乏显式迁移管道 (Ad-hoc Schema Migration)
*   **现状分析**：
    在 `DomainModels.swift` 中，`NovelProject` 每次反序列化时都在 `init(from decoder:)` 中依据 `schemaVersion` 进行 `decodeIfPresent` 并附带 fallback 默认值来实现“隐式迁移”：
    ```swift
    let decodedSchemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
    schemaVersion = max(decodedSchemaVersion, Self.currentSchemaVersion)
    // 后续大量 decodeIfPresent(..., forKey: ...) ?? defaultValue
    ```
*   **潜在风险**：
    *   **破坏性改动的致命漏洞**：这种方式只适用于“新增非必填字段”。如果后续发生破坏性改动（例如某个字段类型发生变更、或者结构体需要拆分），`Decoder` 会直接抛出解析失败，导致用户本地项目**直接损坏，无法打开**。
    *   **代码难以维护**：随着版本迭代（如 v2 -> v10），初始化函数中将堆满各种历史兼容代码，业务模型会彻底丧失可读性。
*   **重构建议**：
    *   设计显式的 `ProjectStoreMigrationManager` 管道。在交由 `JSONDecoder` 解码之前，以 Dictionary 形式完成物理数据的版本升级：
    ```swift
    struct ProjectStoreMigrationManager {
        static func migrate(_ rawData: Data, toVersion targetVersion: Int) throws -> Data {
            var json = try JSONSerialization.jsonObject(with: rawData) as? [String: Any] ?? [:]
            var currentVersion = json["schemaVersion"] as? Int ?? 1
            
            while currentVersion < targetVersion {
                json = try performMigration(json, from: currentVersion)
                currentVersion += 1
            }
            json["schemaVersion"] = targetVersion
            return try JSONSerialization.data(withJSONObject: json)
        }
    }
    ```

### 2.4 性能隐患：主线程文件 I/O 与 CPU 密集哈希计算
*   **现状分析**：
    虽然 `AppState` 声明了 `@MainActor` 确保 UI 刷新安全，但在 `scheduleRecentProjectsPersistence` 中：
    ```swift
    recentProjectsPersistTasks[storageKey] = Task {
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        self.persistRecentProjects(snapshot, for: scope) // 在 MainActor 上执行文件写入
    }
    ```
    因为 Task 继承了 `@MainActor` 上下文，导致真正的 JSON 序列化、磁盘写入以及 `stableHash` 中的 `SHA256` 密集计算全都在**主线程**执行。
*   **潜在风险**：
    *   长篇小说正文、大纲、记忆桶的数据量非常庞大。在用户输入或自动保存时，如果主线程频繁被耗时约数十毫秒的 I/O 阻塞，会导致严重的界面卡顿（Dropped Frames）和输入延迟。
*   **重构建议**：
    *   将 `ProjectFileStore` 重构为 Swift Concurrency `actor`（或者内部的 `writeIfChanged` 以及哈希计算改由非 MainActor 的全局后台线程执行）。
    *   这样，即使文件体积非常庞大，序列化和写盘也不会占用宝贵的主线程时钟，彻底根治写作卡顿风险。

### 2.5 仓库一致性：文档与物理代码冲突 (Out-of-date INDEX.md)
*   **现状分析**：
    `INDEX.md` 中记录的 `OpenWriting/WritingDeskPanels.swift` 物理文件在代码中已不存在（已经被重构拆分为 `WritingDeskDraftProcessingViews.swift` 等三个细分文件），但是索引说明未同步更新。这表明缺乏自动化手段维护架构文档的正确性。
*   **重构建议**：
    *   在 `scripts/run-all-checks.sh` 中增加一步静态校验：通过 Shell 脚本自动扫描 `OpenWriting/` 下的 Swift 文件，并与 `INDEX.md` 进行行比对，若有不一致则报错打断构建，从而保证文档与代码库的永远同步。

---

## 3. 架构优化比照图与演进路线图

### 3.1 架构比照

```mermaid
graph TD
    subgraph 现状 (耦合度高)
        AppState[AppState God Object]
        AppState --> userDefaults[UserDefaults / UI Settings]
        AppState --> projectStore[ProjectFileStore MainActor]
        AppState --> iCloudSync[ICloudProjectStore Sync]
        AppState --> commerceProvider[Commerce / Entitlements]
        
        WritingDeskView[WritingDeskView 3800+ 行]
        WritingDeskView --> AppState
    end

    subgraph 建议重构 (低耦合/高性能)
        WritingDeskView2[WritingDeskView 纯视图布局]
        WritingDeskViewModel[WritingDeskViewModel 状态机]
        
        ProjectRepository[ProjectRepository 核心仓储]
        SettingsStore[SettingsStore 偏好设置]
        SyncCoordinator[SyncCoordinator 异步同步协调]
        CommerceStore[CommerceStore 订阅管理]

        WritingDeskView2 -->|绑定| WritingDeskViewModel
        WritingDeskViewModel -->|加载/保存| ProjectRepository
        WritingDeskViewModel -->|获取设置| SettingsStore
        
        ProjectRepository -->|Actor 安全后台写| ProjectFileStore2[ProjectFileStore actor]
        SyncCoordinator -->|后台协调| ProjectRepository
        SyncCoordinator -->|云端推拉| ICloudProjectStore2[ICloudProjectStore actor]
    end
```

### 3.2 落地行动路线图

为保证系统在迭代中不会被引入回归缺陷，重构应分阶段、以“小步快跑”的形式推进：

| 阶段 | 任务目标 | 核心验证手段 | 风险评级 |
| :--- | :--- | :--- | :--- |
| **Phase 1** | **文档一致性修复**：更新 `INDEX.md`，增加校验脚本 | 运行 `./scripts/run-all-checks.sh` | 🟢 极低 |
| **Phase 2** | **主线程 I/O 解耦**：将 `ProjectFileStore` 内部写入操作移至后台并发任务 | 运行 `ProjectFileStoreTests` 与性能耗时测试 | 🟡 中等 |
| **Phase 3** | **显式迁移管道引入**：重构 `NovelProject` 历史兼容逻辑 | 运行 `DomainModelsTests`（构造历史版本数据测试） | 🔴 较高 |
| **Phase 4** | **视图逻辑解耦**：为 `WritingDeskView` 抽离核心 ViewModel | 运行 hosted Xcode tests，检查 UI 状态联动 | 🔴 较高 |

---

## 4. 构建与测试结果反馈

在审查代码的同时，我们在本地命令行环境下执行了完整的 `run-all-checks.sh` 脚本：
1.  **编译检查**：在 macOS 环境下，主 app 代码 debug 编译构建成功。
2.  **脚本验证**：类型检查、长篇质量门禁、双百万字内存连贯性 soak 均无警告地完美通过。
3.  **托管单元测试失败分析**：
    *   在进入 `DomainModelsTests` 测试类执行阶段时，命令行报出错误：`"OpenWriting" requires a provisioning profile. Enable development signing...`。
    *   **审查定位**：该问题由于命令行运行 `xcodebuild test` 时启用了 `CODE_SIGNING_ALLOWED=YES` 且 `DEVELOPMENT_TEAM` 为空，在当前沙箱/代理开发机上缺乏对应的 Apple 开发者证书而触发的 Xcode 签名强制校验阻断，**并非代码本身的逻辑或单元测试用例编写错误**。
    *   **处理办法**：本地开发者在 Xcode UI 界面中对该 Target 勾选 "Automatically manage signing" 或设置为 ad-hoc 本地开发证书签名即可完美运行。

本任务未对主仓库的代码及配置进行任何破坏性实质修改，因此没有可提交到 `main` 分支的变更。
