import Foundation
import XCTest
@testable import DeskboardAppleBridge

final class AppleSourceConverterTests: XCTestCase {
    func testReminderConversionPreservesAcceptedTemporalVariantsAndExactFields() throws {
        var dateOnly = DateComponents()
        dateOnly.year = 2026
        dateOnly.month = 8
        dateOnly.day = 24
        var local = dateOnly
        local.hour = 9
        local.minute = 30
        var zoned = local
        zoned.timeZone = TimeZone(identifier: "America/Los_Angeles")

        let snapshot = try AppleSourceConverter.reminderSnapshot(
            from: ReminderSourceRead(
                sourceContainerId: "synthetic-reminder-source",
                allowsContentModifications: true,
                records: [
                    ReminderRecordRead(
                        localIdentifier: "synthetic-c",
                        externalIdentifier: nil,
                        title: nil,
                        startComponents: local,
                        dueComponents: zoned,
                        isCompleted: true,
                        completionDate: date("2026-08-24T18:00:00Z")
                    ),
                    ReminderRecordRead(
                        localIdentifier: "synthetic-a",
                        externalIdentifier: "synthetic-external",
                        title: "Synthetic reminder",
                        startComponents: nil,
                        dueComponents: dateOnly,
                        isCompleted: false,
                        completionDate: nil
                    ),
                ]
            ),
            bridgeId: "synthetic-bridge",
            capturedAt: date("2026-08-23T18:00:00Z")
        )
        guard case let .reminder(value) = snapshot else {
            return XCTFail("Expected Reminder snapshot")
        }

        XCTAssertEqual(
            value,
            AppleReminderSourceSnapshotV1(
                schemaVersion: 1,
                entityType: .reminder,
                bridgeId: "synthetic-bridge",
                source: AppleReminderSourceScopeV1(
                    sourceContainerId: "synthetic-reminder-source",
                    allowsContentModifications: true
                ),
                capturedAt: "2026-08-23T18:00:00Z",
                matchedCount: 2,
                truncated: false,
                records: [
                    AppleReminderSourceRecordV1(
                        localIdentifier: "synthetic-a",
                        externalIdentifier: "synthetic-external",
                        title: "Synthetic reminder",
                        start: AppleReminderTemporalV1(
                            kind: .absent,
                            localDate: nil,
                            localDateTime: nil,
                            timeZone: nil
                        ),
                        due: AppleReminderTemporalV1(
                            kind: .dateOnly,
                            localDate: "2026-08-24",
                            localDateTime: nil,
                            timeZone: nil
                        ),
                        isCompleted: false,
                        completionDate: nil
                    ),
                    AppleReminderSourceRecordV1(
                        localIdentifier: "synthetic-c",
                        externalIdentifier: nil,
                        title: nil,
                        start: AppleReminderTemporalV1(
                            kind: .localDateTime,
                            localDate: nil,
                            localDateTime: "2026-08-24T09:30:00",
                            timeZone: nil
                        ),
                        due: AppleReminderTemporalV1(
                            kind: .timeZoneDateTime,
                            localDate: nil,
                            localDateTime: "2026-08-24T09:30:00",
                            timeZone: "America/Los_Angeles"
                        ),
                        isCompleted: true,
                        completionDate: "2026-08-24T18:00:00Z"
                    ),
                ]
            )
        )
        try value.validate()
    }

