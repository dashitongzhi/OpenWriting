# 测试设置指南

## 当前测试文件

已创建的测试文件位于 `Tests/OpenWritingTests/` 目录：

1. **NovelProjectTests.swift** - 小说项目模型的单元测试
   - NovelProject 创建和默认值测试
   - ChapterDraft 创建、字数统计、版本快照、排序
   - ChapterDraftMetadata 转换和排序
   - NovelVolume 创建和标签
   - ReferenceDocument 创建和分类推断
   - GlobalMemorySnapshot 空值、设置值、解析、格式化

2. **SearchTests.swift** - 搜索功能测试
   - 分词提取（去重、最小长度、最大数量）
   - 搜索评分算法
   - 搜索摘要生成

3. **ProjectFileStoreTests.swift** - 文件存储测试
   - 项目保存和加载（单项目、多项目）
   - 章节草稿保存和加载
   - 项目更新和删除
   - 作用域隔离测试
   - 章节版本历史
   - 边界情况（特殊字符、大文件内容）

4. **DomainModelsTests.swift** - 领域模型测试
   - NovelLength 标签和范围
   - ModelProvider 和 ConnectionStatus
   - ChapterDraftSaveResult
   - ReferenceMaterialCategory 推断
   - PersistedTimestampCodec 编解码
   - OutlineGenerationProfile 完成度

## 在 Xcode 中添加测试目标

### 方法 1: 通过 Xcode UI

1. 打开 `OpenWriting.xcodeproj`
2. File → New → Target
3. 选择 "macOS" → "AppKit Unit Testing Bundle"
4. Product Name: `OpenWritingTests`
5. 点击 Create
6. 删除自动生成的测试文件
7. 将 `Tests/OpenWritingTests/` 中的测试文件添加到目标

### 方法 2: 手动编辑 project.pbxproj

在 `PBXProject` 的 `targets` 数组中添加：
```
AD9EB9AC2F8676DB005D3EBC /* OpenWriting */ = {
    ...
};
AD9EB9XX2F8676DB005D3EBC /* OpenWritingTests */ = {
    isa = PBXNativeTarget;
    name = OpenWritingTests;
    productName = OpenWritingTests;
    productType = "com.apple.product-type.bundle.unit-test";
    buildPhases = (
        ...
    );
    dependencies = (
        AD9EB9AC2F8676DB005D3EBC /* OpenWriting */,
    );
};
```

## 运行测试

OpenWriting 的测试入口以 Xcode project 为准；`Tests/Package.swift` 只保留为空 manifest，防止误把 app target 当成 SwiftPM library。不要用 `swift test` 判断本仓库测试状态。

在 Xcode 中：
- Product → Test (⌘U)
- 或使用 Test Navigator (⌘6)

或通过命令行：
```bash
cd /Users/kral/Desktop/OpenWriting
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test \
  -project OpenWriting.xcodeproj \
  -scheme OpenWriting \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
```

## 扩展测试覆盖

建议添加的测试：

### 高优先级
- `AppStateTests.swift` - AppState 方法测试（需模拟 ProjectFileStore）
- `AIWritingServiceTests.swift` - AI 服务测试（需 mock 网络）
- `ProjectExportServiceTests.swift` - 导出服务测试

### 中优先级
- `ChapterTreeRefreshTests.swift` - 章节树刷新逻辑测试
- `GenreTemplateEngineTests.swift` - 模板引擎测试
- `ContextRankerTests.swift` - 上下文排序测试

### 低优先级
- `MemorySystemTests.swift` - 记忆系统测试
- `StrandWeaveTrackerTests.swift` - 叙事线追踪测试
- `WritingMemoryBucketsTests.swift` - 写作记忆桶测试

## 测试最佳实践

1. **每个测试方法独立** - 使用 `setUp` 和 `tearDown`
2. **清晰的测试命名** - `testMethodName_Scenario_ExpectedResult`
3. **测试单一行为** - 一个测试方法只验证一件事
4. **使用断言消息** - 帮助调试失败的测试
5. **避免测试实现细节** - 专注于行为和结果
