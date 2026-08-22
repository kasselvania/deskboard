import AppKit
import Foundation

enum ProbeCommand: Equatable {
    case status
    case requestCalendar
    case requestReminders
    case sources
    case selectCalendar([Int])
    case selectReminders([Int])
    case inspect
    case privateExportConfirmed
}

enum ProbeCommandError: Error {
    case invalidArguments
    case invalidOrdinal
    case permissionUnavailable
}

struct SafePermissionReport: Codable, Equatable {
    let calendar: ProbePermissionState
    let reminders: ProbePermissionState
}

struct SafeSourceSummary: Codable, Equatable {
    let ordinal: Int
    let entityType: ProbeEntityType
    let calendarType: String
    let sourceType: String
    let allowsContentModifications: Bool
    let isSubscribed: Bool
    let isSelected: Bool
}

struct SafeSourceReport: Codable, Equatable {
    let permissions: SafePermissionReport
    let calendars: [SafeSourceSummary]
    let reminderLists: [SafeSourceSummary]
}

struct SafeSelectionReport: Codable, Equatable {
    let entityType: ProbeEntityType
    let selectedOrdinals: [Int]
    let selectedCount: Int
}

struct SafeReminderShape: Codable, Equatable {
    let candidateFile: String
    let titlePresent: Bool
    let notesPresent: Bool
    let externalIdentifierPresent: Bool
    let creationDatePresent: Bool
    let modificationDatePresent: Bool
    let startKind: ProbeReminderTemporalKind?
    let dueKind: ProbeReminderTemporalKind?
    let isCompleted: Bool
    let completionDatePresent: Bool
    let priority: Int
    let recurrencePresent: Bool
    let alarmCount: Int
    let urlPresent: Bool
    let locationPresent: Bool
    let metadataBlock: MetadataBlockObservation?
    let sourceType: String
    let calendarType: String
    let sourceAllowsContentModifications: Bool
    let sourceIsSubscribed: Bool
    let normalizationWarningCount: Int
}

struct SafeEventShape: Codable, Equatable {
    let candidateFile: String
    let titlePresent: Bool
    let notesPresent: Bool
    let eventIdentifierPresent: Bool
    let externalIdentifierPresent: Bool
    let creationDatePresent: Bool
    let modificationDatePresent: Bool
    let temporalKind: ProbeEventTemporalKind
    let startLocalDateTimePresent: Bool
    let endLocalDateTimePresent: Bool
    let timeZonePresent: Bool
    let startDatePresent: Bool
    let endDatePresent: Bool
    let isAllDay: Bool
    let occurrenceDatePresent: Bool
    let isDetached: Bool
    let status: String
    let availability: String
    let recurrencePresent: Bool
    let alarmCount: Int
    let urlPresent: Bool
    let locationPresent: Bool
    let structuredLocationPresent: Bool
    let organizerPresent: Bool
    let attendeeCount: Int
    let sourceType: String
    let calendarType: String
    let sourceAllowsContentModifications: Bool
    let sourceIsSubscribed: Bool
    let normalizationWarningCount: Int
}

struct SafeInspectionReport: Codable, Equatable {
    let permissions: SafePermissionReport
    let calendarDaysBefore: Int
    let calendarDaysAfter: Int
    let reminderResultCount: Int
    let reminderResultsTruncated: Bool
    let eventResultCount: Int
    let eventResultsTruncated: Bool
    let reminders: [SafeReminderShape]
    let events: [SafeEventShape]
    let candidateDirectory: String
}

struct SafePrivateExportReport: Codable, Equatable {
    let reminderResultCount: Int
    let reminderResultsTruncated: Bool
    let eventResultCount: Int
    let eventResultsTruncated: Bool
    let destination: String
    let warning: String
}

enum SafeProbeEvidence {
    static func sourceSummaries(
        _ sources: [ProbeSourceDescriptor],
        selectedIdentifiers: Set<String>
    ) -> [SafeSourceSummary] {
        sources.enumerated().map { index, source in
            SafeSourceSummary(
                ordinal: index + 1,
                entityType: source.entityType,
                calendarType: source.calendarType,
                sourceType: source.sourceType,
                allowsContentModifications: source.allowsContentModifications,
                isSubscribed: source.isSubscribed,
                isSelected: selectedIdentifiers.contains(source.id)
            )
        }
    }