    func testCalendarConversionPreservesExactInstantsAllDayRangesAndWindow() throws {
        let zone = TimeZone(identifier: "America/Los_Angeles")!
        let snapshot = try AppleSourceConverter.calendarSnapshot(
            from: CalendarSourceRead(
                sourceContainerId: "synthetic-calendar-source",
                allowsContentModifications: false,
                isSubscribed: true,
                windowStart: date("2026-08-16T18:00:00Z"),
                windowEnd: date("2026-10-07T18:00:00Z"),
                windowTimeZone: zone,
                records: [
                    CalendarRecordRead(
                        localIdentifier: "synthetic-timed",
                        eventIdentifier: "synthetic-event",
                        externalIdentifier: nil,
                        title: "Synthetic timed event",
                        temporal: .timed(
                            start: date("2026-08-24T16:00:00Z"),
                            end: date("2026-08-24T17:00:00Z"),
                            timeZone: zone
                        ),
                        occurrenceDate: date("2026-08-24T16:00:00Z"),
                        isDetached: false,
                        status: .confirmed
                    ),
                    CalendarRecordRead(
                        localIdentifier: "synthetic-all-day",
                        eventIdentifier: nil,
                        externalIdentifier: nil,
                        title: nil,
                        temporal: .allDay(
                            start: date("2026-08-23T07:00:00Z"),
                            end: date("2026-08-25T07:00:00Z")
                        ),
                        occurrenceDate: nil,
                        isDetached: true,
                        status: .tentative
                    ),
                ]
            ),
            bridgeId: "synthetic-bridge",
            capturedAt: date("2026-08-23T18:00:00Z")
        )
        guard case let .calendar(value) = snapshot else {
            return XCTFail("Expected Calendar snapshot")
        }

        XCTAssertEqual(
            value,
            AppleCalendarSourceSnapshotV1(
                schemaVersion: 1,
                entityType: .calendar,
                bridgeId: "synthetic-bridge",
                source: AppleCalendarSourceScopeV1(
                    sourceContainerId: "synthetic-calendar-source",
                    allowsContentModifications: false,
                    isSubscribed: true
                ),
                capturedAt: "2026-08-23T18:00:00Z",
                window: AppleCalendarWindowV1(
                    start: "2026-08-16T18:00:00Z",
                    end: "2026-10-07T18:00:00Z",
                    timeZone: "America/Los_Angeles",
                    boundarySemantics: .overlapStartInclusiveEndExclusive
                ),
                matchedCount: 2,
                truncated: false,
                records: [
                    AppleCalendarSourceRecordV1(
                        localIdentifier: "synthetic-all-day",
                        eventIdentifier: nil,
                        externalIdentifier: nil,
                        title: nil,
                        temporal: AppleCalendarTemporalV1(
                            kind: .allDayRange,
                            startLocalDateTime: nil,
                            endLocalDateTime: nil,
                            start: nil,
                            end: nil,
                            timeZone: nil,
                            startDate: "2026-08-23",
                            endDate: "2026-08-25"
                        ),
                        occurrenceDate: nil,
                        isDetached: true,
                        status: .tentative
                    ),
                    AppleCalendarSourceRecordV1(
                        localIdentifier: "synthetic-timed",
                        eventIdentifier: "synthetic-event",
                        externalIdentifier: nil,
                        title: "Synthetic timed event",
                        temporal: AppleCalendarTemporalV1(
                            kind: .timeZoneTimedRange,
                            startLocalDateTime: nil,
                            endLocalDateTime: nil,
                            start: "2026-08-24T09:00:00-07:00",
                            end: "2026-08-24T10:00:00-07:00",
                            timeZone: "America/Los_Angeles",
                            startDate: nil,
                            endDate: nil
                        ),
                        occurrenceDate: "2026-08-24T16:00:00Z",
                        isDetached: false,
                        status: .confirmed
                    ),
                ]
            )
        )
        try value.validate()
    }

    func testLocalCalendarTimesRequireExactlyOneInstant() throws {
        let zone = TimeZone(identifier: "America/Los_Angeles")!
        let base = CalendarSourceRead(
            sourceContainerId: "synthetic-calendar-source",
            allowsContentModifications: true,
            isSubscribed: false,
            windowStart: date("2026-01-01T00:00:00Z"),
            windowEnd: date("2027-01-01T00:00:00Z"),
            windowTimeZone: zone,
            records: []
        )
        for temporal in [
            CalendarRecordTemporalRead.localTimed(
                start: "2026-03-08T02:15:00",
                end: "2026-03-08T03:15:00"
            ),
            CalendarRecordTemporalRead.localTimed(
                start: "2026-11-01T01:15:00",
                end: "2026-11-01T01:45:00"
            ),
        ] {
            let source = CalendarSourceRead(
                sourceContainerId: base.sourceContainerId,
                allowsContentModifications: base.allowsContentModifications,
                isSubscribed: base.isSubscribed,
                windowStart: base.windowStart,
                windowEnd: base.windowEnd,
                windowTimeZone: base.windowTimeZone,
                records: [calendarRecord(id: "synthetic-local", temporal: temporal)]
            )
            XCTAssertThrowsError(
                try AppleSourceConverter.calendarSnapshot(
                    from: source,
                    bridgeId: "synthetic-bridge",
                    capturedAt: date("2026-08-23T18:00:00Z")
                )
            )
        }
    }

    func testUnambiguousLocalCalendarTimeIsPreservedWithoutInventingAZone() throws {
        let zone = TimeZone(identifier: "America/Los_Angeles")!
        let snapshot = try AppleSourceConverter.calendarSnapshot(
            from: CalendarSourceRead(
                sourceContainerId: "synthetic-calendar-source",
                allowsContentModifications: true,
                isSubscribed: false,
                windowStart: date("2026-08-01T07:00:00Z"),
                windowEnd: date("2026-09-01T07:00:00Z"),
                windowTimeZone: zone,
                records: [
                    calendarRecord(
                        id: "synthetic-local",
                        temporal: .localTimed(
                            start: "2026-08-24T09:00:00",
                            end: "2026-08-24T10:00:00"
                        )
                    ),
                ]
            ),
            bridgeId: "synthetic-bridge",
            capturedAt: date("2026-08-23T18:00:00Z")
        )
        guard case let .calendar(value) = snapshot else {
            return XCTFail("Expected Calendar snapshot")
        }

        XCTAssertEqual(value.records.first?.temporal.kind, .localTimedRange)
        XCTAssertEqual(
            value.records.first?.temporal.startLocalDateTime,
            "2026-08-24T09:00:00"
        )
        XCTAssertEqual(value.records.first?.temporal.timeZone, nil)
        try value.validate()
    }

