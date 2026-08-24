import Foundation
import XCTest
@testable import DeskboardAppleBridge

final class NativeSecurityTests: XCTestCase {
    func testProductionTargetDeclaresOnlyTheRequiredSandboxCapabilities() throws {
        let root = projectRoot()
        let entitlementURL = root
            .appendingPathComponent("DeskboardAppleBridge", isDirectory: true)
            .appendingPathComponent("DeskboardAppleBridge.entitlements")
        let data = try Data(contentsOf: entitlementURL)
        let value = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any]
        )
        let expectedKeys: Set<String> = [
            "com.apple.security.app-sandbox",
            "com.apple.security.network.client",
            "com.apple.security.personal-information.calendars",
        ]

        XCTAssertEqual(Set(value.keys), expectedKeys)
        for key in expectedKeys {
            XCTAssertEqual(value[key] as? Bool, true)
        }

        let project = try String(
            contentsOf: root
                .appendingPathComponent("DeskboardAppleBridge.xcodeproj", isDirectory: true)
                .appendingPathComponent("project.pbxproj"),
            encoding: .utf8
        )
        XCTAssertTrue(project.contains("ENABLE_APP_SANDBOX = YES;"))
        XCTAssertTrue(project.contains("ENABLE_HARDENED_RUNTIME = YES;"))
        XCTAssertTrue(project.contains("--options runtime"))
        XCTAssertTrue(project.contains("CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO;"))
        XCTAssertTrue(project.contains("INFOPLIST_KEY_NSCalendarsFullAccessUsageDescription"))
        XCTAssertTrue(project.contains("INFOPLIST_KEY_NSRemindersFullAccessUsageDescription"))
        XCTAssertFalse(project.contains("com.apple.security.network.server"))
        XCTAssertFalse(project.contains("com.apple.security.files.user-selected"))
        XCTAssertFalse(project.contains("com.apple.security.files.downloads"))
    }

    func testProductionSourcesHaveNoProbeCommandOrPrivateExportPath() throws {
        let sourceRoot = projectRoot()
            .appendingPathComponent("DeskboardAppleBridge", isDirectory: true)
        let urls = try FileManager.default.contentsOfDirectory(
            at: sourceRoot,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "swift" }
        let sources = try urls
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")

        for forbidden in [
            "private-fixtures",
            "CommandLine.arguments",
            "ProcessInfo.processInfo.arguments",
            "NSOpenPanel",
            "NSSavePanel",
        ] {
            XCTAssertFalse(sources.contains(forbidden))
        }
    }

    private func projectRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
