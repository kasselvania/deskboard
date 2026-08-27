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

        let releaseEntitlementURL = root
            .appendingPathComponent("DeskboardAppleBridge", isDirectory: true)
            .appendingPathComponent("DeskboardAppleBridgeRelease.entitlements")
        let releaseData = try Data(contentsOf: releaseEntitlementURL)
        let releaseValue = try XCTUnwrap(
            PropertyListSerialization.propertyList(
                from: releaseData,
                format: nil
            ) as? [String: Any]
        )
        let signingKeys: Set<String> = [
            "com.apple.application-identifier",
            "com.apple.developer.team-identifier",
        ]
        XCTAssertEqual(Set(releaseValue.keys), expectedKeys.union(signingKeys))
        for key in expectedKeys {
            XCTAssertEqual(releaseValue[key] as? Bool, true)
        }
        XCTAssertEqual(
            releaseValue["com.apple.application-identifier"] as? String,
            "$(DEVELOPMENT_TEAM).$(PRODUCT_BUNDLE_IDENTIFIER)"
        )
        XCTAssertEqual(
            releaseValue["com.apple.developer.team-identifier"] as? String,
            "$(DEVELOPMENT_TEAM)"
        )

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

        let debugBlock = try applicationBuildConfiguration(
            identifier: "E40000000000000000000003",
            project: project
        )
        XCTAssertTrue(
            debugBlock.contains(
                "CODE_SIGN_ENTITLEMENTS = DeskboardAppleBridge/DeskboardAppleBridge.entitlements;"
            )
        )
        XCTAssertFalse(debugBlock.contains("CODE_SIGN_IDENTITY"))

        let releaseBlock = try applicationBuildConfiguration(
            identifier: "E40000000000000000000004",
            project: project
        )
        XCTAssertTrue(
            releaseBlock.contains(
                "CODE_SIGN_ENTITLEMENTS = DeskboardAppleBridge/DeskboardAppleBridgeRelease.entitlements;"
            )
        )
        XCTAssertFalse(releaseBlock.contains("CODE_SIGN_IDENTITY"))
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

    func testUnattendedRuntimeUsesOnlyTheSignedMainAppAndContentFreeOutput() throws {
        let root = projectRoot()
        let source = try String(
            contentsOf: root
                .appendingPathComponent("DeskboardAppleBridge", isDirectory: true)
                .appendingPathComponent("UnattendedBridge.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(source.contains("SMAppService.mainApp"))
        XCTAssertTrue(source.contains("NSBackgroundActivityScheduler"))
        for forbidden in [
            "SMAppService.agent",
            "SMAppService.daemon",
            "SMLoginItemSetEnabled",
            "LaunchAgent",
            "LaunchDaemon",
            "NSLog(",
            "print(",
            "os_log(",
            "Logger(",
        ] {
            XCTAssertFalse(source.contains(forbidden))
        }

        let infoData = try Data(
            contentsOf: root
                .appendingPathComponent("DeskboardAppleBridge", isDirectory: true)
                .appendingPathComponent("Info.plist")
        )
        let info = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: infoData, format: nil)
                as? [String: Any]
        )
        XCTAssertEqual(info["LSUIElement"] as? Bool, true)
    }

    func testNoBackgroundPathCanInvokeBlockedTruncationRecovery() throws {
        let sourceRoot = projectRoot()
            .appendingPathComponent("DeskboardAppleBridge", isDirectory: true)
        let unattended = try String(
            contentsOf: sourceRoot.appendingPathComponent("UnattendedBridge.swift"),
            encoding: .utf8
        )
        let app = try String(
            contentsOf: sourceRoot.appendingPathComponent("DeskboardAppleBridgeApp.swift"),
            encoding: .utf8
        )
        let viewModel = try String(
            contentsOf: sourceRoot.appendingPathComponent("BridgeViewModel.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(unattended.contains("BlockedTruncationRecovery"))
        XCTAssertFalse(unattended.contains("rebuildBlockedReminder"))
        XCTAssertFalse(app.contains("rebuildBlockedReminder"))
        XCTAssertTrue(
            viewModel.contains("rebuildBlockedSourceWithCurrentLimits")
        )
    }

    func testMenuBarSettingsActionExplicitlyOpensAndActivatesSettings() throws {
        let app = try String(
            contentsOf: projectRoot()
                .appendingPathComponent("DeskboardAppleBridge", isDirectory: true)
                .appendingPathComponent("DeskboardAppleBridgeApp.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(app.contains("@Environment(\\.openSettings)"))
        XCTAssertTrue(app.contains("openSettings()"))
        XCTAssertTrue(
            app.contains("NSApplication.shared.activate(ignoringOtherApps: true)")
        )
        XCTAssertFalse(app.contains("SettingsLink"))
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
