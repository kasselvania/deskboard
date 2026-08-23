import Foundation
import XCTest
@testable import AppleEventKitProbe

final class AppleSourceContractV1Tests: XCTestCase {
    private let reminderValidFixtureNames = [
        "reminder-empty.json",
        "reminder-undated.json",
        "reminder-date-only.json",
        "reminder-local-date-time.json",
        "reminder-time-zone-date-time.json",
        "reminder-completed.json",
        "reminder-truncated.json",
    ]
    private let calendarValidFixtureNames = [
        "calendar-empty.json",
        "calendar-local-timed.json",
        "calendar-time-zone-timed.json",
        "calendar-time-zone-offset-transition.json",
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
        "ambiguous-local-date-time.json",
        "nonexistent-local-date-time.json",
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
        "duplicate-reminder-order-coordinate.json",
        "duplicate-calendar-order-coordinate.json",
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
            let snapshot = try XCTUnwrap(decoded.reminderSnapshot, fixtureName)
            XCTAssertNil(decoded.calendarSnapshot, fixtureName)
            let encoded = try JSONEncoder().encode(snapshot)
            let roundTripped = try XCTUnwrap(
                AppleSourceContractDecoder.decode(encoded).reminderSnapshot,
                fixtureName
            )
            XCTAssertEqual(roundTripped, snapshot, fixtureName)
        }

        for fixtureName in calendarValidFixtureNames {
            let decoded = try AppleSourceContractDecoder.decode(
                data(collection: "valid", fixtureName: fixtureName)
            )
            let snapshot = try XCTUnwrap(decoded.calendarSnapshot, fixtureName)
            XCTAssertNil(decoded.reminderSnapshot, fixtureName)
            let encoded = try JSONEncoder().encode(snapshot)
            let roundTripped = try XCTUnwrap(
                AppleSourceContractDecoder.decode(encoded).calendarSnapshot,
                fixtureName
            )
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
            "ambiguous-local-date-time.json",
            "nonexistent-local-date-time.json",
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
            "duplicate-reminder-order-coordinate.json",
            "duplicate-calendar-order-coordinate.json",
        ] {
            XCTAssertThrowsError(
                try AppleSourceContractDecoder.decode(
                    data(collection: "invalid", fixtureName: fixtureName)
                ),
                fixtureName
            )
        }
    }

    func testOnlyStrictlyValidatedCompleteScopesAuthorizeAbsence() throws {
        let emptyReminder = try AppleSourceContractDecoder.decode(
            data(collection: "valid", fixtureName: "reminder-empty.json")
        )
        let emptyCalendar = try AppleSourceContractDecoder.decode(
            data(collection: "valid", fixtureName: "calendar-empty.json")
        )
        let truncatedReminder = try AppleSourceContractDecoder.decode(
            data(collection: "valid", fixtureName: "reminder-truncated.json")
        )
        let truncatedCalendar = try AppleSourceContractDecoder.decode(
            data(collection: "valid", fixtureName: "calendar-truncated.json")
        )

        XCTAssertTrue(emptyReminder.absenceIsAuthoritative)
        XCTAssertTrue(emptyCalendar.absenceIsAuthoritative)
        XCTAssertFalse(truncatedReminder.absenceIsAuthoritative)
        XCTAssertFalse(truncatedCalendar.absenceIsAuthoritative)

        for fixtureName in [
            "unknown-top-level-key.json",
            "unsupported-schema-version.json",
            "non-truncated-count-inconsistency.json",
        ] {
            XCTAssertThrowsError(
                try AppleSourceContractDecoder.decode(
                    data(collection: "invalid", fixtureName: fixtureName)
                ),
                fixtureName
            )
        }
    }

    func testTimezoneQualifiedRangePreservesExactTransitionInstants() throws {
        let decoded = try AppleSourceContractDecoder.decode(
            data(
                collection: "valid",
                fixtureName: "calendar-time-zone-offset-transition.json"
            )
        )
        let temporal = try XCTUnwrap(decoded.calendarSnapshot?.records.first?.temporal)

        XCTAssertEqual(temporal.kind, .timeZoneTimedRange)
        XCTAssertEqual(temporal.start, "2026-11-01T01:30:00-07:00")
        XCTAssertEqual(temporal.end, "2026-11-01T01:30:00-08:00")
        XCTAssertNil(temporal.startLocalDateTime)
        XCTAssertNil(temporal.endLocalDateTime)
    }

    func testRecurringOccurrenceDoesNotImportRecurrenceGrammar() throws {
        let fixtureData = try data(
            collection: "valid",
            fixtureName: "calendar-recurring-occurrence.json"
        )
        let snapshot = try XCTUnwrap(
            AppleSourceContractDecoder.decode(fixtureData).calendarSnapshot
        )

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
