import Foundation
import XCTest
@testable import AppleEventKitProbe

final class TemporalNormalizerTests: XCTestCase {
    func testDateOnlyReminderRemainsDateOnly() throws {
        let components = DateComponents(year: 2026, month: 9, day: 12)

        XCTAssertEqual(
            try TemporalNormalizer.reminderComponents(components),
            .dateOnly("2026-09-12")
        )
    }

    func testTimedReminderWithoutTimeZoneRemainsLocal() throws {
        let components = DateComponents(
            year: 2026,
            month: 9,
            day: 12,
            hour: 9,
            minute: 30
        )

        XCTAssertEqual(
            try TemporalNormalizer.reminderComponents(components),
            .localDateTime("2026-09-12T09:30:00")
        )
    }

    func testTimedReminderPreservesTimeZoneIdentity() throws {
        var components = DateComponents(
            year: 2026,
            month: 9,
            day: 12,
            hour: 9,
            minute: 30
        )
        components.timeZone = TimeZone(identifier: "America/Los_Angeles")

        XCTAssertEqual(
            try TemporalNormalizer.reminderComponents(components),
            .timeZoneDateTime(
                "2026-09-12T09:30:00",
                timeZone: "America/Los_Angeles"
            )
        )
    }

    func testMissingTemporalFieldRemainsAbsent() throws {
        XCTAssertNil(try TemporalNormalizer.reminderComponents(nil))
    }

    func testMalformedComponentsFailWithoutInventingValues() {
        XCTAssertThrowsError(
            try TemporalNormalizer.reminderComponents(
                DateComponents(year: 2026, month: 2, day: 30)
            )
        ) { error in
            XCTAssertEqual(error as? TemporalNormalizationError, .invalidDate)
        }
    }

    func testAllDayEventPreservesExclusiveMultiDayBoundary() throws {
        var calendar = Calendar(identifier: .gregorian)
        let timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        calendar.timeZone = timeZone
        let start = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 11, day: 6))
        )
        let end = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 11, day: 9))
        )

        XCTAssertEqual(
            TemporalNormalizer.event(
                start: start,
                end: end,
                timeZone: timeZone,
                isAllDay: true
            ),
            .allDayRange(startDate: "2026-11-06", endDate: "2026-11-09")
        )
    }

    func testTimedEventPreservesStartEndAndTimeZone() throws {
        var calendar = Calendar(identifier: .gregorian)
        let timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        calendar.timeZone = timeZone
        let start = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 9, minute: 30))
        )
        let end = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 11))
        )

        XCTAssertEqual(
            TemporalNormalizer.event(
                start: start,
                end: end,
                timeZone: timeZone,
                isAllDay: false
            ),
            .timeZoneDateTime(
                start: "2026-11-06T09:30:00",
                end: "2026-11-06T11:00:00",
                timeZone: "America/Los_Angeles"
            )
        )
    }
}

final class SourceSelectionStoreTests: XCTestCase {
    func testSelectionsAreSeparateAndPersisted() {
        let preferences = InMemoryPreferenceStore()
        let store = SourceSelectionStore(preferences: preferences)

        XCTAssertEqual(store.selectedIdentifiers(for: .event), [])
        XCTAssertEqual(store.selectedIdentifiers(for: .reminder), [])

        store.save(["calendar-b", "calendar-a"], for: .event)
        store.save(["list-a"], for: .reminder)

        XCTAssertEqual(store.selectedIdentifiers(for: .event), ["calendar-a", "calendar-b"])
        XCTAssertEqual(store.selectedIdentifiers(for: .reminder), ["list-a"])
        XCTAssertEqual(
            preferences.values[SourceSelectionStore.calendarKey] as? [String],
            ["calendar-a", "calendar-b"]
        )
    }

