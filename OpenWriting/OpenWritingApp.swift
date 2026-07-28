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
    private let terminationFlushCoordinator = TerminationFlushCoordinator(
        timeout: .seconds(8)
    )
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

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !Self.isRunningUnitTests else { return .terminateNow }
        _ = terminationFlushCoordinator.begin(
            flush: {
                AppRuntime.shared.appState.flushAPIKeyPersistence()
                return await AppRuntime.shared.appState.flushProjectPersistence()
            },
            reply: { [weak sender] didFlush in
                sender?.reply(toApplicationShouldTerminate: didFlush)
            }
        )
        return .terminateLater
    }
}

@MainActor
final class TerminationFlushCoordinator {
    typealias FlushOperation = @MainActor () async -> Bool
    typealias ReplyOperation = @MainActor (Bool) -> Void

    private let timeout: Duration
    private var generation: UInt64 = 0
    private var flushTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    private(set) var isRunning = false

    init(timeout: Duration) {
        self.timeout = timeout
    }

    @discardableResult
    func begin(
        flush: @escaping FlushOperation,
        reply: @escaping ReplyOperation
    ) -> Bool {
        guard !isRunning else { return false }

        isRunning = true
        generation &+= 1
        let activeGeneration = generation

        flushTask = Task { @MainActor [weak self] in
            let didFlush = await flush()
            self?.finish(
                generation: activeGeneration,
                didFlush: didFlush,
                reply: reply
            )
        }
        timeoutTask = Task { @MainActor [weak self, timeout] in
            do {
                try await Task.sleep(for: timeout)
            } catch {
                return
            }
            self?.finish(
                generation: activeGeneration,
                didFlush: false,
                reply: reply
            )
        }
        return true
    }

    private func finish(
        generation activeGeneration: UInt64,
        didFlush: Bool,
        reply: ReplyOperation
    ) {
        guard isRunning, generation == activeGeneration else { return }

        isRunning = false
        flushTask?.cancel()
        timeoutTask?.cancel()
        flushTask = nil
        timeoutTask = nil
        reply(didFlush)
    }
}
