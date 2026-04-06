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
        stabilizeWindowPresentation(window)
    }

    func showSettingsWindow() {
        let controller = settingsWindowController ?? makeSettingsWindowController()
        settingsWindowController = controller

        controller.showWindow(nil)

        guard let window = controller.window else { return }
        bringWindowToFront(window)
        stabilizeWindowPresentation(window)
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
        NSApp.setActivationPolicy(.regular)
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.deminiaturize(nil)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
    }

    private func stabilizeWindowPresentation(_ window: NSWindow) {
        for delay in [0.18, 0.75] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak window] in
                guard let self, let window else { return }
                self.bringWindowToFront(window)
            }
        }
    }
}

@MainActor
final class MainWindowController: NSWindowController, NSToolbarDelegate, NSWindowDelegate {
    private static let toolbarIdentifier = NSToolbar.Identifier("OpenReading.MainToolbar")
    private let openSettings: () -> Void
    private weak var observedSplitView: NSSplitView?
    private var splitViewResizeObserver: NSObjectProtocol?
    private var pendingToolbarRefreshes: [DispatchWorkItem] = []

    init(appState: AppState, openSettings: @escaping () -> Void) {
        self.openSettings = openSettings

        let rootView = AppRootView(appState: appState, openSettings: openSettings)
        let hostingController = MainWindowHostingController(rootView: rootView)
        _ = hostingController.view
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
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

    @objc
    private func openSettingsWindow() {
        openSettings()
    }

    @objc
    private func toggleSidebarFromToolbar() {
        NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: self)

        guard let window else { return }
        scheduleToolbarRefresh(for: window)
    }

