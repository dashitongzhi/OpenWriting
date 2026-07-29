import AppKit
import Foundation
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

enum AppAccentColorMode: String, CaseIterable, Identifiable {
    static let storageKey = "appAccentColorMode"

    case custom
    case system

    var id: Self { self }

    var title: String {
        switch self {
        case .custom:
            return "自定义"
        case .system:
            return "跟随系统"
        }
    }
}

@MainActor
enum AppAccentColorPreference {
    static let customColorStorageKey = "appAccentCustomColor"
    static let defaultCustomColorHex = "#0A84FF"

    static func resolvedColor(
        modeRawValue: String,
        customColorHex: String
    ) -> Color {
        let mode = AppAccentColorMode(rawValue: modeRawValue) ?? .custom
        switch mode {
        case .custom:
            return color(from: customColorHex)
        case .system:
            return Color(nsColor: .controlAccentColor)
        }
    }

    static func color(from rawValue: String) -> Color {
        let hex = normalizedHex(rawValue) ?? defaultCustomColorHex
        let value = UInt64(hex.dropFirst(), radix: 16) ?? 0x0A84FF
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    static func foregroundColor(on color: Color) -> Color {
        guard let components = sRGBComponents(from: color) else {
            return .white
        }
        return components.relativeLuminance > 0.179 ? .black : .white
    }

    static func accessibleInkColor(
        from color: Color,
        colorScheme: ColorScheme
    ) -> Color {
        // Text and icons can sit on accent-tinted surfaces up to 24% opacity.
        accessibleColor(
            from: color,
            colorScheme: colorScheme,
            darkTargetLuminance: 0.64,
            lightTargetLuminance: 0.06
        )
    }

    static func accessibleStrokeColor(
        from color: Color,
        colorScheme: ColorScheme
    ) -> Color {
        // Selected borders can share the same accent-tinted surface.
        accessibleColor(
            from: color,
            colorScheme: colorScheme,
            darkTargetLuminance: 0.33,
            lightTargetLuminance: 0.12
        )
    }

    private static func accessibleColor(
        from color: Color,
        colorScheme: ColorScheme,
        darkTargetLuminance: Double,
        lightTargetLuminance: Double
    ) -> Color {
        guard let source = sRGBComponents(from: color) else {
            return color
        }

        let targetLuminance = colorScheme == .dark
            ? darkTargetLuminance
            : lightTargetLuminance
        let alreadyReadable = colorScheme == .dark
            ? source.relativeLuminance >= targetLuminance
            : source.relativeLuminance <= targetLuminance
        guard !alreadyReadable else {
            return source.color
        }

        let endpoint = colorScheme == .dark
            ? SRGBComponents(red: 1, green: 1, blue: 1)
            : SRGBComponents(red: 0, green: 0, blue: 0)
        var lowerBound = 0.0
        var upperBound = 1.0

        for _ in 0..<18 {
            let amount = (lowerBound + upperBound) / 2
            let candidate = source.mixed(toward: endpoint, amount: amount)
            let meetsTarget = colorScheme == .dark
                ? candidate.relativeLuminance >= targetLuminance
                : candidate.relativeLuminance <= targetLuminance
            if meetsTarget {
                upperBound = amount
            } else {
                lowerBound = amount
            }
        }

        return source.mixed(toward: endpoint, amount: upperBound).color
    }

    static func contrastRatio(
        between first: Color,
        and second: Color
    ) -> Double? {
        guard let firstComponents = sRGBComponents(from: first),
              let secondComponents = sRGBComponents(from: second) else {
            return nil
        }
        let lighter = max(
            firstComponents.relativeLuminance,
            secondComponents.relativeLuminance
        )
        let darker = min(
            firstComponents.relativeLuminance,
            secondComponents.relativeLuminance
        )
        return (lighter + 0.05) / (darker + 0.05)
    }

    static func compositedColor(
        overlay: Color,
        opacity: Double,
        over background: Color
    ) -> Color? {
        guard let overlayComponents = sRGBComponents(from: overlay),
              let backgroundComponents = sRGBComponents(from: background)
        else {
            return nil
        }

        return backgroundComponents.mixed(
            toward: overlayComponents,
            amount: opacity
        ).color
    }

    static func hexString(from color: Color) -> String? {
        guard let resolvedColor = NSColor(color).usingColorSpace(.sRGB) else {
            return nil
        }
        let red = Int((resolvedColor.redComponent * 255).rounded())
        let green = Int((resolvedColor.greenComponent * 255).rounded())
        let blue = Int((resolvedColor.blueComponent * 255).rounded())
        return String(
            format: "#%02X%02X%02X",
            min(max(red, 0), 255),
            min(max(green, 0), 255),
            min(max(blue, 0), 255)
        )
    }

    static func normalizedHex(_ rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let hexadecimal = trimmed.hasPrefix("#")
            ? String(trimmed.dropFirst())
            : trimmed
        guard hexadecimal.count == 6,
              UInt64(hexadecimal, radix: 16) != nil else {
            return nil
        }
        return "#\(hexadecimal.uppercased())"
    }

    private static func sRGBComponents(
        from color: Color
    ) -> SRGBComponents? {
        guard let resolvedColor = NSColor(color).usingColorSpace(.sRGB) else {
            return nil
        }
        return SRGBComponents(
            red: min(max(resolvedColor.redComponent, 0), 1),
            green: min(max(resolvedColor.greenComponent, 0), 1),
            blue: min(max(resolvedColor.blueComponent, 0), 1)
        )
    }

    private struct SRGBComponents {
        let red: Double
        let green: Double
        let blue: Double

        var color: Color {
            Color(red: red, green: green, blue: blue)
        }

        var relativeLuminance: Double {
            0.2126 * Self.linearized(red)
                + 0.7152 * Self.linearized(green)
                + 0.0722 * Self.linearized(blue)
        }

        func mixed(
            toward endpoint: SRGBComponents,
            amount: Double
        ) -> SRGBComponents {
            let clampedAmount = min(max(amount, 0), 1)
            return SRGBComponents(
                red: red + (endpoint.red - red) * clampedAmount,
                green: green + (endpoint.green - green) * clampedAmount,
                blue: blue + (endpoint.blue - blue) * clampedAmount
            )
        }

        private static func linearized(_ component: Double) -> Double {
            component <= 0.04045
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }
    }
}

nonisolated private struct AppAccentForegroundColorKey: EnvironmentKey {
    static let defaultValue = Color.white
}

nonisolated private struct AppAccentInkColorKey: EnvironmentKey {
    static let defaultValue = Color(
        red: Double(0x0A) / 255,
        green: Double(0x84) / 255,
        blue: 1
    )
}

nonisolated private struct AppAccentStrokeColorKey: EnvironmentKey {
    static let defaultValue = Color(
        red: Double(0x0A) / 255,
        green: Double(0x84) / 255,
        blue: 1
    )
}

extension EnvironmentValues {
    nonisolated var appAccentForegroundColor: Color {
        get { self[AppAccentForegroundColorKey.self] }
        set { self[AppAccentForegroundColorKey.self] = newValue }
    }