    func testOrderingCollisionAndCapsApplyToTheCompleteMatchedSet() throws {
        let reminders = (0 ..< 4).reversed().map { index in
            ReminderRecordRead(
                localIdentifier: "synthetic-\(index)",
                externalIdentifier: nil,
                title: "Synthetic",
                startComponents: nil,
                dueComponents: nil,
                isCompleted: false,
                completionDate: nil
            )
        }
        let bounded = try AppleSourceConverter.reminderSnapshot(
            from: ReminderSourceRead(
                sourceContainerId: "synthetic-source",
                allowsContentModifications: true,
                records: reminders
            ),
            bridgeId: "synthetic-bridge",
            capturedAt: date("2026-08-23T18:00:00Z"),
            maximumRecords: 2
        )
        guard case let .reminder(snapshot) = bounded else {
            return XCTFail("Expected Reminder snapshot")
        }
        XCTAssertEqual(snapshot.matchedCount, 4)
        XCTAssertEqual(snapshot.records.map(\.localIdentifier), ["synthetic-0", "synthetic-1"])
        XCTAssertTrue(snapshot.truncated)

        let collision = ReminderSourceRead(
            sourceContainerId: "synthetic-source",
            allowsContentModifications: true,
            records: [reminders[0], reminders[0]]
        )
        XCTAssertThrowsError(
            try AppleSourceConverter.reminderSnapshot(
                from: collision,
                bridgeId: "synthetic-bridge",
                capturedAt: date("2026-08-23T18:00:00Z"),
                maximumRecords: 1
            )
        )

        let sameRange = CalendarRecordTemporalRead.localTimed(
            start: "2026-08-24T09:00:00",
            end: "2026-08-24T10:00:00"
        )
        let calendarSource = CalendarSourceRead(
            sourceContainerId: "synthetic-calendar-source",
            allowsContentModifications: true,
            isSubscribed: false,
            windowStart: date("2026-08-01T00:00:00Z"),
            windowEnd: date("2026-09-01T00:00:00Z"),
            windowTimeZone: TimeZone(identifier: "Etc/UTC")!,
            records: [
                calendarRecord(id: "synthetic-b", temporal: sameRange),
                calendarRecord(id: "synthetic-a", temporal: sameRange),
            ]
        )
        let ordered = try AppleSourceConverter.calendarSnapshot(
            from: calendarSource,
            bridgeId: "synthetic-bridge",
            capturedAt: date("2026-08-23T18:00:00Z")
        )
        guard case let .calendar(calendarSnapshot) = ordered else {
            return XCTFail("Expected Calendar snapshot")
        }
        XCTAssertEqual(
            calendarSnapshot.records.map(\.localIdentifier),
            ["synthetic-a", "synthetic-b"]
        )

        let duplicate = calendarRecord(id: "synthetic-a", temporal: sameRange)
        XCTAssertThrowsError(
            try AppleSourceConverter.calendarSnapshot(
                from: CalendarSourceRead(
                    sourceContainerId: calendarSource.sourceContainerId,
                    allowsContentModifications: true,
                    isSubscribed: false,
                    windowStart: calendarSource.windowStart,
                    windowEnd: calendarSource.windowEnd,
                    windowTimeZone: calendarSource.windowTimeZone,
                    records: [duplicate, duplicate]
                ),
                bridgeId: "synthetic-bridge",
                capturedAt: date("2026-08-23T18:00:00Z"),
                maximumRecords: 1
            )
        )
    }

