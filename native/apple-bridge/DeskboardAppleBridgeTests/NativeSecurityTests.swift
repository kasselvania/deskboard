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
        XCTAssertTrue(project.contains("CODE_SIGN_STYLE = Automatic;"))
        XCTAssertTrue(project.contains("--options runtime"))
        XCTAssertTrue(project.contains("CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO;"))
        XCTAssertTrue(project.contains("INFOPLIST_KEY_NSCalendarsFullAccessUsageDescription"))
        XCTAssertTrue(project.contains("INFOPLIST_KEY_NSRemindersFullAccessUsageDescription"))
        XCTAssertFalse(project.contains("DEVELOPMENT_TEAM"))
        XCTAssertFalse(project.contains("CODE_SIGN_IDENTITY = \"-\";"))
        XCTAssertFalse(project.contains("com.apple.security.network.server"))
        XCTAssertFalse(project.contains("com.apple.security.files.user-selected"))
        XCTAssertFalse(project.contains("com.apple.security.files.downloads"))

        for identifier in [
            "E40000000000000000000003",
            "E40000000000000000000004",
        ] {
            let block = try applicationBuildConfiguration(
                identifier: identifier,
                project: project
            )
            XCTAssertFalse(block.contains("CODE_SIGN_IDENTITY"))
        }
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

    private func applicationBuildConfiguration(
        identifier: String,
        project: String
    ) throws -> Substring {
        let start = try XCTUnwrap(project.range(of: "\t\t\(identifier) /*"))
        let end = try XCTUnwrap(
            project.range(
                of: "\n\t\t};",
                range: start.lowerBound ..< project.endIndex
            )
        )
        return project[start.lowerBound ..< end.upperBound]
    }
}