    static func identifiers(
        for ordinals: [Int],
        in sources: [ProbeSourceDescriptor]
    ) throws -> Set<String> {
        guard Set(ordinals).count == ordinals.count else {
            throw ProbeCommandError.invalidOrdinal
        }
        var identifiers: Set<String> = []
        for ordinal in ordinals {
            guard sources.indices.contains(ordinal - 1) else {
                throw ProbeCommandError.invalidOrdinal
            }
            identifiers.insert(sources[ordinal - 1].id)
        }
        return identifiers
    }

    static func inspectionReport(
        inspection: ProbeInspection,
        permissions: SafePermissionReport
    ) -> SafeInspectionReport {
        let sanitized = ProbeSanitizer.sanitize(inspection)
        return SafeInspectionReport(
            permissions: permissions,
            calendarDaysBefore: sanitized.calendarReadWindow.daysBefore,
            calendarDaysAfter: sanitized.calendarReadWindow.daysAfter,
            reminderResultCount: sanitized.reminderResultCount,
            reminderResultsTruncated: sanitized.reminderResultsTruncated,
            eventResultCount: sanitized.eventResultCount,
            eventResultsTruncated: sanitized.eventResultsTruncated,
            reminders: sanitized.reminders.enumerated().map { index, item in
                SafeReminderShape(
                    candidateFile: String(format: "reminder-candidate-%03d.json", index + 1),
                    titlePresent: item.title != nil,
                    notesPresent: item.notes != nil,
                    externalIdentifierPresent: item.externalIdentifier != nil,
                    creationDatePresent: item.creationDate != nil,
                    modificationDatePresent: item.lastModifiedDate != nil,
                    startKind: item.start?.kind,
                    dueKind: item.due?.kind,
                    isCompleted: item.isCompleted,
                    completionDatePresent: item.completionDate != nil,
                    priority: item.priority,
                    recurrencePresent: item.recurrences != nil,
                    alarmCount: item.alarmCount,
                    urlPresent: item.url != nil,
                    locationPresent: item.location != nil,
                    metadataBlock: item.metadataBlock,
                    sourceType: item.container.sourceType,
                    calendarType: item.container.calendarType,
                    sourceAllowsContentModifications: item.container.allowsContentModifications,
                    sourceIsSubscribed: item.container.isSubscribed,
                    normalizationWarningCount: item.normalizationWarnings.count
                )
            },
            events: sanitized.events.enumerated().map { index, item in
                SafeEventShape(
                    candidateFile: String(format: "event-candidate-%03d.json", index + 1),
                    titlePresent: item.title != nil,
                    notesPresent: item.notes != nil,
                    eventIdentifierPresent: item.eventIdentifier != nil,
                    externalIdentifierPresent: item.externalIdentifier != nil,
                    creationDatePresent: item.creationDate != nil,
                    modificationDatePresent: item.lastModifiedDate != nil,
                    temporalKind: item.temporal.kind,
                    startLocalDateTimePresent: item.temporal.startLocalDateTime != nil,
                    endLocalDateTimePresent: item.temporal.endLocalDateTime != nil,
                    timeZonePresent: item.temporal.timeZone != nil,
                    startDatePresent: item.temporal.startDate != nil,
                    endDatePresent: item.temporal.endDate != nil,
                    isAllDay: item.isAllDay,
                    occurrenceDatePresent: item.occurrenceDate != nil,
                    isDetached: item.isDetached,
                    status: item.status,
                    availability: item.availability,
                    recurrencePresent: item.recurrences != nil,
                    alarmCount: item.alarmCount,
                    urlPresent: item.url != nil,
                    locationPresent: item.location != nil,
                    structuredLocationPresent: item.structuredLocationPresent,
                    organizerPresent: item.organizerPresent,
                    attendeeCount: item.attendeeCount,
                    sourceType: item.container.sourceType,
                    calendarType: item.container.calendarType,
                    sourceAllowsContentModifications: item.container.allowsContentModifications,
                    sourceIsSubscribed: item.container.isSubscribed,
                    normalizationWarningCount: item.normalizationWarnings.count
                )
            },
            candidateDirectory: "private-fixtures/eventkit-probe/sanitized-candidates"
        )
    }
}