    func testDisappearedSourceIsRemovedWithoutAffectingOtherEntity() {
        let preferences = InMemoryPreferenceStore()
        let store = SourceSelectionStore(preferences: preferences)
        store.save(["calendar-present", "calendar-gone"], for: .event)
        store.save(["list-present"], for: .reminder)

        let reconciled = store.reconcile(
            selectedIdentifiers: store.selectedIdentifiers(for: .event),
            availableIdentifiers: ["calendar-present"],
            for: .event
        )

        XCTAssertEqual(reconciled, ["calendar-present"])
        XCTAssertEqual(store.selectedIdentifiers(for: .event), ["calendar-present"])
        XCTAssertEqual(store.selectedIdentifiers(for: .reminder), ["list-present"])
    }
}

final class SafeProbeCommandTests: XCTestCase {
    func testCommandParsingIsExplicitAndDeterministic() throws {
        XCTAssertEqual(try ProbeCommandLine.parse([]), nil)
        XCTAssertEqual(
            try ProbeCommandLine.parse(["-ApplePersistenceIgnoreState", "YES"]),
            nil
        )
        XCTAssertEqual(try ProbeCommandLine.parse(["--safe-status"]), .status)
        XCTAssertEqual(
            try ProbeCommandLine.parse(["--safe-request-calendar"]),
            .requestCalendar
        )
        XCTAssertEqual(
            try ProbeCommandLine.parse(["--safe-request-reminders"]),
            .requestReminders
        )
        XCTAssertEqual(try ProbeCommandLine.parse(["--safe-sources"]), .sources)
        XCTAssertEqual(try ProbeCommandLine.parse(["--safe-inspect"]), .inspect)
        XCTAssertEqual(
            try ProbeCommandLine.parse(["--private-export-confirmed"]),
            .privateExportConfirmed
        )
        XCTAssertEqual(
            try ProbeCommandLine.parse(["--safe-select-calendar=3,1"]),
            .selectCalendar([1, 3])
        )
        XCTAssertEqual(
            try ProbeCommandLine.parse(["--safe-select-reminders="]),
            .selectReminders([])
        )
        XCTAssertThrowsError(
            try ProbeCommandLine.parse(["--safe-select-calendar=1,1"])
        )
        XCTAssertThrowsError(try ProbeCommandLine.parse(["--safe-unknown"]))
        XCTAssertThrowsError(try ProbeCommandLine.parse(["--private-unknown"]))
    }

    func testSafeSourceReportOmitsPrivateTitlesAndIdentifiers() throws {
        let source = ProbeSourceDescriptor(
            id: "private-calendar-identifier",
            entityType: .event,
            title: "private-calendar-title",
            calendarType: "calDAV",
            sourceType: "calDAV",
            allowsContentModifications: true,
            isSubscribed: false
        )

        let summaries = SafeProbeEvidence.sourceSummaries(
            [source],
            selectedIdentifiers: [source.id]
        )
        let encoded = String(decoding: try JSONEncoder().encode(summaries), as: UTF8.self)

        XCTAssertEqual(summaries.first?.ordinal, 1)
        XCTAssertEqual(summaries.first?.isSelected, true)
        XCTAssertFalse(encoded.contains(source.id))
        XCTAssertFalse(encoded.contains(source.title))
    }

    func testOrdinalSelectionRejectsMissingAndDuplicateSources() throws {
        let sources = [
            ProbeSourceDescriptor(
                id: "private-calendar-a",
                entityType: .event,
                title: "Private A",
                calendarType: "local",
                sourceType: "local",
                allowsContentModifications: true,
                isSubscribed: false
            ),
            ProbeSourceDescriptor(
                id: "private-calendar-b",
                entityType: .event,
                title: "Private B",
                calendarType: "subscription",
                sourceType: "subscribed",
                allowsContentModifications: false,
                isSubscribed: true
            ),
        ]

        XCTAssertEqual(
            try SafeProbeEvidence.identifiers(for: [2], in: sources),
            ["private-calendar-b"]
        )
        XCTAssertThrowsError(
            try SafeProbeEvidence.identifiers(for: [0], in: sources)
        )
        XCTAssertThrowsError(
            try SafeProbeEvidence.identifiers(for: [1, 1], in: sources)
        )
    }
}

