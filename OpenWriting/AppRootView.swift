import AppKit
import AuthenticationServices
import Observation
import SwiftUI

struct AppRootView: View {
    @Bindable var appState: AppState
    let openSettings: () -> Void
    @State private var presentedSheet: AppRootSheet?
    @State private var accountPortalState: AccountPortalState

    init(appState: AppState, openSettings: @escaping () -> Void = {}) {
        self.appState = appState
        self.openSettings = openSettings
        _accountPortalState = State(initialValue: AccountPortalState(appState: appState))
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 244, max: 266)
        } detail: {
            detailContent
        }
        .navigationSplitViewStyle(.balanced)
        .modifier(WindowToolbarChromeModifier())
        .background(
            WindowChromeRefreshView(
                refreshToken: appState.selectedSidebarItem.rawValue
            )
        )
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .accountPortal:
                AccountPortalSheet(appState: appState, portalState: accountPortalState)
            }
        }
        .appAppearanceBridge()
    }

    private var sidebar: some View {
        List(selection: sidebarSelection) {
            Section {
                sidebarRows([.home, .projects, .writingDesk, .outline])
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            sidebarFooter
        }
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
        switch appState.selectedSidebarItem {
        case .home:
            HomeDashboardView(appState: appState, openSettings: openSettings)
        case .writingDesk:
            WritingDeskView(appState: appState, openSettings: openSettings)
        case .projects, .outline, .library, .prompts:
            PlaceholderWorkspaceView(item: appState.selectedSidebarItem, appState: appState, openSettings: openSettings)
        }
    }

    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()

            Button {
                presentedSheet = .accountPortal
            } label: {
                SidebarAccountButtonContent(
                    displayName: appState.accountDisplayName,
                    secondaryLabel: appState.accountSecondaryLabel,
                    syncTitle: appState.cloudSyncTitle,
                    syncSymbolName: appState.cloudSyncSymbolName,
                    isSignedIn: appState.isAccountSignedIn
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.regularMaterial)
    }
    private var sidebarSelection: Binding<SidebarItem?> {
        Binding(
            get: { appState.selectedSidebarItem },
            set: { appState.navigate(to: $0 ?? .home) }
        )
    }
}

private enum AppRootSheet: String, Identifiable {
    case accountPortal

    var id: String { rawValue }
}

@MainActor
@Observable
private final class AccountPortalState {
    let appState: AppState
    var isSigningIn = false
    var isRefreshingCloud = false
    var actionMessage = ""
    var errorMessage = ""

    var signInAvailability: NativeAppleServiceAvailability {
        NativeAppleAccountRuntime.signInWithAppleAvailability()
    }

    var iCloudCapabilityAvailability: NativeAppleServiceAvailability {
        NativeAppleAccountRuntime.iCloudEntitlementAvailability()
    }

    init(appState: AppState) {
        self.appState = appState
    }

    func configureAppleIDRequest(_ request: ASAuthorizationAppleIDRequest) {
        let availability = signInAvailability
        guard availability.isAvailable else {
            isSigningIn = false
            actionMessage = ""
            errorMessage = availability.message
            return
        }

        isSigningIn = true
        errorMessage = ""
        actionMessage = "正在请求 Apple 身份验证。"
        request.requestedScopes = [.fullName, .email]
    }

    func handleAuthorization(_ result: Result<ASAuthorization, Error>) {
        isSigningIn = false

        switch result {
        case let .success(authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                errorMessage = "没有拿到可用的 Apple ID 凭证。"
                return
            }

            let profile = AppleAccountProfile.from(credential: credential, fallback: appState.activeAccount)
            appState.bindAppleAccount(profile)
            errorMessage = ""
            actionMessage = "已连接 \(appState.accountDisplayName)。"
        case let .failure(error):
            actionMessage = ""
            errorMessage = "Apple ID 登录失败：\(error.localizedDescription)"
        }
    }

    func logout() {
        appState.logoutAccount()
        actionMessage = "已断开当前 Apple 账号，本机资料仍保留在设备上。"
        errorMessage = ""
    }

    func refreshFromICloud() {
        isRefreshingCloud = true
        actionMessage = "正在从 iCloud 拉取最新项目。"
        errorMessage = ""

        Task { @MainActor [weak self] in
            guard let self else { return }
            await appState.refreshICloudProjects()
            isRefreshingCloud = false
            actionMessage = appState.cloudSyncStatusMessage
        }
    }
}

