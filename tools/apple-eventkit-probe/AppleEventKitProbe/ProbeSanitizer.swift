import Foundation

enum ProbeSanitizer {
    static func sanitize(_ inspection: ProbeInspection) -> ProbeInspection {
        var reminderContainerOrdinals: [String: Int] = [:]
        var eventContainerOrdinals: [String: Int] = [:]
        var sourceOrdinals: [String: Int] = [:]

        let reminders = inspection.reminders.enumerated().map { index, record in
            sanitizeReminder(
                record,
                index: index,
                containerOrdinals: &reminderContainerOrdinals,
                sourceOrdinals: &sourceOrdinals
            )
        }
        let events = inspection.events.enumerated().map { index, record in
            sanitizeEvent(
                record,
                index: index,
                containerOrdinals: &eventContainerOrdinals,
                sourceOrdinals: &sourceOrdinals
            )
        }

        return ProbeInspection(
            schemaVersion: inspection.schemaVersion,
            generatedAt: "2026-08-21T17:00:00.000Z",
            calendarReadWindow: ProbeReadWindow(
                daysBefore: inspection.calendarReadWindow.daysBefore,
                daysAfter: inspection.calendarReadWindow.daysAfter,
                start: "2026-08-14T17:00:00.000Z",
                end: "2026-10-05T17:00:00.000Z"
            ),
            reminderResultCount: reminders.count,
            reminderResultsTruncated: inspection.reminderResultsTruncated,
            eventResultCount: events.count,
            eventResultsTruncated: inspection.eventResultsTruncated,
            reminders: reminders,
            events: events
        )
    }

    private static func sanitizeReminder(
        _ input: ReminderProbeRecord,
        index: Int,
        containerOrdinals: inout [String: Int],
        sourceOrdinals: inout [String: Int]
    ) -> ReminderProbeRecord {
        let ordinal = index + 1
        var output = input
        output.localIdentifier = identifier("synthetic-reminder", ordinal)
        output.externalIdentifier = input.externalIdentifier.map { _ in
            identifier("synthetic-reminder-external", ordinal)
        }
        output.container = sanitizeContainer(
            input.container,
            entityType: .reminder,
            containerOrdinals: &containerOrdinals,
            sourceOrdinals: &sourceOrdinals
        )
        output.title = input.title.map { _ in "Synthetic Reminder \(letter(ordinal))" }
        output.notes = sanitizeNotes(input.notes, metadata: input.metadataBlock)
        output.creationDate = replacementInstant(input.creationDate, offset: ordinal)
        output.lastModifiedDate = replacementInstant(input.lastModifiedDate, offset: ordinal + 10)
        output.start = input.start.map { sanitizeTemporal($0, ordinal: ordinal, secondary: false) }
        output.due = input.due.map { sanitizeTemporal($0, ordinal: ordinal, secondary: true) }
        output.completionDate = replacementInstant(input.completionDate, offset: ordinal + 20)
        output.recurrences = sanitizeRecurrences(input.recurrences, prefix: "synthetic-reminder-calendar")
        output.url = input.url.map { _ in "https://example.invalid/reminders/\(padded(ordinal))" }
        output.location = input.location.map { _ in "Example Location" }
        output.normalizationWarnings = input.normalizationWarnings.map { _ in "synthetic-normalization-warning" }
        return output
    }

    private static func sanitizeEvent(
        _ input: EventProbeRecord,
        index: Int,
        containerOrdinals: inout [String: Int],
        sourceOrdinals: inout [String: Int]
    ) -> EventProbeRecord {
        let ordinal = index + 1
        var output = input
        output.localIdentifier = identifier("synthetic-event", ordinal)
        output.eventIdentifier = input.eventIdentifier.map { _ in
            identifier("synthetic-event-occurrence", ordinal)
        }
        output.externalIdentifier = input.externalIdentifier.map { _ in
            identifier("synthetic-event-external", ordinal)
        }
        output.container = sanitizeContainer(
            input.container,
            entityType: .event,
            containerOrdinals: &containerOrdinals,
            sourceOrdinals: &sourceOrdinals
        )
        output.title = input.title.map { _ in "Synthetic Event \(letter(ordinal))" }
        output.notes = input.notes.map { _ in "Synthetic event notes." }
        output.creationDate = replacementInstant(input.creationDate, offset: ordinal)
        output.lastModifiedDate = replacementInstant(input.lastModifiedDate, offset: ordinal + 10)
        output.temporal = sanitizeTemporal(input.temporal, ordinal: ordinal, secondary: false)
        output.occurrenceDate = replacementInstant(input.occurrenceDate, offset: ordinal + 20)
        output.recurrences = sanitizeRecurrences(input.recurrences, prefix: "synthetic-event-calendar")
        output.url = input.url.map { _ in "https://example.invalid/events/\(padded(ordinal))" }
        output.location = input.location.map { _ in "Example Location" }
        output.normalizationWarnings = input.normalizationWarnings.map { _ in "synthetic-normalization-warning" }
        return output
    }

