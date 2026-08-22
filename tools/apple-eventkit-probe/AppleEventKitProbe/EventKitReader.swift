import EventKit
import Foundation

enum ProbeReadBounds {
    static let calendarDaysBefore = 7
    static let calendarDaysAfter = 45
    static let maximumRecordsPerEntity = 200
}

struct ProbeReadBatch<Record> {
    let records: [Record]
    let matchedCount: Int

    var wasTruncated: Bool { matchedCount > records.count }
}

struct ProbeEventOrderKey: Comparable {
    let startDate: Date
    let endDate: Date
    let containerIdentifier: String
    let calendarItemIdentifier: String
    let eventIdentifier: String

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.startDate != rhs.startDate {
            return lhs.startDate < rhs.startDate
        }
        if lhs.endDate != rhs.endDate {
            return lhs.endDate < rhs.endDate
        }
        if lhs.containerIdentifier != rhs.containerIdentifier {
            return lhs.containerIdentifier < rhs.containerIdentifier
        }
        if lhs.calendarItemIdentifier != rhs.calendarItemIdentifier {
            return lhs.calendarItemIdentifier < rhs.calendarItemIdentifier
        }
        return lhs.eventIdentifier < rhs.eventIdentifier
    }
}

enum ProbeEventOrdering {
    static func orderedPrefix<Record>(
        _ records: [Record],
        maximumCount: Int,
        key: (Record) -> ProbeEventOrderKey
    ) -> [Record] {
        Array(records.sorted { key($0) < key($1) }.prefix(maximumCount))
    }
}

final class EventKitReader {
    private let eventStore: EKEventStore

