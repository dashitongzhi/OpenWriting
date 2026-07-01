import SwiftUI

@main
struct OpenWritingApp: App {
    @NSApplicationDelegateAdaptor(OpenWritingAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("设置...") {
                    AppRuntime.shared.windowCoordinator.showSettingsWindow()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

@MainActor
final class OpenWritingAppDelegate: NSObject, NSApplicationDelegate {
    private static var isRunningUnitTests: Bool {
        let environment = ProcessInfo.processInfo.environment

        return environment["OPENWRITING_XCTEST"] == "1"
            || environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || Bundle.allBundles.contains { $0.bundlePath.hasSuffix(".xctest") }
            || NSClassFromString("XCTest.XCTestCase") != nil
            || NSClassFromString("XCTestCase") != nil
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningUnitTests else {
            return
        }

        NSApp.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningUnitTests else { return }

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
        guard !Self.isRunningUnitTests else { return false }

        if !flag {
            AppRuntime.shared.windowCoordinator.showMainWindow()
        }

        return true
    }
}
