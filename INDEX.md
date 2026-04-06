# OpenReading Index

最后更新：2026-04-06

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
| `Sources/OpenReading/OpenReadingApp.swift` | 应用入口 | `YES` | 启动 AppKit 窗口协调器，并把偏好设置菜单交给原生设置窗口；当前也会在应用启动时立即前置，并在首帧后再补一次延迟激活，尽量确保界面直接弹到桌面 |
| `Sources/OpenReading/AppWindowCoordinator.swift` | AppKit 窗口协调器 | `YES` | 直接管理主窗口、设置窗口、首帧即生效并通过跟踪分隔线贴近侧边栏右上边框的原生工具栏按钮、透明标题栏样式、透明窗口背景、切页与全屏切换后的窗口 chrome 兜底刷新、工具栏 delegate/配置重挂、更强的前置聚焦、系统全屏能力，以及向根视图注入打开设置窗口的动作；当前也会在窗口显示后追加两次延迟前置，减少“进程已启动但界面没弹到前台”的情况 |
| `Sources/OpenReading/AppRootView.swift` | 根视图、侧边栏与主内容布局 | `YES` | 负责 SwiftUI 内容布局、更紧凑的系统风格侧边栏，并让侧边栏选中态与共享 `AppState` 导航状态保持一致，同时把打开设置动作传到首页和工作区页面；当前也已把 `写作台` 接入侧边栏一级入口 |
| `Sources/OpenReading/AppState.swift` | 应用状态与示例数据 | `YES` | 包含模型配置、本地校验、首页展示数据、当前创作书籍摘要的来源数据，以及每次启动稳定随机的名言种子；当前还负责首页动作路由、项目空间定位、高亮选中、活动项目持久化，以及用 `UserDefaults + Keychain` 保存模型连接设置，并把项目数据统一改为“当前创作章节 + 已创作章节数”口径，同时为每个项目保存本章目标、正文草稿、大纲、手动参考文本、特殊要求、字数设定、连续性笔记和参考文档元信息；写作台里“显示缓存区 / 显示 AI 时间节点”两项也由这里持久化 |
| `Sources/OpenReading/HomeDashboardView.swift` | 首页与主内容组件 | `YES` | 包含首页、模型状态摘要、顶部主视觉滚动淡出效果、分屏式工作区布局、深浅色自适应视觉主题、玻璃拟态卡片、当前创作书籍信息卡、栏目专属写作工作卡、非首页顶部双栏布局、占位工作区和共用卡片，并为非首页首卡加入写作引句区、统一名言展示、全站主内容区顶部位置上移及下拉后的顶部停靠回弹修正；当前非首页工作区的标题双卡已恢复为统一的等高样式，`项目空间 / 章节树 / 素材库 / 提示工作流` 都继续显示左侧名言首卡，并与右侧工作卡保持上下同时对齐，同时也收紧了这组标题双卡的固定高度与左卡内部留白，减少顶部大块空白；首页四张主卡已接通可用动作，最近项目可直达项目空间对应条目，项目空间页也补了可滚动定位和高亮的项目列表，同时把“新建项目”改成原生命名弹窗、移除了所有进度百分比展示，并让“继续上次写作”与项目空间内入口都可进入写作台 |
| `Sources/OpenReading/WritingDeskView.swift` | 写作台页面 | `YES` | 提供重做后的原生长篇写作工作台：已删除顶部标题名言卡，正文区改为“上排大纲设定 / 参考文本 / 特殊要求三卡横排，下排草稿箱 / AI 作家双栏对半”的布局；其中字数设定并入特殊要求卡，继续支持键盘编辑、导入大纲、导入参考文本、AI 续写、AI 润色、手动保存、自动滚动锁定，以及按设置项显示或隐藏缓存区和 AI 时间节点模块；写作台由侧边栏、项目空间和首页“继续上次写作”共享进入 |
| `Sources/OpenReading/AIWritingService.swift` | AI 写作服务 | `YES` | 封装 OpenAI 兼容 `chat/completions` 调用；当前已支持基于项目摘要、大纲、连续性笔记、手动参考文本、导入参考文档、特殊要求、字数设定和正文尾段的长篇续写提示词，并新增面向当前草稿的润色能力 |
| `Sources/OpenReading/LiteraryQuoteLibrary.swift` | 文学名言库加载与随机选择 | `YES` | 从本地 TSV 资源加载 500 条中文文学名言，按页面和启动种子稳定选择展示内容，并在加载时统一转为简体中文、隐藏纯英文出处；当前也兼容从原生 app 的 `Contents/Resources` 与开发期构建目录两种位置读取资源 |
| `Sources/OpenReading/AppearanceSettingsView.swift` | 设置视图与主题模式定义 | `YES` | 提供跟随系统、浅色、深色三种原生外观模式，并承接模型连接设置；当前也包含写作台显示偏好，用于控制缓存区与 AI 作家时间节点模块是否显示 |
| `Sources/OpenReading/Resources/LiteraryQuotes.zh-Hans.tsv` | 中文文学名言资源 | `YES` | 收录 500 条中文文学名言，用于非首页首卡的随机写作引句展示 |
| `Scripts/open-openreading-app.sh` | 本地构建并准备可启动 app bundle 的脚本 | `YES` | 使用 Xcode toolchain 与工程内缓存目录完成 `swift build --disable-sandbox`，再以兼容 `zsh` 的方式包装并 ad-hoc 签名本地 `.app`；资源放回标准的 `Contents/Resources`，并把真正的 `OpenReading` Mach-O 可执行文件放进 `Contents/MacOS`；最终 bundle 会被放到非隐藏的 `/tmp/OpenReading-preview`，脚本本身只负责构建并输出 app 路径，真正启动要由干净进程里的 plain `open` 来完成，绕开 `.build` 路径和构建态环境变量导致的 LaunchServices 打开失败 |
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
