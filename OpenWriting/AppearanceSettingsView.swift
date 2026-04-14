import AppKit
import Observation
import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    static let storageKey = "appAppearance"

    case system
    case light
    case dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system:
            return "跟随系统"
        case .light:
            return "浅色"
        case .dark:
            return "深色"
        }
    }

    var symbolName: String {
        switch self {
        case .system:
            return "circle.lefthalf.filled"
        case .light:
            return "sun.max"
        case .dark:
            return "moon.fill"
        }
    }

    var description: String {
        switch self {
        case .system:
            return "OpenWriting 会跟随 macOS 当前的外观设置自动切换。"
        case .light:
            return "始终使用浅色外观，适合长时间阅读和排版。"
        case .dark:
            return "始终使用深色外观，适合夜间写作和低光环境。"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system:
            return nil
        case .light:
            return NSAppearance(named: .aqua)
        case .dark:
            return NSAppearance(named: .darkAqua)
        }
    }

    static func current(userDefaults: UserDefaults = .standard) -> AppAppearance {
        guard let rawValue = userDefaults.string(forKey: storageKey),
              let appearance = AppAppearance(rawValue: rawValue)
        else {
            return .system
        }

        return appearance
    }
}

struct AppearanceSettingsView: View {
    @Bindable var appState: AppState
    @AppStorage(AppAppearance.storageKey) private var appAppearanceRawValue = AppAppearance.system.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("OpenWriting 设置")
                .font(.title2.weight(.semibold))

            Form {
                Section("外观") {
                    Picker("显示模式", selection: appearanceBinding) {
                        ForEach(AppAppearance.allCases) { appearance in
                            Label(appearance.title, systemImage: appearance.symbolName)
                                .tag(appearance)
                        }
                    }
                    .pickerStyle(.segmented)

                    VStack(alignment: .leading, spacing: 10) {
                        Label(selectedAppearance.title, systemImage: selectedAppearance.symbolName)
                            .font(.headline)

                        Text(selectedAppearance.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }

                Section("模型连接") {
                    ModelConnectionSettingsForm(appState: appState)
                }

                Section("写作台显示") {
                    Toggle("显示缓存区", isOn: $appState.showWritingDeskCachePanel)
                        .toggleStyle(.switch)

                    Toggle("显示 AI 作家时间节点", isOn: $appState.showWritingDeskTimeline)
                        .toggleStyle(.switch)

                    Text("关闭后会隐藏对应模块，但写作台的正文编辑、导入、大纲和 AI 续写能力仍然保留。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            Text("外观和模型供应商都放在同一个原生设置窗口里，和常见 macOS 工具型应用的偏好结构保持一致。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 460, height: 620, alignment: .topLeading)
        .appAppearanceBridge()
    }

    private var selectedAppearance: AppAppearance {
        AppAppearance(rawValue: appAppearanceRawValue) ?? .system
    }

    private var appearanceBinding: Binding<AppAppearance> {
        Binding(
            get: { selectedAppearance },
            set: { appAppearanceRawValue = $0.rawValue }
        )
    }
}

private struct AppAppearanceBridgeModifier: ViewModifier {
    @AppStorage(AppAppearance.storageKey) private var appAppearanceRawValue = AppAppearance.system.rawValue

    func body(content: Content) -> some View {
        let appearance = AppAppearance(rawValue: appAppearanceRawValue) ?? .system

        content
            .preferredColorScheme(appearance.colorScheme)
            .background(
                WindowAppearanceSyncView(appearance: appearance)
            )
    }
}

private struct WindowAppearanceSyncView: NSViewRepresentable {
    let appearance: AppAppearance

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.isHidden = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let applyAppearance = {
            guard let window = nsView.window else { return }
            window.appearance = appearance.nsAppearance
        }

        if nsView.window == nil {
            DispatchQueue.main.async(execute: applyAppearance)
        } else {
            applyAppearance()
        }
    }
}

extension View {
    func appAppearanceBridge() -> some View {
        modifier(AppAppearanceBridgeModifier())
    }
}

struct ModelConnectionSettingsForm: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("接口类型", selection: $appState.selectedProvider) {
                ForEach(ModelProvider.allCases) { provider in
                    Text(provider.title).tag(provider)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 8) {
                Text("Base URL")
                    .font(.subheadline.weight(.semibold))

                TextField("https://api.openai.com/v1", text: $appState.baseURL)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("模型名称")
                    .font(.subheadline.weight(.semibold))

                TextField("gpt-4.1-mini", text: $appState.modelName)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("API Key")
                    .font(.subheadline.weight(.semibold))

                SecureField("sk-...", text: $appState.apiKey)
                    .textFieldStyle(.roundedBorder)
            }

            Toggle("启动时自动检查格式", isOn: $appState.autoValidateOnLaunch)
                .toggleStyle(.switch)

            HStack(alignment: .center, spacing: 12) {
                Button("验证配置") {
                    appState.validateConfiguration()
                }
                .buttonStyle(.borderedProminent)

                HStack(spacing: 8) {
                    Image(systemName: appState.connectionStatus.symbolName)
                        .foregroundStyle(statusColor)

                    Text(appState.validationMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Text("模型连接属于全局偏好；当前写作台已经可以直接调用 OpenAI 兼容接口续写当前章节。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }

    private var statusColor: Color {
        switch appState.connectionStatus {
        case .idle:
            return .secondary
        case .ready:
            return Color(red: 0.18, green: 0.56, blue: 0.42)
        case .needsAttention:
            return Color(red: 0.83, green: 0.45, blue: 0.20)
        }
    }
}