final class MetadataBlockDetectorTests: XCTestCase {
    func testPairedBlockPreservesPresenceOfSurroundingProse() throws {
        let observation = try XCTUnwrap(
            MetadataBlockDetector.inspect(
                """
                Prose before.
                [deskboard:v1]
                kind: task
                [/deskboard]
                Prose after.
                """
            )
        )

        XCTAssertTrue(observation.pairedBlockPresent)
        XCTAssertTrue(observation.proseBeforePresent)
        XCTAssertTrue(observation.proseAfterPresent)
        XCTAssertFalse(observation.malformed)
    }

    func testMalformedAndUnsupportedDelimitersAreDetectedWithoutParsing() throws {
        let malformed = try XCTUnwrap(
            MetadataBlockDetector.inspect("[deskboard:v1]\nkind: task")
        )
        let unsupported = try XCTUnwrap(
            MetadataBlockDetector.inspect("[deskboard:v2]\nkind: task\n[/deskboard]")
        )

        XCTAssertTrue(malformed.malformed)
        XCTAssertFalse(malformed.pairedBlockPresent)
        XCTAssertTrue(unsupported.unsupportedVersionDelimiterPresent)
        XCTAssertTrue(unsupported.malformed)
    }
}

final class ProbeExportLocationTests: XCTestCase {
    func testExportLocationRequiresRepositoryIgnoreBoundary() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("eventkit-export-location-\(UUID().uuidString)")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        XCTAssertThrowsError(
            try ProbeExportLocations.resolve(
                environment: ["DESKBOARD_REPOSITORY_ROOT": root.path],
                currentDirectory: "/",
                fileManager: fileManager
            )
        )

        try "private-fixtures/\n".write(
            to: root.appendingPathComponent(".gitignore"),
            atomically: true,
            encoding: .utf8
        )
        let locations = try ProbeExportLocations.resolve(
            environment: ["DESKBOARD_REPOSITORY_ROOT": root.path],
            currentDirectory: "/",
            fileManager: fileManager
        )

        XCTAssertEqual(
            locations.privateRoot.path,
            root.appendingPathComponent("private-fixtures/eventkit-probe").path
        )
    }

    func testSanitizedGenerationRemovesOnlyPriorCandidateJSON() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("eventkit-candidate-cleanup-\(UUID().uuidString)")
        let candidateDirectory = root.appendingPathComponent("sanitized-candidates")
        try fileManager.createDirectory(at: candidateDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let staleCandidate = candidateDirectory.appendingPathComponent("event-candidate-999.json")
        let reviewNotes = candidateDirectory.appendingPathComponent("review-notes.txt")
        try Data("stale".utf8).write(to: staleCandidate)
        try Data("keep".utf8).write(to: reviewNotes)

        let inspection = ProbeInspection(
            generatedAt: "2026-08-21T17:00:00.000Z",
            calendarReadWindow: ProbeReadWindow(
                daysBefore: 7,
                daysAfter: 45,
                start: "2026-08-14T17:00:00.000Z",
                end: "2026-10-05T17:00:00.000Z"
            ),
            reminderResultCount: 0,
            reminderResultsTruncated: false,
            eventResultCount: 0,
            eventResultsTruncated: false,
            reminders: [],
            events: []
        )
        let exporter = try ProbeExporter(
            fileManager: fileManager,
            locations: ProbeExportLocations(privateRoot: root)
        )

        _ = try exporter.writeSanitizedCandidates(inspection)

        XCTAssertFalse(fileManager.fileExists(atPath: staleCandidate.path))
        XCTAssertTrue(fileManager.fileExists(atPath: reviewNotes.path))
    }
}

