import AppKit
import SwiftUI

@MainActor
final class AppRuntime {
    static let shared = AppRuntime()

    let appState: AppState
    let windowCoordinator: AppWindowCoordinator

    private init() {
        let appState = AppState()
        self.appState = appState
        self.windowCoordinator = AppWindowCoordinator(appState: appState)
    }
}

@MainActor
final class AppWindowCoordinator {
    private let appState: AppState
    private var mainWindowController: MainWindowController?
    private var settingsWindowController: SettingsWindowController?

    init(appState: AppState) {
        self.appState = appState
    }

    func showMainWindow() {
        let controller = mainWindowController ?? makeMainWindowController()
        mainWindowController = controller

        controller.showWindow(nil)

        guard let window = controller.window else { return }
        bringWindowToFront(window)
    }

    func showSettingsWindow() {
        let controller = settingsWindowController ?? makeSettingsWindowController()
        settingsWindowController = controller

        controller.showWindow(nil)

        guard let window = controller.window else { return }
        bringWindowToFront(window)
    }

    private func makeMainWindowController() -> MainWindowController {
        MainWindowController(
            appState: appState,
            openSettings: { [weak self] in
                self?.showSettingsWindow()
            }
        )
    }

    private func makeSettingsWindowController() -> SettingsWindowController {
        SettingsWindowController(appState: appState)
    }

    private func bringWindowToFront(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.deminiaturize(nil)
        window.makeKeyAndOrderFront(nil)
    }
}

@MainActor
final class MainWindowController: NSWindowController {
    private let openSettings: () -> Void

    init(appState: AppState, openSettings: @escaping () -> Void) {
        self.openSettings = openSettings

        let rootView = AppRootView(appState: appState, openSettings: openSettings)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_440, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.contentViewController = hostingController
        super.init(window: window)
        configureWindow(window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func configureWindow(_ window: NSWindow) {
        window.title = "OpenReading"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.setFrameAutosaveName("OpenReading.MainWindow")
        window.minSize = NSSize(width: 1_180, height: 760)
        window.center()
    }
}

@MainActor
final class SettingsWindowController: NSWindowController {
    init(appState: AppState) {
        let rootView = AppearanceSettingsView(appState: appState)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 430),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        window.contentViewController = hostingController
        super.init(window: window)
        configureWindow(window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func configureWindow(_ window: NSWindow) {
        window.title = "设置"
        window.titleVisibility = .visible
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 460, height: 430))
        window.center()
    }
}