    nonisolated var appAccentInkColor: Color {
        get { self[AppAccentInkColorKey.self] }
        set { self[AppAccentInkColorKey.self] = newValue }
    }

    nonisolated var appAccentStrokeColor: Color {
        get { self[AppAccentStrokeColorKey.self] }
        set { self[AppAccentStrokeColorKey.self] = newValue }
    }
}

struct AppAccentInkStyle: ShapeStyle {
    func resolve(in environment: EnvironmentValues) -> some ShapeStyle {
        environment.appAccentInkColor
    }
}

extension ShapeStyle where Self == AppAccentInkStyle {
    static var appAccentInk: AppAccentInkStyle {
        AppAccentInkStyle()
    }
}

struct AppearanceSettingsView: View {
    @Bindable var appState: AppState
    @AppStorage(AppAppearance.storageKey) private var appAppearanceRawValue = AppAppearance.system.rawValue
    @AppStorage(AppAccentColorMode.storageKey) private var accentColorModeRawValue =
        AppAccentColorMode.custom.rawValue
    @AppStorage(AppAccentColorPreference.customColorStorageKey) private var customAccentColorHex =
        AppAccentColorPreference.defaultCustomColorHex
    @State private var isHelpPresented = false

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

                    Picker("重点色", selection: accentColorModeBinding) {
                        ForEach(AppAccentColorMode.allCases) { mode in
                            Text(mode.title)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if selectedAccentColorMode == .custom {
                        ColorPicker(
                            "自定义重点色",
                            selection: customAccentColorBinding,
                            supportsOpacity: false
                        )

                        Button("恢复 Apple 蓝色") {
                            customAccentColorHex =
                                AppAccentColorPreference.defaultCustomColorHex
                        }
                        .buttonStyle(.link)
                    }

                    HStack(spacing: 10) {
                        Circle()
                            .fill(selectedAccentColor)
                            .frame(width: 14, height: 14)
                            .accessibilityHidden(true)

                        Text(
                            selectedAccentColorMode == .custom
                                ? "重点色会立即应用到按钮、选择状态和写作台强调元素。"
                                : "重点色会跟随 macOS“外观”设置。"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                Section("模型连接") {
                    ModelConnectionSettingsForm(appState: appState)
                }

                Section("隐私与数据") {
                    Toggle("允许 AI 功能发送写作上下文", isOn: $appState.hasAcceptedAIDataTransfer)
                        .toggleStyle(.switch)

                    VStack(alignment: .leading, spacing: 6) {
                        Label("AI 续写、润色、审查和记忆整理会把正文片段、设定、大纲、全局记忆与相关参考文本发送到所选模型服务。", systemImage: "lock.shield")
                            .font(.subheadline)

                        Text("关闭后，本机写作、项目管理和导出仍可使用，但所有需要模型的功能都会暂停。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }

                Section("写作台显示") {
                    Toggle("专注写作模式", isOn: $appState.isWritingFocusModeEnabled)
                        .toggleStyle(.switch)

                    Toggle("显示缓存区", isOn: $appState.showWritingDeskCachePanel)
                        .toggleStyle(.switch)

                    Toggle("显示 AI 作家时间节点", isOn: $appState.showWritingDeskTimeline)
                        .toggleStyle(.switch)

                    Text("关闭后会隐藏对应模块，但写作台的正文编辑、导入、大纲和 AI 续写能力仍然保留。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("正文排版") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("字号")
                            Spacer()
                            Text("\(Int(appState.draftEditorFontSize)) pt")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }

                        Slider(value: $appState.draftEditorFontSize, in: 13...24, step: 1)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("行距")
                            Spacer()
                            Text("\(Int(appState.draftEditorLineSpacing))")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }

                        Slider(value: $appState.draftEditorLineSpacing, in: 2...14, step: 1)
                    }

                    Text("排版设置会立即应用到写作台正文编辑器，不影响项目正文内容。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("帮助") {
                    Button {
                        isHelpPresented = true
                    } label: {
                        Label("打开 OpenWriting 使用手册", systemImage: "questionmark.circle")
                    }
                    .buttonStyle(.bordered)

                    Text("覆盖快速入门、AI 数据使用、记忆系统、质量审查、章节保存和导出。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

        }
        .padding(24)
        .frame(
            minWidth: 420,
            idealWidth: 520,
            maxWidth: 680,
            minHeight: 500,
            idealHeight: 620,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .appAppearanceBridge()
        .sheet(isPresented: $isHelpPresented) {
            OpenWritingHelpView()
                .frame(minWidth: 560, idealWidth: 680, minHeight: 560, idealHeight: 720)
        }
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

    private var selectedAccentColorMode: AppAccentColorMode {
        AppAccentColorMode(rawValue: accentColorModeRawValue) ?? .custom
    }

    private var selectedAccentColor: Color {
        AppAccentColorPreference.resolvedColor(
            modeRawValue: accentColorModeRawValue,
            customColorHex: customAccentColorHex
        )
    }

    private var accentColorModeBinding: Binding<AppAccentColorMode> {
        Binding(
            get: { selectedAccentColorMode },
            set: { accentColorModeRawValue = $0.rawValue }
        )
    }

    private var customAccentColorBinding: Binding<Color> {
        Binding(
            get: {
                AppAccentColorPreference.color(from: customAccentColorHex)
            },
            set: { color in
                guard let hex =
                        AppAccentColorPreference.hexString(from: color) else {
                    return
                }
                customAccentColorHex = hex
            }
        )
    }
}

private struct AppAppearanceBridgeModifier: ViewModifier {
    @Environment(\.colorScheme) private var inheritedColorScheme
    @AppStorage(AppAppearance.storageKey) private var appAppearanceRawValue = AppAppearance.system.rawValue
    @AppStorage(AppAccentColorMode.storageKey) private var accentColorModeRawValue =
        AppAccentColorMode.custom.rawValue
    @AppStorage(AppAccentColorPreference.customColorStorageKey) private var customAccentColorHex =
        AppAccentColorPreference.defaultCustomColorHex

    func body(content: Content) -> some View {
        let appearance = AppAppearance(rawValue: appAppearanceRawValue) ?? .system
        let accentColor = AppAccentColorPreference.resolvedColor(
            modeRawValue: accentColorModeRawValue,
            customColorHex: customAccentColorHex
        )
        let effectiveColorScheme =
            appearance.colorScheme ?? inheritedColorScheme
        let accentForegroundColor =
            AppAccentColorPreference.foregroundColor(on: accentColor)
        let accentInkColor =
            AppAccentColorPreference.accessibleInkColor(
                from: accentColor,
                colorScheme: effectiveColorScheme
            )
        let accentStrokeColor =
            AppAccentColorPreference.accessibleStrokeColor(
                from: accentColor,
                colorScheme: effectiveColorScheme
            )

        content
            .environment(
                \.appAccentForegroundColor,
                accentForegroundColor
            )
            .environment(\.appAccentInkColor, accentInkColor)
            .environment(\.appAccentStrokeColor, accentStrokeColor)
            .tint(accentColor)
            .accentColor(accentColor)
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
        if nsView.window == nil {
            DispatchQueue.main.async { [weak nsView] in
                guard let window = nsView?.window else { return }
                window.appearance = appearance.nsAppearance
            }
        } else {
            nsView.window?.appearance = appearance.nsAppearance
        }
    }
}

private struct OpenWritingHelpView: View {
    private let sections: [(title: String, symbol: String, body: String)] = [
        (
            "快速开始",
            "sparkle.magnifyingglass",
            "先建立项目，补齐简介、大纲、当前章节目标和字数要求。正文区可以直接写作；AI 作家区适合生成候选稿、重写、润色和拟标题。"
        ),
        (
            "AI 数据使用",
            "lock.shield",
            "启用 AI 功能后，章节正文片段、设定、大纲、全局记忆、参考文本和审查上下文会发送给当前选择的模型服务。关闭设置里的数据授权后，模型相关功能会暂停，本地写作和导出仍可使用。"
        ),
        (
            "长篇记忆",
            "brain.head.profile",
            "全局记忆、章节树、伏笔和 Strand Weave 用来帮助长篇保持连续性。保存章节后，系统会刷新近端缓存，并可继续整理跨章节记忆。"
        ),
        (
            "质量审查",
            "checklist",
            "章节审查会检查情节推进、人物一致性、伏笔、节奏和 AI 味。阻断项应先修复，再接受候选稿或推进下一章。"
        ),
        (
            "导出与备份",
            "square.and.arrow.up",
            "项目可以导出为备份、Markdown、DOCX 和 EPUB。长篇项目导出前建议先保存当前章节，并确认章节目录顺序。"
        )
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("OpenWriting 使用手册", systemImage: "book.closed")
                    .font(.title2.weight(.semibold))

                Spacer()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(sections, id: \.title) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            Label(section.title, systemImage: section.symbol)
                                .font(.headline)

                            Text(section.body)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if section.title != sections.last?.title {
                            Divider()
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(24)
    }
}

extension View {
    func appAppearanceBridge() -> some View {
        modifier(AppAppearanceBridgeModifier())
    }
}

struct ModelConnectionSettingsForm: View {
    @Environment(\.appAccentInkColor) private var accentInkColor
    @Bindable var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("模型选择", selection: $appState.selectedProvider) {
                ForEach(ModelProvider.visibleCases) { provider in
                    Text(provider.title).tag(provider)
                }
            }
            .pickerStyle(.segmented)

            if appState.selectedProvider != .openAICompatible {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Base URL")
                        .font(.subheadline.weight(.semibold))

                    TextField(appState.selectedProvider.baseURLPlaceholder, text: $appState.baseURL)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("模型 ID")
                        .font(.subheadline.weight(.semibold))

                    TextField(appState.selectedProvider.modelPlaceholder, text: $appState.modelName)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("API Key")
                        .font(.subheadline.weight(.semibold))

                    SecureField(appState.selectedProvider.keyPlaceholder, text: $appState.apiKey)
                        .textFieldStyle(.roundedBorder)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Label("OpenWriting 提供模型由服务器托管", systemImage: "checkmark.seal")
                        .font(.subheadline.weight(.semibold))

                    Text("客户端不显示模型 ID、Base URL 或 API Key，也不会保存 OpenAI API Key。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            Toggle("启动时自动检查格式", isOn: $appState.autoValidateOnLaunch)
                .toggleStyle(.switch)

            HStack(alignment: .center, spacing: 12) {
                Button("测试连接") {
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

            if appState.selectedProvider != .openAICompatible {
                Text("自定义 OpenAI 使用 /v1/chat/completions 格式：Base URL 通常以 /v1 结尾，填写模型 ID 与 API Key；API Key 单独存放在系统 Keychain。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("OpenWriting 会通过平台托管服务完成模型调用；高级用户可切换到自定义后手动填写自己的服务。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    private var statusColor: Color {
        switch appState.connectionStatus {
        case .idle:
            return .secondary
        case .checking:
            return accentInkColor
        case .ready:
            return Color(red: 0.18, green: 0.56, blue: 0.42)
        case .needsAttention:
            return Color(red: 0.83, green: 0.45, blue: 0.20)
        }
    }
}
