import SwiftUI

@main
struct OpenReadingApp: App {
    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
        .defaultSize(width: 1_440, height: 900)
        .windowToolbarStyle(.unified(showsTitle: false))

        Settings {
            SettingsPlaceholderView()
        }
    }
}

private struct SettingsPlaceholderView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("OpenReading 设置")
                .font(.title2.weight(.semibold))

            Text("当前阶段先完成首页原型。后续这里会接入模型供应商管理、本地缓存、主题与同步设置。")
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 420, height: 220, alignment: .topLeading)
    }
}