enum ProbeCommandLine {
    static func parse(_ arguments: [String]) throws -> ProbeCommand? {
        guard let first = arguments.first else { return nil }
        guard arguments.contains(where: {
            $0.hasPrefix("--safe-") || $0.hasPrefix("--private-")
        }) else { return nil }
        guard arguments.count == 1 else { throw ProbeCommandError.invalidArguments }

        switch first {
        case "--safe-status":
            return .status
        case "--safe-request-calendar":
            return .requestCalendar
        case "--safe-request-reminders":
            return .requestReminders
        case "--safe-sources":
            return .sources
        case "--safe-inspect":
            return .inspect
        case "--private-export-confirmed":
            return .privateExportConfirmed
        default:
            if first.hasPrefix("--safe-select-calendar=") {
                return .selectCalendar(try parseOrdinals(String(first.dropFirst(23))))
            }
            if first.hasPrefix("--safe-select-reminders=") {
                return .selectReminders(try parseOrdinals(String(first.dropFirst(24))))
            }
            if first.hasPrefix("--safe-") || first.hasPrefix("--private-") {
                throw ProbeCommandError.invalidArguments
            }
            return nil
        }
    }

    @MainActor
    static func run(
        _ command: ProbeCommand,
        reader: EventKitReader = EventKitReader(),
        selectionStore: SourceSelectionStore = SourceSelectionStore()
    ) async throws {
        let permissions = permissionReport(reader: reader)
        switch command {
        case .status:
            try write(permissions)
        case .requestCalendar:
            if permissions.calendar == .notDetermined {
                activateForPermissionPrompt()
                _ = try await reader.requestAccess(for: .event)
            }
            try write(permissionReport(reader: reader))
        case .requestReminders:
            if permissions.reminders == .notDetermined {
                activateForPermissionPrompt()
                _ = try await reader.requestAccess(for: .reminder)
            }
            try write(permissionReport(reader: reader))
        case .sources:
            try write(sourceReport(
                reader: reader,
                selectionStore: selectionStore,
                permissions: permissions
            ))
        case let .selectCalendar(ordinals):
            try select(
                entityType: .event,
                ordinals: ordinals,
                reader: reader,
                selectionStore: selectionStore,
                permissions: permissions
            )
        case let .selectReminders(ordinals):
            try select(
                entityType: .reminder,
                ordinals: ordinals,
                reader: reader,
                selectionStore: selectionStore,
                permissions: permissions
            )
        case .inspect:
            let inspection = await inspect(
                reader: reader,
                selectionStore: selectionStore,
                permissions: permissions
            )
            _ = try ProbeExporter().writeSanitizedCandidates(inspection)
            try write(SafeProbeEvidence.inspectionReport(
                inspection: inspection,
                permissions: permissions
            ))
        case .privateExportConfirmed:
            let inspection = await inspect(
                reader: reader,
                selectionStore: selectionStore,
                permissions: permissions
            )
            _ = try ProbeExporter().writePrivateInspection(inspection)
            try write(SafePrivateExportReport(
                reminderResultCount: inspection.reminderResultCount,
                reminderResultsTruncated: inspection.reminderResultsTruncated,
                eventResultCount: inspection.eventResultCount,
                eventResultsTruncated: inspection.eventResultsTruncated,
                destination: "private-fixtures/eventkit-probe/private-inspection-latest.json",
                warning: "Private source data stays local. Never commit, print, screenshot, or share this file."
            ))
        }
    }

    static func writeFailure() {
        let data = Data("{\"error\":\"safe probe command failed\"}\n".utf8)
        try? FileHandle.standardError.write(contentsOf: data)
    }

    @MainActor
    private static func activateForPermissionPrompt() {
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.activate()
    }

