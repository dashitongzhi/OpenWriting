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
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        AppRuntime.shared.windowCoordinator.showMainWindow()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            NSApp.activate(ignoringOtherApps: true)
            AppRuntime.shared.windowCoordinator.showMainWindow()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            AppRuntime.shared.windowCoordinator.showMainWindow()
        }

        return true
    }
}
