import Foundation
import XCTest
@testable import DeskboardAppleBridge

final class BridgeStatusContractTests: XCTestCase {
    private let validFixtureNames = [
        "empty-independent-permissions.json",
        "selected-applied.json",
        "selected-blocked-invalid.json",
        "selected-retry-pending.json",
        "selected-unavailable.json",
    ]
    private let invalidFixtureNames = [
        "acknowledged-without-time.json",
        "duplicate-coordinate.json",
        "excluded-source-title.json",
        "invalid-captured-at.json",
        "pending-revision-gap.json",
        "retry-without-pending.json",
        "success-with-pending.json",
        "unknown-delivery-key.json",
        "unknown-permission.json",
        "unknown-top-level-key.json",
        "unordered-coordinate.json",
        "unsupported-schema-version.json",
        "zero-status-revision.json",
    ]

    func testExactSharedFixtureInventories() throws {
        try assertExactJSONFiles(in: "valid", allowlist: validFixtureNames)
        try assertExactJSONFiles(in: "invalid", allowlist: invalidFixtureNames)
    }

    func testEveryValidFixtureStrictlyDecodesValidatesAndRoundTrips() throws {
        for fixtureName in validFixtureNames {
            let snapshot = try AppleBridgeStatusContractDecoder.decode(
                data(collection: "valid", fixtureName: fixtureName)
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            let roundTripped = try AppleBridgeStatusContractDecoder.decode(
                encoder.encode(snapshot)
            )
            XCTAssertEqual(roundTripped, snapshot, fixtureName)
        }
    }

    func testEveryInvalidFixtureFailsStrictOrSemanticValidation() throws {
        for fixtureName in invalidFixtureNames {
            XCTAssertThrowsError(
                try AppleBridgeStatusContractDecoder.decode(
                    data(collection: "invalid", fixtureName: fixtureName)
                ),
                fixtureName
            )
        }
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func data(collection: String, fixtureName: String) throws -> Data {
        try Data(
            contentsOf: repositoryRoot
                .appendingPathComponent("fixtures/apple-bridge-status/v1")
                .appendingPathComponent(collection)
                .appendingPathComponent(fixtureName)
        )
    }

    private func assertExactJSONFiles(
        in collection: String,
        allowlist: [String]
    ) throws {
        let directory = repositoryRoot
            .appendingPathComponent("fixtures/apple-bridge-status/v1")
            .appendingPathComponent(collection)
        let actual = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: []
        )
        .filter { $0.pathExtension == "json" }
        .map(\.lastPathComponent)
        .sorted()

        XCTAssertEqual(actual, allowlist.sorted())
    }
}