    private static func parseOrdinals(_ value: String) throws -> [Int] {
        if value.isEmpty { return [] }
        let ordinals = try value.split(separator: ",", omittingEmptySubsequences: false).map {
            guard let ordinal = Int($0), ordinal > 0 else {
                throw ProbeCommandError.invalidArguments
            }
            return ordinal
        }
        guard Set(ordinals).count == ordinals.count else {
            throw ProbeCommandError.invalidArguments
        }
        return ordinals.sorted()
    }

    private static func permissionReport(reader: EventKitReader) -> SafePermissionReport {
        SafePermissionReport(
            calendar: reader.permissionState(for: .event),
            reminders: reader.permissionState(for: .reminder)
        )
    }

    private static func sourceReport(
        reader: EventKitReader,
        selectionStore: SourceSelectionStore,
        permissions: SafePermissionReport
    ) -> SafeSourceReport {
        let calendars = permissions.calendar == .granted ? reader.sources(for: .event) : []
        let reminderLists = permissions.reminders == .granted ? reader.sources(for: .reminder) : []
        let savedCalendars = selectionStore.selectedIdentifiers(for: .event)
        let selectedCalendars = permissions.calendar == .granted
            ? selectionStore.reconcile(
                selectedIdentifiers: savedCalendars,
                availableIdentifiers: Set(calendars.map(\.id)),
                for: .event
            )
            : savedCalendars
        let savedReminderLists = selectionStore.selectedIdentifiers(for: .reminder)
        let selectedReminderLists = permissions.reminders == .granted
            ? selectionStore.reconcile(
                selectedIdentifiers: savedReminderLists,
                availableIdentifiers: Set(reminderLists.map(\.id)),
                for: .reminder
            )
            : savedReminderLists
        return SafeSourceReport(
            permissions: permissions,
            calendars: SafeProbeEvidence.sourceSummaries(
                calendars,
                selectedIdentifiers: selectedCalendars
            ),
            reminderLists: SafeProbeEvidence.sourceSummaries(
                reminderLists,
                selectedIdentifiers: selectedReminderLists
            )
        )
    }

    private static func select(
        entityType: ProbeEntityType,
        ordinals: [Int],
        reader: EventKitReader,
        selectionStore: SourceSelectionStore,
        permissions: SafePermissionReport
    ) throws {
        let permission = entityType == .event ? permissions.calendar : permissions.reminders
        guard permission == .granted else {
            throw ProbeCommandError.permissionUnavailable
        }
        let sources = reader.sources(for: entityType)
        let identifiers = try SafeProbeEvidence.identifiers(for: ordinals, in: sources)
        selectionStore.save(identifiers, for: entityType)
        try write(SafeSelectionReport(
            entityType: entityType,
            selectedOrdinals: ordinals,
            selectedCount: identifiers.count
        ))
    }

    private static func inspect(
        reader: EventKitReader,
        selectionStore: SourceSelectionStore,
        permissions: SafePermissionReport
    ) async -> ProbeInspection {
        let reminderBatch: ProbeReadBatch<ReminderProbeRecord>
        if permissions.reminders == .granted {
            reminderBatch = await reader.readReminders(
                selectedIdentifiers: selectionStore.selectedIdentifiers(for: .reminder)
            )
        } else {
            reminderBatch = ProbeReadBatch(records: [], matchedCount: 0)
        }

        let eventResult: (batch: ProbeReadBatch<EventProbeRecord>, window: ProbeReadWindow)
        if permissions.calendar == .granted {
            eventResult = reader.readEvents(
                selectedIdentifiers: selectionStore.selectedIdentifiers(for: .event)
            )
        } else {
            eventResult = (
                ProbeReadBatch(records: [], matchedCount: 0),
                reader.emptyReadWindow()
            )
        }

        return ProbeInspection(
            generatedAt: InstantFormatter.string(from: Date())!,
            calendarReadWindow: eventResult.window,
            reminderResultCount: reminderBatch.matchedCount,
            reminderResultsTruncated: reminderBatch.wasTruncated,
            eventResultCount: eventResult.batch.matchedCount,
            eventResultsTruncated: eventResult.batch.wasTruncated,
            reminders: reminderBatch.records,
            events: eventResult.batch.records
        )
    }

    private static func write<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(value)
        data.append(0x0A)
        try FileHandle.standardOutput.write(contentsOf: data)
    }
}
