import XCTest
@testable import OpenWriting

final class HostedXCTestLaunchGuardTests: XCTestCase {
    func testOpenWritingTestsLaunchInsideAppHost() {
        let testBundleURL = Bundle(for: Self.self).bundleURL.standardizedFileURL
        let hostAppURL = Self.containingAppBundleURL(for: testBundleURL)
        XCTAssertNotNil(
            hostAppURL,
            "OpenWritingTests must be embedded inside an app host so hosted macOS XCTest launch regressions fail loudly."
        )

        guard let hostAppURL else {
            return
        }

        let expectedBundleIdentifier = Bundle(url: hostAppURL)?.bundleIdentifier
        XCTAssertNotNil(
            expectedBundleIdentifier,
            "The hosted XCTest guard must derive the expected bundle identifier from the built app host."
        )

        XCTAssertEqual(
            Bundle.main.bundleIdentifier,
            expectedBundleIdentifier,
            "OpenWritingTests must run inside the built app host, not a standalone XCTest runner."
        )
        XCTAssertEqual(
            Bundle.main.bundleURL.standardizedFileURL.path,
            hostAppURL.path,
            "Bundle.main must be the same app host that contains the OpenWritingTests bundle."
        )
    }

    private static func containingAppBundleURL(for bundleURL: URL) -> URL? {
        var candidate = bundleURL

        while candidate.path != "/" {
            if candidate.pathExtension == "app" {
                return candidate
            }

            let parent = candidate.deletingLastPathComponent()
            guard parent.path != candidate.path else {
                return nil
            }
            candidate = parent
        }

        return nil
    }
}