    init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
    }

    func permissionState(for entityType: ProbeEntityType) -> ProbePermissionState {
        let eventKitType = eventKitEntityType(entityType)
        switch EKEventStore.authorizationStatus(for: eventKitType) {
        case .notDetermined:
            return .notDetermined
        case .fullAccess:
            return .granted
        case .denied:
            return .denied
        case .restricted, .writeOnly:
            return .unavailable
        @unknown default:
            return .unavailable
        }
    }

    func requestAccess(for entityType: ProbeEntityType) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            let completion: @Sendable (Bool, Error?) -> Void = { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }

            switch entityType {
            case .event:
                eventStore.requestFullAccessToEvents(completion: completion)
            case .reminder:
                eventStore.requestFullAccessToReminders(completion: completion)
            }
        }
    }

    func sources(for entityType: ProbeEntityType) -> [ProbeSourceDescriptor] {
        eventStore.calendars(for: eventKitEntityType(entityType))
            .map { calendar in
                ProbeSourceDescriptor(
                    id: calendar.calendarIdentifier,
                    entityType: entityType,
                    title: calendar.title,
                    calendarType: Self.calendarType(calendar.type),
                    sourceType: Self.sourceType(calendar.source.sourceType),
                    allowsContentModifications: calendar.allowsContentModifications,
                    isSubscribed: calendar.isSubscribed
                )
            }
            .sorted {
                let titleComparison = $0.title.localizedStandardCompare($1.title)
                if titleComparison == .orderedSame {
                    return $0.id < $1.id
                }
                return titleComparison == .orderedAscending
            }
    }

    func readReminders(
        selectedIdentifiers: Set<String>
    ) async -> ProbeReadBatch<ReminderProbeRecord> {
        let calendars = selectedCalendars(
            for: .reminder,
            identifiers: selectedIdentifiers
        )
        guard !calendars.isEmpty else {
            return ProbeReadBatch(records: [], matchedCount: 0)
        }

        let predicate = eventStore.predicateForReminders(in: calendars)
        let reminders: [EKReminder] = await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { fetched in
                continuation.resume(returning: fetched ?? [])
            }
        }
        let sorted = reminders.sorted {
            $0.calendarItemIdentifier < $1.calendarItemIdentifier
        }
        let bounded = sorted.prefix(ProbeReadBounds.maximumRecordsPerEntity)
        return ProbeReadBatch(
            records: bounded.map(Self.reminderRecord),
            matchedCount: sorted.count
        )
    }

    func readEvents(
        selectedIdentifiers: Set<String>,
        now: Date = Date()
    ) -> (batch: ProbeReadBatch<EventProbeRecord>, window: ProbeReadWindow) {
        let range = calendarRange(now: now)
        let calendars = selectedCalendars(for: .event, identifiers: selectedIdentifiers)
        guard !calendars.isEmpty else {
            return (ProbeReadBatch(records: [], matchedCount: 0), range.window)
        }

        let predicate = eventStore.predicateForEvents(
            withStart: range.start,
            end: range.end,
            calendars: calendars
        )
        let events = eventStore.events(matching: predicate)
        let bounded = ProbeEventOrdering.orderedPrefix(
            events,
            maximumCount: ProbeReadBounds.maximumRecordsPerEntity
        ) { event in
            ProbeEventOrderKey(
                startDate: event.startDate,
                endDate: event.endDate,
                containerIdentifier: event.calendar.calendarIdentifier,
                calendarItemIdentifier: event.calendarItemIdentifier,
                eventIdentifier: event.eventIdentifier ?? ""
            )
        }
        return (
            ProbeReadBatch(
                records: bounded.map(Self.eventRecord),
                matchedCount: events.count
            ),
            range.window
        )
    }

    func emptyReadWindow(now: Date = Date()) -> ProbeReadWindow {
        calendarRange(now: now).window
    }

    private func selectedCalendars(
        for entityType: ProbeEntityType,
        identifiers: Set<String>
    ) -> [EKCalendar] {
        guard !identifiers.isEmpty else { return [] }
        return eventStore.calendars(for: eventKitEntityType(entityType)).filter {
            identifiers.contains($0.calendarIdentifier)
        }
    }

    private func eventKitEntityType(_ entityType: ProbeEntityType) -> EKEntityType {
        switch entityType {
        case .event: .event
        case .reminder: .reminder
        }
    }

    private func calendarRange(now: Date) -> (start: Date, end: Date, window: ProbeReadWindow) {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(
            byAdding: .day,
            value: -ProbeReadBounds.calendarDaysBefore,
            to: now
        )!
        let end = calendar.date(
            byAdding: .day,
            value: ProbeReadBounds.calendarDaysAfter,
            to: now
        )!
        let window = ProbeReadWindow(
            daysBefore: ProbeReadBounds.calendarDaysBefore,
            daysAfter: ProbeReadBounds.calendarDaysAfter,
            start: InstantFormatter.string(from: start)!,
            end: InstantFormatter.string(from: end)!
        )
        return (start, end, window)
    }

    private static func reminderRecord(_ reminder: EKReminder) -> ReminderProbeRecord {
        var warnings: [String] = []
        let start = normalizedReminderTemporal(
            reminder.startDateComponents,
            field: "start",
            warnings: &warnings
        )
        let due = normalizedReminderTemporal(
            reminder.dueDateComponents,
            field: "due",
            warnings: &warnings
        )

        return ReminderProbeRecord(
            localIdentifier: reminder.calendarItemIdentifier,
            externalIdentifier: reminder.calendarItemExternalIdentifier,
            container: container(reminder.calendar),
            title: reminder.title,
            notes: reminder.notes,
            creationDate: InstantFormatter.string(from: reminder.creationDate),
            lastModifiedDate: InstantFormatter.string(from: reminder.lastModifiedDate),
            start: start,
            due: due,
            isCompleted: reminder.isCompleted,
            completionDate: InstantFormatter.string(from: reminder.completionDate),
            priority: Int(reminder.priority),
            recurrences: recurrences(reminder.recurrenceRules),
            alarmCount: reminder.alarms?.count ?? 0,
            url: reminder.url?.absoluteString,
            location: reminder.location,
            metadataBlock: MetadataBlockDetector.inspect(reminder.notes),
            normalizationWarnings: warnings
        )
    }

    private static func eventRecord(_ event: EKEvent) -> EventProbeRecord {
        EventProbeRecord(
            localIdentifier: event.calendarItemIdentifier,
            eventIdentifier: event.eventIdentifier,
            externalIdentifier: event.calendarItemExternalIdentifier,
            container: container(event.calendar),
            title: event.title,
            notes: event.notes,
            creationDate: InstantFormatter.string(from: event.creationDate),
            lastModifiedDate: InstantFormatter.string(from: event.lastModifiedDate),
            temporal: TemporalNormalizer.event(
                start: event.startDate,
                end: event.endDate,
                timeZone: event.timeZone,
                isAllDay: event.isAllDay
            ),
            isAllDay: event.isAllDay,
            occurrenceDate: InstantFormatter.string(from: event.occurrenceDate),
            isDetached: event.isDetached,
            status: eventStatus(event.status),
            availability: eventAvailability(event.availability),
            recurrences: recurrences(event.recurrenceRules),
            alarmCount: event.alarms?.count ?? 0,
            url: event.url?.absoluteString,
            location: event.location,
            structuredLocationPresent: event.structuredLocation != nil,
            organizerPresent: event.organizer != nil,
            attendeeCount: event.attendees?.count ?? 0,
            normalizationWarnings: []
        )
    }

    private static func normalizedReminderTemporal(
        _ components: DateComponents?,
        field: String,
        warnings: inout [String]
    ) -> ProbeReminderTemporal? {
        do {
            return try TemporalNormalizer.reminderComponents(components)
        } catch let error as TemporalNormalizationError {
            warnings.append("\(field)-\(error.errorDescription ?? "unsupported")")
            return nil
        } catch {
            warnings.append("\(field)-unsupported")
            return nil
        }
    }

    private static func container(_ calendar: EKCalendar) -> ProbeContainer {
        ProbeContainer(
            identifier: calendar.calendarIdentifier,
            title: calendar.title,
            calendarType: calendarType(calendar.type),
            sourceIdentifier: calendar.source.sourceIdentifier,
            sourceTitle: calendar.source.title,
            sourceType: sourceType(calendar.source.sourceType),
            allowsContentModifications: calendar.allowsContentModifications,
            isSubscribed: calendar.isSubscribed
        )
    }

    private static func recurrences(_ rules: [EKRecurrenceRule]?) -> [ProbeRecurrence]? {
        guard let rules, !rules.isEmpty else { return nil }
        return rules.map { rule in
            let recurrenceEnd: ProbeRecurrenceEnd?
            if let end = rule.recurrenceEnd {
                recurrenceEnd = ProbeRecurrenceEnd(
                    kind: end.endDate == nil ? "occurrenceCount" : "endDate",
                    occurrenceCount: end.occurrenceCount == 0 ? nil : end.occurrenceCount,
                    endDate: InstantFormatter.string(from: end.endDate)
                )
            } else {
                recurrenceEnd = nil
            }

            return ProbeRecurrence(
                calendarIdentifier: rule.calendarIdentifier,
                frequency: recurrenceFrequency(rule.frequency),
                interval: rule.interval,
                firstDayOfWeek: rule.firstDayOfTheWeek,
                daysOfWeek: rule.daysOfTheWeek?.map {
                    ProbeRecurrenceDay(
                        dayOfWeek: $0.dayOfTheWeek.rawValue,
                        weekNumber: $0.weekNumber
                    )
                },
                daysOfMonth: rule.daysOfTheMonth?.map(\.intValue),
                daysOfYear: rule.daysOfTheYear?.map(\.intValue),
                weeksOfYear: rule.weeksOfTheYear?.map(\.intValue),
                monthsOfYear: rule.monthsOfTheYear?.map(\.intValue),
                setPositions: rule.setPositions?.map(\.intValue),
                end: recurrenceEnd
            )
        }
    }

    private static func recurrenceFrequency(_ frequency: EKRecurrenceFrequency) -> String {
        switch frequency {
        case .daily: "daily"
        case .weekly: "weekly"
        case .monthly: "monthly"
        case .yearly: "yearly"
        @unknown default: "unknown"
        }
    }

    private static func calendarType(_ type: EKCalendarType) -> String {
        switch type {
        case .local: "local"
        case .calDAV: "calDAV"
        case .exchange: "exchange"
        case .subscription: "subscription"
        case .birthday: "birthday"
        @unknown default: "unknown"
        }
    }

    private static func sourceType(_ type: EKSourceType) -> String {
        switch type {
        case .local: "local"
        case .exchange: "exchange"
        case .calDAV: "calDAV"
        case .mobileMe: "mobileMe"
        case .subscribed: "subscribed"
        case .birthdays: "birthdays"
        @unknown default: "unknown"
        }
    }

    private static func eventStatus(_ status: EKEventStatus) -> String {
        switch status {
        case .none: "none"
        case .confirmed: "confirmed"
        case .tentative: "tentative"
        case .canceled: "canceled"
        @unknown default: "unknown"
        }
    }

    private static func eventAvailability(_ availability: EKEventAvailability) -> String {
        switch availability {
        case .notSupported: "notSupported"
        case .busy: "busy"
        case .free: "free"
        case .tentative: "tentative"
        case .unavailable: "unavailable"
        @unknown default: "unknown"
        }
    }
}