    static func applyWindowChrome(to window: NSWindow) {
        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        window.contentView?.superview?.wantsLayer = true
        window.contentView?.superview?.layer?.backgroundColor = NSColor.clear.cgColor
        window.toolbar?.displayMode = .iconOnly
        window.toolbar?.showsBaselineSeparator = false
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, .sidebarToggle, .sidebarDividerTracking, .flexibleSpace, .openSettings]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, .sidebarToggle, .sidebarDividerTracking, .flexibleSpace, .openSettings]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        if itemIdentifier == .sidebarToggle {
            return makeSidebarToggleToolbarItem(itemIdentifier: itemIdentifier)
        }

        if itemIdentifier == .sidebarDividerTracking {
            return makeSidebarTrackingSeparatorItem(itemIdentifier: itemIdentifier)
        }

        guard itemIdentifier == .openSettings else { return nil }

        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = "设置"
        item.paletteLabel = "设置"
        item.toolTip = "打开设置"
        item.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "打开设置")
        item.target = self
        item.action = #selector(openSettingsWindow)
        item.isBordered = true
        item.autovalidates = false
        item.visibilityPriority = .high
        return item
    }

    func windowWillEnterFullScreen(_ notification: Notification) {
        refreshWindowChrome()
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        refreshWindowChrome()
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        refreshWindowChrome()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        refreshWindowChrome()
    }

    private func configureWindow(_ window: NSWindow) {
        window.delegate = self
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.setFrameAutosaveName("OpenReading.MainWindow")
        window.minSize = NSSize(width: 1_180, height: 760)
        window.center()

        if #available(macOS 11.0, *) {
            window.titlebarSeparatorStyle = .none
        }

        ensureToolbarConfiguration(for: window)
        installSplitViewObservation(for: window)

        Self.applyWindowChrome(to: window)

        DispatchQueue.main.async {
            self.ensureToolbarConfiguration(for: window)
            self.installSplitViewObservation(for: window)
            Self.applyWindowChrome(to: window)
            window.toolbar?.validateVisibleItems()
        }
    }

    private func makeSidebarToggleToolbarItem(itemIdentifier: NSToolbarItem.Identifier) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = "折叠侧边栏"
        item.paletteLabel = "折叠侧边栏"
        item.toolTip = "折叠或展开侧边栏"
        item.image = NSImage(systemSymbolName: "sidebar.leading", accessibilityDescription: "折叠或展开侧边栏")
        item.target = self
        item.action = #selector(toggleSidebarFromToolbar)
        item.isBordered = true
        item.autovalidates = false
        item.visibilityPriority = .high
        return item
    }

    private func makeSidebarTrackingSeparatorItem(itemIdentifier: NSToolbarItem.Identifier) -> NSToolbarItem? {
        guard
            let splitView = window?.contentViewController?.view.firstDescendantSplitView,
            splitView.subviews.count > 1
        else {
            return makeToolbarFallbackSpacer(itemIdentifier: itemIdentifier)
        }

        return NSTrackingSeparatorToolbarItem(
            identifier: itemIdentifier,
            splitView: splitView,
            dividerIndex: 0
        )
    }

    private func makeToolbarFallbackSpacer(itemIdentifier: NSToolbarItem.Identifier) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        let spacerView = ToolbarFallbackSpacerView()
        item.view = spacerView
        item.visibilityPriority = .low
        return item
    }

    private func refreshWindowChrome() {
        guard let window else { return }
        ensureToolbarConfiguration(for: window)
        installSplitViewObservation(for: window)
        Self.applyWindowChrome(to: window)
        window.toolbar?.validateVisibleItems()
    }

    func refreshWindowChromeFromSwiftUI(for window: NSWindow) {
        ensureToolbarConfiguration(for: window)
        installSplitViewObservation(for: window)
        Self.applyWindowChrome(to: window)
        window.toolbar?.validateVisibleItems()
    }

    private func ensureToolbarConfiguration(for window: NSWindow) {
        let needsToolbarRebuild =
            window.toolbar == nil ||
            !(window.toolbar?.items.contains(where: { $0.itemIdentifier == .openSettings }) ?? false)

        let toolbar = needsToolbarRebuild ? makeToolbar() : (window.toolbar ?? makeToolbar())
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.showsBaselineSeparator = false

        if window.toolbar !== toolbar {
            window.toolbar = toolbar
        }
    }

    private func installSplitViewObservation(for window: NSWindow) {
        guard let splitView = window.contentViewController?.view.firstDescendantSplitView else { return }
        guard observedSplitView !== splitView else { return }

        if let splitViewResizeObserver {
            NotificationCenter.default.removeObserver(splitViewResizeObserver)
        }

        observedSplitView = splitView
        splitViewResizeObserver = NotificationCenter.default.addObserver(
            forName: NSSplitView.didResizeSubviewsNotification,
            object: splitView,
            queue: .main
        ) { [weak self, weak window] _ in
            guard let self, let window else { return }
            Task { @MainActor in
                self.scheduleToolbarRefresh(for: window)
            }
        }
    }

    private func scheduleToolbarRefresh(for window: NSWindow) {
        pendingToolbarRefreshes.forEach { $0.cancel() }
        pendingToolbarRefreshes.removeAll()

        for delay in [0.0, 0.12, 0.28] {
            let workItem = DispatchWorkItem { [weak self, weak window] in
                guard let self, let window else { return }
                self.ensureToolbarConfiguration(for: window)
                self.installSplitViewObservation(for: window)
                Self.applyWindowChrome(to: window)
                window.toolbar?.validateVisibleItems()
            }

            pendingToolbarRefreshes.append(workItem)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
    }

    private func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: Self.toolbarIdentifier)
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.showsBaselineSeparator = false
        return toolbar
    }
}

@MainActor
private final class MainWindowHostingController: NSHostingController<AppRootView> {
    override var title: String? {
        get { nil }
        set { super.title = nil }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        DispatchQueue.main.async { [weak self] in
            self?.refreshWindowChrome()
        }
    }

    private func refreshWindowChrome() {
        guard let window = view.window else { return }
        if let controller = window.windowController as? MainWindowController {
            controller.refreshWindowChromeFromSwiftUI(for: window)
        } else {
            MainWindowController.applyWindowChrome(to: window)
        }
    }
}

private extension NSToolbarItem.Identifier {
    static let sidebarDividerTracking = NSToolbarItem.Identifier("OpenReading.Toolbar.SidebarDividerTracking")
    static let sidebarToggle = NSToolbarItem.Identifier("OpenReading.Toolbar.SidebarToggle")
    static let openSettings = NSToolbarItem.Identifier("OpenReading.Toolbar.OpenSettings")
}

private extension NSView {
    var firstDescendantSplitView: NSSplitView? {
        if let splitView = self as? NSSplitView {
            return splitView
        }

        for subview in subviews {
            if let splitView = subview.firstDescendantSplitView {
                return splitView
            }
        }

        return nil
    }
}

private final class ToolbarFallbackSpacerView: NSView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: 1, height: 1)
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
