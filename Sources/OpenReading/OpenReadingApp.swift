import SwiftUI

@main
struct OpenReadingApp: App {
    @State private var appState = AppState()
    @NSApplicationDelegateAdaptor(OpenReadingAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            AppRootView(appState: appState)
        }
        .defaultSize(width: 1_440, height: 900)
        .windowToolbarStyle(.unified(showsTitle: false))

        Settings {
            AppearanceSettingsView(appState: appState)
        }
    }
}

@MainActor
final class OpenReadingAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }
}
