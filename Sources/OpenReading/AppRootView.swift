import Observation
import SwiftUI

struct AppRootView: View {
    @AppStorage("appAppearance") private var appAppearanceRawValue = AppAppearance.system.rawValue
    @Bindable var appState: AppState
    let openSettings: () -> Void
    @State private var selectedItem: SidebarItem? = .home

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 250, ideal: 286, max: 332)
        } detail: {
            detailContent
        }
        .navigationSplitViewStyle(.balanced)
        .task(id: appAppearanceRawValue) {
            AppAppearance.apply(selectedAppearance)
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            sidebarTopBar

            List(selection: $selectedItem) {
                Section {
                    sidebarRows([.home, .projects, .outline])
                } header: {
                    SidebarSectionHeader(title: "工作台")
                }

                Section {
                    sidebarRows([.library, .prompts])
                } header: {
                    SidebarSectionHeader(title: "创作资源")
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(.clear)

            sidebarFooter
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .underPageBackgroundColor).opacity(0.94),
                    Color(nsColor: .windowBackgroundColor)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var sidebarTopBar: some View {
        HStack {
            Spacer()

            Button(action: openSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .help("打开设置")
        }
        .padding(.top, 14)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func sidebarRows(_ items: [SidebarItem]) -> some View {
        ForEach(items) { item in
            Label {
                Text(item.title)
                    .font(.system(size: 17, weight: .semibold))
            } icon: {
                Image(systemName: item.symbolName)
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 24)
            }
                .tag(item)
                .padding(.vertical, 8)
                .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
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
}

private struct SidebarSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(nil)
            .padding(.top, 10)
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
