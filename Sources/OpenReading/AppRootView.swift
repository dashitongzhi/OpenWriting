import Observation
import SwiftUI
import AppKit

struct AppRootView: View {
    @AppStorage("appAppearance") private var appAppearanceRawValue = AppAppearance.system.rawValue
    @Bindable var appState: AppState
    @State private var selectedItem: SidebarItem? = .home
    @State private var didConfigureWindow = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailContent
        }
        .navigationSplitViewStyle(.balanced)
        .background {
            WindowAccessor { window in
                configureMainWindowIfNeeded(window)
            }
        }
        .toolbar {
            if #available(macOS 26.0, *) {
                ToolbarSpacer(.flexible, placement: .primaryAction)
            }

            ToolbarItem(placement: .primaryAction) {
                SettingsLink {
                    Label("设置", systemImage: "gearshape")
                }
                .labelStyle(.iconOnly)
                .help("打开设置")
            }
        }
        .toolbarBackground(.hidden, for: .windowToolbar)
        .task(id: appAppearanceRawValue) {
            AppAppearance.apply(selectedAppearance)
        }
    }

    private var sidebar: some View {
        List(selection: $selectedItem) {
            Section("工作台") {
                sidebarRows([.home, .projects, .outline])
            }

            Section("创作资源") {
                sidebarRows([.library, .prompts])
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
        case .projects, .outline, .library, .prompts:
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

    private var selectedAppearance: AppAppearance {
        AppAppearance(rawValue: appAppearanceRawValue) ?? .system
    }
    @MainActor
    private func configureMainWindowIfNeeded(_ window: NSWindow) {
        guard !didConfigureWindow else { return }
        didConfigureWindow = true

        window.collectionBehavior.formUnion([.fullScreenPrimary, .fullScreenAllowsTiling])
        window.isReleasedWhenClosed = false

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}

private struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()

        DispatchQueue.main.async {
            if let window = view.window {
                onResolve(window)
            }
        }

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                onResolve(window)
            }
        }
    }
}

enum SidebarItem: String, CaseIterable, Identifiable {
    case home
    case projects
    case outline
    case library
    case prompts

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
        }
    }
}
