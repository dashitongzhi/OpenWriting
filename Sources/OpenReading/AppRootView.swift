import SwiftUI

struct AppRootView: View {
    @State private var selectedItem: SidebarItem? = .home
    @State private var appState = AppState()

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailContent
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var sidebar: some View {
        List(selection: $selectedItem) {
            Section("工作台") {
                sidebarRows([.home, .projects, .outline])
            }

            Section("创作资源") {
                sidebarRows([.library, .prompts])
            }

            Section("系统") {
                sidebarRows([.models, .settings])
            }
        }
        .navigationTitle("OpenReading")
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            sidebarFooter
        }
    }

    @ViewBuilder
    private func sidebarRows(_ items: [SidebarItem]) -> some View {
        ForEach(items) { item in
            Label(item.title, systemImage: item.symbolName)
                .tag(item)
                .padding(.vertical, 3)
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selectedItem ?? .home {
        case .home:
            HomeDashboardView(appState: appState)
        case .models:
            ModelWorkspaceView(appState: appState)
        case .projects, .outline, .library, .prompts, .settings:
            PlaceholderWorkspaceView(item: selectedItem ?? .home, appState: appState)
        }
    }

    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()

            HStack(spacing: 10) {
                Image(systemName: appState.isConfigurationReady ? "bolt.horizontal.circle.fill" : "bolt.horizontal.circle")
                    .foregroundStyle(appState.isConfigurationReady ? Color.accentColor : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(appState.isConfigurationReady ? "模型配置已填写" : "模型配置待完善")
                        .font(.subheadline.weight(.semibold))

                    Text(appState.validationMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Text("macOS 写作工作台原型")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.regularMaterial)
    }
}

enum SidebarItem: String, CaseIterable, Identifiable {
    case home
    case projects
    case outline
    case library
    case prompts
    case models
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .home:
            return "首页"
        case .projects:
            return "项目空间"
        case .outline:
            return "章节树"
        case .library:
            return "素材库"
        case .prompts:
            return "提示工作流"
        case .models:
            return "模型连接"
        case .settings:
            return "应用设置"
        }
    }

    var symbolName: String {
        switch self {
        case .home:
            return "house"
        case .projects:
            return "square.grid.2x2"
        case .outline:
            return "list.bullet.rectangle.portrait"
        case .library:
            return "books.vertical"
        case .prompts:
            return "sparkles.rectangle.stack"
        case .models:
            return "network"
        case .settings:
            return "slider.horizontal.3"
        }
    }

    var summary: String {
        switch self {
        case .home:
            return "总览写作进度、模型配置和快速开始入口。"
        case .projects:
            return "这里会放项目列表、筛选器和最近打开的手稿。"
        case .outline:
            return "这里会放章节树、场景卡片和剧情推进视图。"
        case .library:
            return "这里会集中管理人物、地点、组织和世界观素材。"
        case .prompts:
            return "这里会编排设定补完、续写和润色等 AI 工作流。"
        case .models:
            return "这里会做供应商切换、凭证管理和连接测试。"
        case .settings:
            return "这里会放主题、同步、快捷键和本地存储策略。"
        }
    }
}