private struct AccountPortalSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var appState: AppState
    @Bindable var portalState: AccountPortalState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                accountHeroCard

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        authenticationCard
                            .frame(width: 320)

                        syncOverviewCard
                    }

                    VStack(spacing: 16) {
                        authenticationCard
                        syncOverviewCard
                    }
                }

                HStack {
                    Spacer()

                    Button("完成") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
        }
        .frame(minWidth: 820, idealWidth: 920, minHeight: 560, idealHeight: 660)
    }

    private var accountHeroCard: some View {
        NativeAccountCard {
            HStack(alignment: .top, spacing: 16) {
                AccountAvatarView(
                    displayName: appState.accountDisplayName,
                    secondaryLabel: appState.accountSecondaryLabel,
                    isSignedIn: appState.isAccountSignedIn,
                    size: 70
                )

                VStack(alignment: .leading, spacing: 8) {
                    Label("账户中心", systemImage: "apple.logo")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(appState.accountDisplayName)
                        .font(.title2.weight(.semibold))

                    Text(appState.accountSecondaryLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("账户入口和同步方案现在都改为 Apple 原生路径，界面也按 macOS 系统应用的层级做了收敛。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                }

                Spacer(minLength: 16)

                VStack(alignment: .trailing, spacing: 10) {
                    AccountSyncPill(
                        title: appState.cloudSyncTitle,
                        symbolName: appState.cloudSyncSymbolName
                    )

                    if portalState.isSigningIn || portalState.isRefreshingCloud {
                        Label("正在处理", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            if !portalState.errorMessage.isEmpty {
                Label(portalState.errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if !portalState.actionMessage.isEmpty {
                Label(portalState.actionMessage, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(appState.accountStorageSummary + " " + appState.cloudSyncStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
            }
        }
    }

    private var authenticationCard: some View {
        NativeAccountCard {
            Text("Apple ID 登录")
                .font(.headline)

            Text("使用系统原生授权面板登录，不再跳转网页，也不再维护单独的邮箱入口。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(3)

            SignInWithAppleButton(.signIn) { request in
                portalState.configureAppleIDRequest(request)
            } onCompletion: { result in
                portalState.handleAuthorization(result)
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .disabled(!portalState.signInAvailability.isAvailable)

            if !portalState.signInAvailability.isAvailable {
                Label(portalState.signInAvailability.message, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
            }

            if appState.isAccountSignedIn {
                Button {
                    portalState.refreshFromICloud()
                } label: {
                    Label("从 iCloud 拉取最新项目", systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(portalState.isRefreshingCloud)

                Button {
                    portalState.logout()
                } label: {
                    Label("退出当前 Apple ID", systemImage: "rectangle.portrait.and.arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            Divider()

            Label("首次授权时，Apple 只会在当次返回姓名与邮箱。之后会继续使用本地保存的账户资料。", systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
        }
    }

    private var syncOverviewCard: some View {
        NativeAccountCard {
            Text("同步与资料")
                .font(.headline)

            Text("结构上参考 Apple Music 一类系统应用的账户页：顶部账户头部，下面是清晰分组的资料与状态卡片。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(3)

            VStack(alignment: .leading, spacing: 12) {
                AccountDetailRow(
                    title: "账户状态",
                    symbolName: "person.crop.circle",
                    value: appState.isAccountSignedIn ? "已连接 Apple ID" : "尚未登录"
                )

                AccountDetailRow(
                    title: "数据隔离",
                    symbolName: "person.2.crop.square.stack",
                    value: appState.isAccountSignedIn ? "按 Apple user ID 分桶保存" : "当前使用本机默认资料"
                )

                AccountDetailRow(
                    title: "同步目标",
                    symbolName: "icloud",
                    value: appState.cloudSyncTitle
                )

                AccountDetailRow(
                    title: "同步内容",
                    symbolName: "square.stack.3d.up",
                    value: "项目列表、当前项目、正文、大纲、章节存档与参考资料快照"
                )
            }

            Divider()

            Label(appState.cloudSyncStatusMessage, systemImage: appState.cloudSyncSymbolName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AccountSyncPill.tint(for: appState.cloudSyncSymbolName))

            if !portalState.iCloudCapabilityAvailability.isAvailable {
                Label(portalState.iCloudCapabilityAvailability.message, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
            }

            Text("如果当前构建还没有在宿主 target 中开启 Sign in with Apple 或 iCloud 容器能力，界面会回退为本机保存，但交互仍保持 Apple 原生样式。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
        }
    }
}

private struct SidebarAccountButtonContent: View {
    @Environment(\.colorScheme) private var colorScheme
    let displayName: String
    let secondaryLabel: String
    let syncTitle: String
    let syncSymbolName: String
    let isSignedIn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                AccountAvatarView(
                    displayName: displayName,
                    secondaryLabel: secondaryLabel,
                    isSignedIn: isSignedIn,
                    size: 42
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(displayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    Text(isSignedIn ? "Apple ID 与 iCloud" : "使用 Apple ID 登录")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 8) {
                Label(isSignedIn ? "Apple 账户" : "未连接", systemImage: isSignedIn ? "apple.logo" : "person.crop.circle.badge.plus")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                AccountSyncPill(title: syncTitle, symbolName: syncSymbolName)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(backgroundFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(borderColor)
        )
        .shadow(color: shadowColor, radius: 10, y: 4)
    }

    private var backgroundFill: LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                colors: [
                    Color(red: 0.14, green: 0.14, blue: 0.16).opacity(0.96),
                    Color(red: 0.10, green: 0.10, blue: 0.12).opacity(0.94)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        return LinearGradient(
            colors: [
                Color.white.opacity(0.82),
                Color.white.opacity(0.68)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.primary.opacity(0.08)
    }

    private var shadowColor: Color {
        Color.black.opacity(colorScheme == .dark ? 0.18 : 0.04)
    }
}

private struct NativeAccountCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(backgroundFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(borderColor)
        )
        .shadow(color: shadowColor, radius: 16, y: 8)
    }

    private var backgroundFill: LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                colors: [
                    Color(red: 0.13, green: 0.13, blue: 0.15).opacity(0.98),
                    Color(red: 0.09, green: 0.09, blue: 0.11).opacity(0.96)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        return LinearGradient(
            colors: [
                Color.white.opacity(0.86),
                Color.white.opacity(0.70)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.primary.opacity(0.08)
    }

    private var shadowColor: Color {
        Color.black.opacity(colorScheme == .dark ? 0.16 : 0.035)
    }
}

private struct AccountAvatarView: View {
    @Environment(\.colorScheme) private var colorScheme
    let displayName: String
    let secondaryLabel: String
    let isSignedIn: Bool
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(backgroundGradient)

            Circle()
                .strokeBorder(ringColor, lineWidth: 1)

            if isSignedIn {
                Text(monogram)
                    .font(.system(size: size * 0.34, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: size * 0.52, weight: .regular))
                    .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.68) : .secondary)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: Color.black.opacity(isSignedIn ? 0.08 : 0.03), radius: 8, y: 4)
    }

    private var backgroundGradient: LinearGradient {
        if isSignedIn {
            return LinearGradient(
                colors: [
                    Color(nsColor: .controlAccentColor).opacity(0.95),
                    Color(nsColor: .selectedControlColor).opacity(0.72)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        if colorScheme == .dark {
            return LinearGradient(
                colors: [
                    Color(red: 0.19, green: 0.19, blue: 0.23),
                    Color(red: 0.10, green: 0.10, blue: 0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        return LinearGradient(
            colors: [
                Color.primary.opacity(0.07),
                Color.primary.opacity(0.03)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var monogram: String {
        let resolved = preferredSource.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolved.isEmpty else { return "ID" }

        let separators = CharacterSet(charactersIn: " @._-")
        let components = resolved.components(separatedBy: separators).filter { !$0.isEmpty }

        if components.count >= 2 {
            return components.prefix(2)
                .compactMap { $0.first }
                .map { String($0).uppercased() }
                .joined()
        }

        return String(resolved.prefix(2)).uppercased()
    }

    private var preferredSource: String {
        let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDisplayName.isEmpty, trimmedDisplayName != "未登录", trimmedDisplayName != "Apple ID" {
            return trimmedDisplayName
        }

        let trimmedSecondary = secondaryLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedSecondary
    }

    private var ringColor: Color {
        if isSignedIn {
            return Color.white.opacity(colorScheme == .dark ? 0.24 : 0.34)
        }

        return colorScheme == .dark ? Color.white.opacity(0.10) : Color.white.opacity(0.18)
    }
}

private struct AccountSyncPill: View {
    let title: String
    let symbolName: String

    var body: some View {
        Label(title, systemImage: symbolName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Self.tint(for: symbolName))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(Self.tint(for: symbolName).opacity(0.12))
            )
    }

    static func tint(for symbolName: String) -> Color {
        if symbolName.contains("slash") {
            return .secondary
        }

        if symbolName.contains("triangle") || symbolName.contains("arrow") {
            return .orange
        }

        return Color(nsColor: .controlAccentColor)
    }
}

private struct AccountDetailRow: View {
    let title: String
    let symbolName: String
    let value: String

    var body: some View {
        LabeledContent {
            Text(value)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
        } label: {
            Label(title, systemImage: symbolName)
                .foregroundStyle(.primary)
        }
        .font(.subheadline)
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

private struct WindowToolbarChromeModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content
                .toolbar(removing: .title)
                .toolbarBackground(.hidden, for: .windowToolbar)
        } else {
            content
                .toolbarBackground(.hidden, for: .windowToolbar)
        }
    }
}

private struct WindowChromeRefreshView: NSViewRepresentable {
    let refreshToken: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.isHidden = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        _ = refreshToken

        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            if let controller = window.windowController as? MainWindowController {
                controller.refreshWindowChromeFromSwiftUI(for: window)
            } else {
                MainWindowController.applyWindowChrome(to: window)
                window.toolbar?.validateVisibleItems()
            }
        }
    }
}

enum SidebarItem: String, CaseIterable, Identifiable {
    case home
    case projects
    case writingDesk
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
        case .writingDesk:
            return "写作台"
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
        case .writingDesk:
            return "square.and.pencil"
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
            return "总览当前章节、模型配置和快速开始入口。"
        case .projects:
            return "这里会放项目列表、筛选器和最近打开的手稿。"
        case .writingDesk:
            return "这里会直接进入当前章节的正文创作与续写。"
        case .outline:
            return "这里会放章节树、场景卡片和剧情推进视图。"
        case .library:
            return "这里会集中管理人物、地点、组织和世界观素材。"
        case .prompts:
            return "这里会编排设定补完、续写和润色等 AI 工作流。"
        }
    }
}
