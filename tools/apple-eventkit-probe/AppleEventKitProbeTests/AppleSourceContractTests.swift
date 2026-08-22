import Foundation
import XCTest
@testable import AppleEventKitProbe

final class AppleSourceContractV1Tests: XCTestCase {
    private let reminderValidFixtureNames = [
        "reminder-undated.json",
        "reminder-date-only.json",
        "reminder-local-date-time.json",
        "reminder-time-zone-date-time.json",
        "reminder-completed.json",
        "reminder-truncated.json",
    ]
    private let calendarValidFixtureNames = [
        "calendar-local-timed.json",
        "calendar-time-zone-timed.json",
        "calendar-all-day-single-day.json",
        "calendar-recurring-occurrence.json",
        "calendar-subscribed-read-only.json",
        "calendar-truncated.json",
    ]
    private let invalidFixtureNames = [
        "unsupported-schema-version.json",
        "unknown-top-level-key.json",
        "unknown-nested-key.json",
        "wrong-entity-discriminator.json",
        "contradictory-temporal-fields.json",
        "impossible-date.json",
        "impossible-clock-time.json",
        "offset-in-local-date-time.json",
        "timed-end-not-after-start.json",
        "all-day-end-not-after-start.json",
        "incomplete-reminder-with-completion-date.json",
        "matched-count-below-records-length.json",
        "non-truncated-count-inconsistency.json",
        "truncated-without-omission.json",
        "malformed-calendar-window.json",
        "unrecognized-time-zone.json",
        "excluded-participant-field.json",
        "calendar-record-outside-window.json",
        "reminder-record-order.json",
        "calendar-record-order.json",
    ]

    func testExactSharedFixtureInventories() throws {
        try assertExactJSONFiles(
            in: "valid",
            allowlist: reminderValidFixtureNames + calendarValidFixtureNames
        )
        try assertExactJSONFiles(in: "invalid", allowlist: invalidFixtureNames)
    }

    func testEveryValidFixtureDecodesValidatesAndRoundTrips() throws {
        for fixtureName in reminderValidFixtureNames {
            let decoded = try AppleSourceContractDecoder.decode(
                data(collection: "valid", fixtureName: fixtureName)
            )
            guard case let .reminder(snapshot) = decoded else {
                return XCTFail("Expected Reminder variant for \(fixtureName)")
            }
            let encoded = try JSONEncoder().encode(snapshot)
            guard case let .reminder(roundTripped) = try AppleSourceContractDecoder.decode(encoded) else {
                return XCTFail("Expected Reminder round trip for \(fixtureName)")
            }
            XCTAssertEqual(roundTripped, snapshot, fixtureName)
        }

        for fixtureName in calendarValidFixtureNames {
            let decoded = try AppleSourceContractDecoder.decode(
                data(collection: "valid", fixtureName: fixtureName)
            )
            guard case let .calendar(snapshot) = decoded else {
                return XCTFail("Expected Calendar variant for \(fixtureName)")
            }
            let encoded = try JSONEncoder().encode(snapshot)
            guard case let .calendar(roundTripped) = try AppleSourceContractDecoder.decode(encoded) else {
                return XCTFail("Expected Calendar round trip for \(fixtureName)")
            }
            XCTAssertEqual(roundTripped, snapshot, fixtureName)
        }
    }

    func testEveryInvalidFixtureFailsStrictOrSemanticValidation() throws {
        for fixtureName in invalidFixtureNames {
            XCTAssertThrowsError(
                try AppleSourceContractDecoder.decode(
                    data(collection: "invalid", fixtureName: fixtureName)
                ),
                fixtureName
            )
        }
    }

    func testUnknownKeysFailAtTopScopeTemporalAndRecordLevels() throws {
        for fixtureName in [
            "unknown-top-level-key.json",
            "unknown-nested-key.json",
            "contradictory-temporal-fields.json",
            "excluded-participant-field.json",
        ] {
            XCTAssertThrowsError(
                try AppleSourceContractDecoder.decode(
                    data(collection: "invalid", fixtureName: fixtureName)
                ),
                fixtureName
            )
        }
    }

    func testTemporalCompletionCountScopeAndOrderingFailuresMatchTypeScript() throws {
        for fixtureName in [
            "impossible-date.json",
            "impossible-clock-time.json",
            "offset-in-local-date-time.json",
            "timed-end-not-after-start.json",
            "all-day-end-not-after-start.json",
            "incomplete-reminder-with-completion-date.json",
            "matched-count-below-records-length.json",
            "non-truncated-count-inconsistency.json",
            "truncated-without-omission.json",
            "malformed-calendar-window.json",
            "unrecognized-time-zone.json",
            "calendar-record-outside-window.json",
            "reminder-record-order.json",
            "calendar-record-order.json",
        ] {
            XCTAssertThrowsError(
                try AppleSourceContractDecoder.decode(
                    data(collection: "invalid", fixtureName: fixtureName)
                ),
                fixtureName
            )
        }
    }

    func testOnlyCompleteScopesAuthorizeAbsence() throws {
        let complete = try AppleSourceContractDecoder.decode(
            data(collection: "valid", fixtureName: "reminder-undated.json")
        )
        let truncatedReminder = try AppleSourceContractDecoder.decode(
            data(collection: "valid", fixtureName: "reminder-truncated.json")
        )
        let truncatedCalendar = try AppleSourceContractDecoder.decode(
            data(collection: "valid", fixtureName: "calendar-truncated.json")
        )

        XCTAssertTrue(complete.absenceIsAuthoritative)
        XCTAssertFalse(truncatedReminder.absenceIsAuthoritative)
        XCTAssertFalse(truncatedCalendar.absenceIsAuthoritative)
    }

    func testRecurringOccurrenceDoesNotImportRecurrenceGrammar() throws {
        let fixtureData = try data(
            collection: "valid",
            fixtureName: "calendar-recurring-occurrence.json"
        )
        guard case let .calendar(snapshot) = try AppleSourceContractDecoder.decode(fixtureData) else {
            return XCTFail("Expected Calendar variant")
        }

        XCTAssertNotNil(snapshot.records.first?.occurrenceDate)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: fixtureData) as? [String: Any]
        )
        let records = try XCTUnwrap(object["records"] as? [[String: Any]])
        XCTAssertNil(records.first?["recurrences"])
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
                .appendingPathComponent("fixtures/apple-source-contract/v1")
                .appendingPathComponent(collection)
                .appendingPathComponent(fixtureName)
        )
    }

    private func assertExactJSONFiles(
        in collection: String,
        allowlist: [String]
    ) throws {
        let directory = repositoryRoot
            .appendingPathComponent("fixtures/apple-source-contract/v1")
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
