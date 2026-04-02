# OpenReading Index

最后更新：2026-04-02

## 维护规则

- 每次新增、删除或重命名项目文件时，都要同步更新本文件。
- 每次修改现有文件时，如果它的职责、位置或 Git 策略发生变化，也要同步更新本文件。
- `Git` 列说明：
  - `YES`：建议纳入 Git 版本管理。
  - `NO`：不应纳入 Git，通常是生成物、缓存或仓库内部数据。
  - `OPTIONAL`：按团队约定决定，当前默认不新增此类条目。

## 当前索引

| 路径 | 作用 | Git | 备注 |
| --- | --- | --- | --- |
| `Package.swift` | Swift Package 清单 | `YES` | 定义 macOS 可执行应用与平台版本 |
| `Sources/OpenReading/OpenReadingApp.swift` | 应用入口 | `YES` | 持有全局应用状态，配置窗口激活与原生 `Settings` 场景 |
| `Sources/OpenReading/AppRootView.swift` | 根视图、侧边栏、工具栏与主窗口行为 | `YES` | 管理工作区入口，保留当前设置按钮布局，并隐藏窗口工具栏背景以避免白色长条 |
| `Sources/OpenReading/AppState.swift` | 应用状态与示例数据 | `YES` | 包含模型配置、本地校验和首页展示数据 |
| `Sources/OpenReading/HomeDashboardView.swift` | 首页与主内容组件 | `YES` | 包含首页、模型状态摘要、顶部主视觉滚动淡出效果、占位工作区和共用卡片 |
| `Sources/OpenReading/AppearanceSettingsView.swift` | 设置视图与主题模式定义 | `YES` | 提供跟随系统、浅色、深色三种原生外观模式，并承接模型连接设置 |
| `.vscode/launch.json` | 调试启动配置 | `YES` | 本地 Swift 调试预设，可随工程共享 |
| `.gitignore` | Git 忽略规则 | `YES` | 忽略构建产物和本地缓存 |
| `INDEX.md` | 项目索引文件 | `YES` | 后续每次改动都要同步更新 |
| `.build/` | SwiftPM 构建输出 | `NO` | 本地生成目录，不应提交 |
| `.swiftpm/` | SwiftPM 本地状态 | `NO` | 本地依赖与工作区状态，不应提交 |
| `.git/` | Git 仓库元数据 | `NO` | Git 内部目录，绝不纳入版本管理 |

## 当前 Git 约定

- 源码、工程清单、共享调试配置、文档索引应进入 Git。
- 构建输出、缓存目录、仓库内部元数据不应进入 Git。
- 如果后面新增资源目录、测试目录或网络层文件，需要把它们补进上面的表格。