    func testMeasuredProductionReminderLimitCompletes945AndTruncates1001Exactly() throws {
        let capturedAt = date("2026-08-26T12:00:00Z")
        let makeSource: (Int) -> ReminderSourceRead = { count in
            ReminderSourceRead(
                sourceContainerId: "synthetic-production-limit-source",
                allowsContentModifications: true,
                records: (0 ..< count).reversed().map { index in
                    ReminderRecordRead(
                        localIdentifier: String(format: "synthetic-%05d", index),
                        externalIdentifier: nil,
                        title: "Synthetic bounded reminder",
                        startComponents: nil,
                        dueComponents: nil,
                        isCompleted: index.isMultiple(of: 2),
                        completionDate: nil
                    )
                }
            )
        }

        let complete = try AppleSourceConverter.reminderSnapshot(
            from: makeSource(945),
            bridgeId: "synthetic-bridge",
            capturedAt: capturedAt
        )
        guard case let .reminder(completeSnapshot) = complete else {
            return XCTFail("Expected Reminder snapshot")
        }
        XCTAssertEqual(completeSnapshot.matchedCount, 945)
        XCTAssertEqual(completeSnapshot.records.count, 945)
        XCTAssertFalse(completeSnapshot.truncated)
        let completeBytes = try AppleSourceEnvelopeCodec.encodeWithinProductionLimit(
            sourceRevision: 1,
            snapshot: complete
        )
        XCTAssertLessThanOrEqual(
            completeBytes.count,
            BridgeProductionLimits.maximumEncodedEnvelopeBytes
        )
        guard case let .reminder(decodedComplete) = try AppleSourceEnvelopeCodec.decode(
            completeBytes
        ).snapshot else {
            return XCTFail("Expected decoded Reminder snapshot")
        }
        XCTAssertEqual(decodedComplete.matchedCount, 945)
        XCTAssertEqual(decodedComplete.records.count, 945)
        XCTAssertFalse(decodedComplete.truncated)

        let oversized = try AppleSourceConverter.reminderSnapshot(
            from: makeSource(1_001),
            bridgeId: "synthetic-bridge",
            capturedAt: capturedAt
        )
        guard case let .reminder(oversizedSnapshot) = oversized else {
            return XCTFail("Expected Reminder snapshot")
        }
        XCTAssertEqual(oversizedSnapshot.matchedCount, 1_001)
        XCTAssertEqual(oversizedSnapshot.records.count, 1_000)
        XCTAssertTrue(oversizedSnapshot.truncated)
        let oversizedBytes = try AppleSourceEnvelopeCodec.encodeWithinProductionLimit(
            sourceRevision: 2,
            snapshot: oversized
        )
        XCTAssertLessThanOrEqual(
            oversizedBytes.count,
            BridgeProductionLimits.maximumEncodedEnvelopeBytes
        )
        guard case let .reminder(decodedOversized) = try AppleSourceEnvelopeCodec.decode(
            oversizedBytes
        ).snapshot else {
            return XCTFail("Expected decoded Reminder snapshot")
        }
        XCTAssertEqual(decodedOversized.matchedCount, 1_001)
        XCTAssertEqual(decodedOversized.records.count, 1_000)
        XCTAssertTrue(decodedOversized.truncated)
    }

    func testCalendarWindowPolicyUsesExactSevenAndFortyFiveDayConstants() throws {
        let zone = TimeZone(identifier: "Etc/UTC")!
        let now = date("2026-08-23T18:00:00Z")
        let window = try CalendarWindowPolicy.window(now: now, timeZone: zone)
        XCTAssertEqual(window.start, date("2026-08-16T18:00:00Z"))
        XCTAssertEqual(window.end, date("2026-10-07T18:00:00Z"))
        XCTAssertEqual(BridgeProductionLimits.calendarDaysBehind, 7)
        XCTAssertEqual(BridgeProductionLimits.calendarDaysAhead, 45)
    }

    func testSelectionsDefaultEmptyAndRemainIndependent() {
        var state = BridgePersistentState.fresh(bridgeId: "synthetic-bridge")
        XCTAssertTrue(state.selectedCalendarSourceIds.isEmpty)
        XCTAssertTrue(state.selectedReminderSourceIds.isEmpty)

        state.setSelections(["synthetic-calendar"], for: .calendar)
        XCTAssertEqual(state.selectedCalendarSourceIds, ["synthetic-calendar"])
        XCTAssertTrue(state.selectedReminderSourceIds.isEmpty)
    }

    func testProductionReaderDoesNotCollectExcludedFieldsOrMutateEventKit() throws {
        let testURL = URL(fileURLWithPath: #filePath)
        let sourceURL = testURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("DeskboardAppleBridge/EventKitBridgeReader.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        for forbidden in [
            ".notes", ".url", ".location", ".structuredLocation", ".attendees",
            ".organizer", ".alarms", ".recurrenceRules", ".creationDate",
            ".lastModifiedDate", ".save(", ".remove(",
        ] {
            XCTAssertFalse(source.contains(forbidden))
        }
    }

    private func calendarRecord(
        id: String,
        temporal: CalendarRecordTemporalRead
    ) -> CalendarRecordRead {
        CalendarRecordRead(
            localIdentifier: id,
            eventIdentifier: nil,
            externalIdentifier: nil,
            title: "Synthetic",
            temporal: temporal,
            occurrenceDate: nil,
            isDetached: false,
            status: .confirmed
        )
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
