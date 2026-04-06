# OpenReading Index

最后更新：2026-04-05

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
| `Sources/OpenReading/OpenReadingApp.swift` | 应用入口 | `YES` | 启动 AppKit 窗口协调器，并把偏好设置菜单交给原生设置窗口 |
| `Sources/OpenReading/AppWindowCoordinator.swift` | AppKit 窗口协调器 | `YES` | 直接管理主窗口、设置窗口、首帧即生效并通过跟踪分隔线贴近侧边栏右上边框的原生工具栏按钮、透明标题栏样式、透明窗口背景、切页与全屏切换后的窗口 chrome 兜底刷新、工具栏 delegate/配置重挂、前置聚焦与系统全屏能力 |
| `Sources/OpenReading/AppRootView.swift` | 根视图、侧边栏与主内容布局 | `YES` | 负责 SwiftUI 内容布局、更紧凑的系统风格侧边栏，以及隐藏窗口工具栏标题/背景并在页面切换时请求刷新原生窗口样式 |
| `Sources/OpenReading/AppState.swift` | 应用状态与示例数据 | `YES` | 包含模型配置、本地校验、首页展示数据、当前创作书籍摘要的来源数据，以及每次启动稳定随机的名言种子 |
| `Sources/OpenReading/HomeDashboardView.swift` | 首页与主内容组件 | `YES` | 包含首页、模型状态摘要、顶部主视觉滚动淡出效果、分屏式工作区布局、深浅色自适应视觉主题、玻璃拟态卡片、当前创作书籍信息卡、栏目专属写作工作卡、非首页顶部双栏对齐布局、占位工作区和共用卡片，并为非首页首卡加入写作引句区、统一名言展示、全站主内容区顶部位置上移及下拉后的顶部停靠回弹修正；当前首页已改为四张加长主卡、移出模型连接卡，并统一为同一固定高度以保证四卡尺寸一致 |
| `Sources/OpenReading/LiteraryQuoteLibrary.swift` | 文学名言库加载与随机选择 | `YES` | 从本地 TSV 资源加载 500 条中文文学名言，按页面和启动种子稳定选择展示内容，并在加载时统一转为简体中文、隐藏纯英文出处 |
| `Sources/OpenReading/AppearanceSettingsView.swift` | 设置视图与主题模式定义 | `YES` | 提供跟随系统、浅色、深色三种原生外观模式，并承接模型连接设置 |
| `Sources/OpenReading/Resources/LiteraryQuotes.zh-Hans.tsv` | 中文文学名言资源 | `YES` | 收录 500 条中文文学名言，用于非首页首卡的随机写作引句展示 |
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
