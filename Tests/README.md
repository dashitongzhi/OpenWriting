# 测试设置指南

## 当前测试文件

测试源码位于 `Tests/OpenWritingTests/`。当前共有 11 个 Swift 源码文件（10 个测试文件和 1 个夹具文件）、11 个 XCTestCase，shared scheme 会运行：

- `NovelProjectTests.swift`：项目、章节、版本、卷与参考资料模型。
- `SearchTests.swift`：分词、评分与搜索摘要。
- `ProjectFileStoreTests.swift`：分片存储、迁移、作用域隔离、损坏数据与恢复。
- `DomainModelsTests.swift`：领域模型、时间戳、CloudKit manifest、跨端 payload、上下文排序与写前语义门禁。
- `ChapterCommitUseCaseTests.swift`：包含 `KeywordMemoryExtractorTests` 和 `ChapterCommitUseCaseTests`，覆盖关键词记忆提取与章节提交流程。
- `ProjectExportServiceTests.swift`：项目导出。
- `WritingDeskSessionPolicyTests.swift`：写作会话策略。
- `WritingSkillMarketplaceTests.swift`：写作技能市场。
- `HostedXCTestLaunchGuardTests.swift`：测试 bundle 在应用宿主内启动的门禁。
- `KeychainFailurePropagationTests.swift`：Keychain 写入失败在配置验证、账号切换与退出链路中的传播。

`TestFactories.swift` 提供测试夹具，不单独定义 XCTestCase。

## Xcode 测试目标

`OpenWritingTests` target 已在 `OpenWriting.xcodeproj` 和 shared `OpenWriting` scheme 中配置完成，不要重新创建。

新增测试文件后，需要把文件加入 `OpenWritingTests` target，并运行：

```zsh
./scripts/verify-xctest-membership.sh
```

## 运行测试

OpenWriting 的测试入口以 Xcode project 为准；`Tests/Package.swift` 只保留为空 manifest，防止误把 app target 当成 SwiftPM library。不要用 `swift test` 判断本仓库测试状态。

在 Xcode 中：
- Product → Test (⌘U)
- 或使用 Test Navigator (⌘6)

在仓库根目录通过命令行运行：

```zsh
./scripts/run-hosted-xctest-guard.sh
./scripts/run-tests.sh
```

## 扩展测试覆盖

建议添加的测试：

### 高优先级
- `AppStateTests.swift` - AppState 方法测试（需模拟 ProjectFileStore）
- `AIWritingServiceTests.swift` - AI 服务测试（需 mock 网络）

### 中优先级
- `ChapterTreeRefreshTests.swift` - 章节树刷新逻辑测试
- `GenreTemplateEngineTests.swift` - 模板引擎测试

### 低优先级
- `StrandWeaveTrackerTests.swift` - 叙事线追踪测试
- `WritingMemoryBucketsTests.swift` - 写作记忆桶测试

## 测试最佳实践

1. **每个测试方法独立** - 使用 `setUp` 和 `tearDown`
2. **清晰的测试命名** - `testMethodName_Scenario_ExpectedResult`
3. **测试单一行为** - 一个测试方法只验证一件事
4. **使用断言消息** - 帮助调试失败的测试
5. **避免测试实现细节** - 专注于行为和结果