    private static func sanitizeContainer(
        _ input: ProbeContainer,
        entityType: ProbeEntityType,
        containerOrdinals: inout [String: Int],
        sourceOrdinals: inout [String: Int]
    ) -> ProbeContainer {
        let containerOrdinal = stableOrdinal(for: input.identifier, in: &containerOrdinals)
        let sourceOrdinal = stableOrdinal(for: input.sourceIdentifier, in: &sourceOrdinals)
        let containerPrefix = entityType == .event ? "synthetic-calendar" : "synthetic-reminder-list"
        let titlePrefix = entityType == .event ? "Synthetic Calendar" : "Synthetic Reminder List"

        return ProbeContainer(
            identifier: identifier(containerPrefix, containerOrdinal),
            title: "\(titlePrefix) \(letter(containerOrdinal))",
            calendarType: input.calendarType,
            sourceIdentifier: identifier("synthetic-source", sourceOrdinal),
            sourceTitle: "Synthetic Account \(letter(sourceOrdinal))",
            sourceType: input.sourceType,
            allowsContentModifications: input.allowsContentModifications,
            isSubscribed: input.isSubscribed
        )
    }

    private static func sanitizeNotes(
        _ notes: String?,
        metadata: MetadataBlockObservation?
    ) -> String? {
        guard notes != nil else { return nil }
        if metadata?.pairedBlockPresent == true {
            return """
            Synthetic prose before.

            [deskboard:v1]
            kind: task
            project: synthetic-project
            [/deskboard]

            Synthetic prose after.
            """
        }
        return "Synthetic reminder notes."
    }

    private static func sanitizeTemporal(
        _ input: ProbeTemporal,
        ordinal: Int,
        secondary: Bool
    ) -> ProbeTemporal {
        let day = min(28, 10 + ordinal + (secondary ? 1 : 0))
        let date = String(format: "2026-09-%02d", day)
        switch input.kind {
        case .dateOnly:
            return .dateOnly(date)
        case .localDateTime:
            return .localDateTime("\(date)T09:30:00")
        case .timeZoneDateTime:
            return .timeZoneDateTime(
                "\(date)T09:30:00",
                timeZone: "America/Los_Angeles"
            )
        case .allDayRange:
            let duration = allDayDuration(input) ?? 1
            let calendar = Calendar(identifier: .gregorian)
            let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: day))!
            let end = calendar.date(byAdding: .day, value: duration, to: start)!
            return .allDayRange(
                startDate: dateOnlyString(start, calendar: calendar),
                endDate: dateOnlyString(end, calendar: calendar)
            )
        }
    }

    private static func allDayDuration(_ temporal: ProbeTemporal) -> Int? {
        guard
            let start = temporal.startDate,
            let end = temporal.endDate
        else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        guard let startDate = formatter.date(from: start), let endDate = formatter.date(from: end) else {
            return nil
        }
        return max(1, Calendar(identifier: .gregorian).dateComponents([.day], from: startDate, to: endDate).day ?? 1)
    }

    private static func sanitizeRecurrences(
        _ recurrences: [ProbeRecurrence]?,
        prefix: String
    ) -> [ProbeRecurrence]? {
        recurrences?.enumerated().map { index, recurrence in
            var output = recurrence
            output.calendarIdentifier = identifier(prefix, index + 1)
            if recurrence.end?.endDate != nil {
                output.end?.endDate = "2027-09-30T17:00:00.000Z"
            }
            return output
        }
    }

    private static func stableOrdinal(
        for privateIdentifier: String,
        in ordinals: inout [String: Int]
    ) -> Int {
        if let existing = ordinals[privateIdentifier] {
            return existing
        }
        let newValue = ordinals.count + 1
        ordinals[privateIdentifier] = newValue
        return newValue
    }

    private static func replacementInstant(_ input: String?, offset: Int) -> String? {
        guard input != nil else { return nil }
        let day = min(28, max(1, offset))
        return String(format: "2026-08-%02dT17:00:00.000Z", day)
    }

    private static func dateOnlyString(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private static func identifier(_ prefix: String, _ ordinal: Int) -> String {
        "\(prefix)-\(padded(ordinal))"
    }

    private static func padded(_ value: Int) -> String {
        String(format: "%03d", value)
    }

    private static func letter(_ ordinal: Int) -> String {
        guard (1 ... 26).contains(ordinal), let scalar = UnicodeScalar(64 + ordinal) else {
            return padded(ordinal)
        }
        return String(Character(scalar))
    }
}
