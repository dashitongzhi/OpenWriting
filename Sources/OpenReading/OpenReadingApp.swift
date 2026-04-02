import SwiftUI

@main
struct OpenReadingApp: App {
    @NSApplicationDelegateAdaptor(OpenReadingAppDelegate.self) private var appDelegate
    private let runtime = AppRuntime.shared

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("设置...") {
                    runtime.windowCoordinator.showSettingsWindow()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

@MainActor
final class OpenReadingAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppRuntime.shared.windowCoordinator.showMainWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            AppRuntime.shared.windowCoordinator.showMainWindow()
        }

        return true
    }
}