final class ProbeSanitizerTests: XCTestCase {
    func testSanitizerReplacesEveryPrivateTextAndIdentifierField() throws {
        let privateInspection = makePrivateInspection()
        let sanitized = ProbeSanitizer.sanitize(privateInspection)
        let encoded = try String(
            decoding: JSONEncoder().encode(sanitized),
            as: UTF8.self
        )

        let privateValues = [
            "private-reminder-id",
            "private-reminder-external",
            "private-reminder-title",
            "private reminder prose",
            "private-list-id",
            "private-list-title",
            "private-source-id",
            "private-source-title",
            "private-reminder-url",
            "private-reminder-location",
            "private-reminder-calendar-id",
            "private-event-id",
            "private-event-occurrence-id",
            "private-event-external",
            "private-event-title",
            "private event notes",
            "private-calendar-id",
            "private-calendar-title",
            "private-event-url",
            "private-event-location",
            "private-event-calendar-id",
            "2031-04-03",
            "Europe/Private",
            "private warning",
        ]
        for value in privateValues {
            XCTAssertFalse(encoded.contains(value), "Sanitized output retained a private field")
        }

        XCTAssertEqual(sanitized.reminders[0].title, "Synthetic Reminder A")
        XCTAssertEqual(sanitized.events[0].title, "Synthetic Event A")
        XCTAssertEqual(sanitized.events[0].location, "Example Location")
        XCTAssertEqual(sanitized.reminders[0].container.title, "Synthetic Reminder List A")
        XCTAssertEqual(sanitized.events[0].container.title, "Synthetic Calendar A")
        XCTAssertTrue(sanitized.reminders[0].notes?.contains("[deskboard:v1]") == true)

        let safeReport = SafeProbeEvidence.inspectionReport(
            inspection: privateInspection,
            permissions: SafePermissionReport(calendar: .granted, reminders: .granted)
        )
        let reportText = String(
            decoding: try JSONEncoder().encode(safeReport),
            as: UTF8.self
        )
        for value in privateValues {
            XCTAssertFalse(reportText.contains(value), "Safe report retained a private field")
        }
        XCTAssertEqual(
            safeReport.candidateDirectory,
            "private-fixtures/eventkit-probe/sanitized-candidates"
        )
        XCTAssertTrue(safeReport.events[0].startDatePresent)
        XCTAssertTrue(safeReport.events[0].endDatePresent)
        XCTAssertFalse(safeReport.events[0].startLocalDateTimePresent)
        XCTAssertFalse(safeReport.events[0].endLocalDateTimePresent)
    }

    func testSanitizerIsDeterministic() {
        let first = ProbeSanitizer.sanitize(makePrivateInspection())
        let second = ProbeSanitizer.sanitize(makePrivateInspection())

        XCTAssertEqual(first, second)
    }

    func testEventSanitizerPreservesTimedDurationWithoutPrivateValues() throws {
        var privateInspection = makePrivateInspection()
        privateInspection.events[0].temporal = .timeZoneDateTime(
            start: "2031-04-03T09:30:00",
            end: "2031-04-03T11:00:00",
            timeZone: "Europe/Private"
        )

        let temporal = ProbeSanitizer.sanitize(privateInspection).events[0].temporal

        XCTAssertEqual(temporal.kind, .timeZoneDateTime)
        XCTAssertEqual(temporal.startLocalDateTime, "2026-09-11T09:30:00")
        XCTAssertEqual(temporal.endLocalDateTime, "2026-09-11T11:00:00")
        XCTAssertEqual(temporal.timeZone, "America/Los_Angeles")
        let encoded = String(decoding: try JSONEncoder().encode(temporal), as: UTF8.self)
        XCTAssertFalse(encoded.contains("2031-04-03"))
        XCTAssertFalse(encoded.contains("Europe/Private"))

        let report = SafeProbeEvidence.inspectionReport(
            inspection: privateInspection,
            permissions: SafePermissionReport(calendar: .granted, reminders: .granted)
        )
        XCTAssertTrue(report.events[0].startLocalDateTimePresent)
        XCTAssertTrue(report.events[0].endLocalDateTimePresent)
        XCTAssertTrue(report.events[0].timeZonePresent)
    }

