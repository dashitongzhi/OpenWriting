import XCTest
@testable import OpenWriting

final class HostedXCTestLaunchGuardTests: XCTestCase {
    func testOpenWritingTestsLaunchInsideAppHost() {
        XCTAssertEqual(
            Bundle.main.bundleIdentifier,
            "CHZ.Kral.OpenWriting",
            "OpenWritingTests must run inside OpenWriting.app so hosted macOS XCTest launch regressions fail loudly."
        )
    }
}
