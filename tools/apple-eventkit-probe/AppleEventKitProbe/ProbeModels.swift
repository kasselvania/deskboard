import Foundation

enum ProbeEntityType: String, Codable, CaseIterable {
    case event
    case reminder
}

enum ProbePermissionState: String, Codable {
    case notDetermined
    case requesting
    case granted
    case denied
    case unavailable

    var label: String {
        switch self {
        case .notDetermined: "Not determined"
        case .requesting: "Requesting"
        case .granted: "Granted"
        case .denied: "Denied"
        case .unavailable: "Restricted or unavailable"
        }
    }
}

struct ProbeSourceDescriptor: Identifiable, Equatable {
    let id: String
    let entityType: ProbeEntityType
    let title: String
    let calendarType: String
    let sourceType: String
    let allowsContentModifications: Bool
    let isSubscribed: Bool
}

enum ProbeTemporalKind: String, Codable {
    case dateOnly
    case localDateTime
    case timeZoneDateTime
    case allDayRange
}

struct ProbeTemporal: Codable, Equatable {
    var kind: ProbeTemporalKind
    var localDate: String?
    var localDateTime: String?
    var timeZone: String?
    var startDate: String?
    var endDate: String?

    static func dateOnly(_ localDate: String) -> Self {
        Self(
            kind: .dateOnly,
            localDate: localDate,
            localDateTime: nil,
            timeZone: nil,
            startDate: nil,
            endDate: nil
        )
    }

    static func localDateTime(_ value: String) -> Self {
        Self(
            kind: .localDateTime,
            localDate: nil,
            localDateTime: value,
            timeZone: nil,
            startDate: nil,
            endDate: nil
        )
    }

    static func timeZoneDateTime(_ value: String, timeZone: String) -> Self {
        Self(
            kind: .timeZoneDateTime,
            localDate: nil,
            localDateTime: value,
            timeZone: timeZone,
            startDate: nil,
            endDate: nil
        )
    }

    static func allDayRange(startDate: String, endDate: String) -> Self {
        Self(
            kind: .allDayRange,
            localDate: nil,
            localDateTime: nil,
            timeZone: nil,
            startDate: startDate,
            endDate: endDate
        )
    }
}

struct ProbeContainer: Codable, Equatable {
    var identifier: String
    var title: String
    var calendarType: String
    var sourceIdentifier: String
    var sourceTitle: String
    var sourceType: String
    var allowsContentModifications: Bool
    var isSubscribed: Bool
}

struct ProbeRecurrenceEnd: Codable, Equatable {
    var kind: String
    var occurrenceCount: Int?
    var endDate: String?
}

struct ProbeRecurrenceDay: Codable, Equatable {
    var dayOfWeek: Int
    var weekNumber: Int
}

struct ProbeRecurrence: Codable, Equatable {
    var calendarIdentifier: String
    var frequency: String
    var interval: Int
    var firstDayOfWeek: Int
    var daysOfWeek: [ProbeRecurrenceDay]?
    var daysOfMonth: [Int]?
    var daysOfYear: [Int]?
    var weeksOfYear: [Int]?
    var monthsOfYear: [Int]?
    var setPositions: [Int]?
    var end: ProbeRecurrenceEnd?
}

struct MetadataBlockObservation: Codable, Equatable {
    var openingDelimiterPresent: Bool
    var closingDelimiterPresent: Bool
    var pairedBlockPresent: Bool
    var malformed: Bool
    var proseBeforePresent: Bool
    var proseAfterPresent: Bool
    var multipleOpeningDelimiters: Bool
    var multipleClosingDelimiters: Bool
    var unsupportedVersionDelimiterPresent: Bool
}

struct ReminderProbeRecord: Codable, Equatable, Identifiable {
    var id: String { localIdentifier }

    var entityType: ProbeEntityType = .reminder
    var localIdentifier: String
    var externalIdentifier: String?
    var container: ProbeContainer
    var title: String?
    var notes: String?
    var creationDate: String?
    var lastModifiedDate: String?
    var start: ProbeTemporal?
    var due: ProbeTemporal?
    var isCompleted: Bool
    var completionDate: String?
    var priority: Int
    var recurrences: [ProbeRecurrence]?
    var alarmCount: Int
    var url: String?
    var location: String?
    var metadataBlock: MetadataBlockObservation?
    var normalizationWarnings: [String]
}

struct EventProbeRecord: Codable, Equatable, Identifiable {
    var id: String { localIdentifier }

    var entityType: ProbeEntityType = .event
    var localIdentifier: String
    var eventIdentifier: String?
    var externalIdentifier: String?
    var container: ProbeContainer
    var title: String?
    var notes: String?
    var creationDate: String?
    var lastModifiedDate: String?
    var temporal: ProbeTemporal
    var isAllDay: Bool
    var occurrenceDate: String?
    var isDetached: Bool
    var status: String
    var availability: String
    var recurrences: [ProbeRecurrence]?
    var alarmCount: Int
    var url: String?
    var location: String?
    var structuredLocationPresent: Bool
    var organizerPresent: Bool
    var attendeeCount: Int
    var normalizationWarnings: [String]
}

struct ProbeReadWindow: Codable, Equatable {
    var daysBefore: Int
    var daysAfter: Int
    var start: String
    var end: String
}

struct ProbeInspection: Codable, Equatable {
    var schemaVersion: Int = 1
    var generatedAt: String
    var calendarReadWindow: ProbeReadWindow
    var reminderResultCount: Int
    var reminderResultsTruncated: Bool
    var eventResultCount: Int
    var eventResultsTruncated: Bool
    var reminders: [ReminderProbeRecord]
    var events: [EventProbeRecord]
}

enum InstantFormatter {
    static func string(from date: Date?) -> String? {
        guard let date else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