    private func makePrivateInspection() -> ProbeInspection {
        let metadata = MetadataBlockDetector.inspect(
            "private reminder prose\n[deskboard:v1]\nkind: task\n[/deskboard]\nprivate tail"
        )
        let reminderContainer = ProbeContainer(
            identifier: "private-list-id",
            title: "private-list-title",
            calendarType: "calDAV",
            sourceIdentifier: "private-source-id",
            sourceTitle: "private-source-title",
            sourceType: "calDAV",
            allowsContentModifications: true,
            isSubscribed: false
        )
        let eventContainer = ProbeContainer(
            identifier: "private-calendar-id",
            title: "private-calendar-title",
            calendarType: "subscription",
            sourceIdentifier: "private-source-id",
            sourceTitle: "private-source-title",
            sourceType: "subscribed",
            allowsContentModifications: false,
            isSubscribed: true
        )
        let recurrenceEnd = ProbeRecurrenceEnd(
            kind: "endDate",
            occurrenceCount: nil,
            endDate: "2031-04-03T16:00:00.000Z"
        )
        let reminderRecurrence = ProbeRecurrence(
            calendarIdentifier: "private-reminder-calendar-id",
            frequency: "weekly",
            interval: 1,
            firstDayOfWeek: 2,
            daysOfWeek: [ProbeRecurrenceDay(dayOfWeek: 2, weekNumber: 0)],
            daysOfMonth: nil,
            daysOfYear: nil,
            weeksOfYear: nil,
            monthsOfYear: nil,
            setPositions: nil,
            end: recurrenceEnd
        )
        let eventRecurrence = ProbeRecurrence(
            calendarIdentifier: "private-event-calendar-id",
            frequency: "monthly",
            interval: 1,
            firstDayOfWeek: 0,
            daysOfWeek: nil,
            daysOfMonth: [3],
            daysOfYear: nil,
            weeksOfYear: nil,
            monthsOfYear: nil,
            setPositions: nil,
            end: nil
        )
        let reminder = ReminderProbeRecord(
            localIdentifier: "private-reminder-id",
            externalIdentifier: "private-reminder-external",
            container: reminderContainer,
            title: "private-reminder-title",
            notes: "private reminder prose",
            creationDate: "2031-04-01T16:00:00.000Z",
            lastModifiedDate: "2031-04-02T16:00:00.000Z",
            start: .dateOnly("2031-04-03"),
            due: .timeZoneDateTime(
                "2031-04-03T09:30:00",
                timeZone: "Europe/Private"
            ),
            isCompleted: true,
            completionDate: "2031-04-03T17:00:00.000Z",
            priority: 1,
            recurrences: [reminderRecurrence],
            alarmCount: 1,
            url: "https://private-reminder-url.invalid/value",
            location: "private-reminder-location",
            metadataBlock: metadata,
            normalizationWarnings: ["private warning"]
        )
        let event = EventProbeRecord(
            localIdentifier: "private-event-id",
            eventIdentifier: "private-event-occurrence-id",
            externalIdentifier: "private-event-external",
            container: eventContainer,
            title: "private-event-title",
            notes: "private event notes",
            creationDate: "2031-04-01T16:00:00.000Z",
            lastModifiedDate: "2031-04-02T16:00:00.000Z",
            temporal: .allDayRange(startDate: "2031-04-03", endDate: "2031-04-05"),
            isAllDay: true,
            occurrenceDate: "2031-04-03T07:00:00.000Z",
            isDetached: false,
            status: "confirmed",
            availability: "free",
            recurrences: [eventRecurrence],
            alarmCount: 0,
            url: "https://private-event-url.invalid/value",
            location: "private-event-location",
            structuredLocationPresent: true,
            organizerPresent: true,
            attendeeCount: 2,
            normalizationWarnings: ["private warning"]
        )
        return ProbeInspection(
            generatedAt: "2031-04-03T16:00:00.000Z",
            calendarReadWindow: ProbeReadWindow(
                daysBefore: 7,
                daysAfter: 45,
                start: "2031-03-27T16:00:00.000Z",
                end: "2031-05-18T16:00:00.000Z"
            ),
            reminderResultCount: 1,
            reminderResultsTruncated: false,
            eventResultCount: 1,
            eventResultsTruncated: false,
            reminders: [reminder],
            events: [event]
        )
    }
}

private final class InMemoryPreferenceStore: PreferenceStore {
    var values: [String: Any] = [:]

    func stringArray(forKey defaultName: String) -> [String]? {
        values[defaultName] as? [String]
    }

    func set(_ value: Any?, forKey defaultName: String) {
        values[defaultName] = value
    }
}
