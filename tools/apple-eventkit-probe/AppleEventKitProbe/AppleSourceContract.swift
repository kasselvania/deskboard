import Foundation

enum AppleSourceContractValidationError: Error, LocalizedError {
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case let .invalid(message): message
        }
    }
}

enum AppleSourceEntityTypeV1: String, Codable {
    case reminder
    case calendar
}

enum AppleReminderTemporalKindV1: String, Codable {
    case absent
    case dateOnly
    case localDateTime
    case timeZoneDateTime
}

struct AppleReminderTemporalV1: Codable, Equatable {
    let kind: AppleReminderTemporalKindV1
    let localDate: String?
    let localDateTime: String?
    let timeZone: String?

    func validate() throws {
        switch kind {
        case .absent:
            guard localDate == nil, localDateTime == nil, timeZone == nil else {
                throw AppleSourceContractValidationError.invalid(
                    "absent Reminder temporal value contains contradictory fields"
                )
            }
        case .dateOnly:
            guard
                let localDate,
                AppleSourceTemporalValidation.isCalendarDate(localDate),
                localDateTime == nil,
                timeZone == nil
            else {
                throw AppleSourceContractValidationError.invalid(
                    "invalid date-only Reminder temporal value"
                )
            }
        case .localDateTime:
            guard
                let localDateTime,
                AppleSourceTemporalValidation.isLocalDateTime(localDateTime),
                localDate == nil,
                timeZone == nil
            else {
                throw AppleSourceContractValidationError.invalid(
                    "invalid local Reminder date-time"
                )
            }
        case .timeZoneDateTime:
            guard
                let localDateTime,
                let timeZone,
                AppleSourceTemporalValidation.isLocalDateTime(localDateTime),
                TimeZone(identifier: timeZone) != nil,
                localDate == nil
            else {
                throw AppleSourceContractValidationError.invalid(
                    "invalid timezone-qualified Reminder date-time"
                )
            }
        }
    }
}

enum AppleCalendarTemporalKindV1: String, Codable {
    case localTimedRange
    case timeZoneTimedRange
    case allDayRange
}

struct AppleCalendarTemporalV1: Codable, Equatable {
    let kind: AppleCalendarTemporalKindV1
    let startLocalDateTime: String?
    let endLocalDateTime: String?
    let start: String?
    let end: String?
    let timeZone: String?
    let startDate: String?
    let endDate: String?

    func validate() throws {
        switch kind {
        case .localTimedRange:
            guard
                let startLocalDateTime,
                let endLocalDateTime,
                AppleSourceTemporalValidation.isLocalDateTime(startLocalDateTime),
                AppleSourceTemporalValidation.isLocalDateTime(endLocalDateTime),
                startLocalDateTime < endLocalDateTime,
                start == nil,
                end == nil,
                timeZone == nil,
                startDate == nil,
                endDate == nil
            else {
                throw AppleSourceContractValidationError.invalid(
                    "invalid local Calendar timed range"
                )
            }
        case .timeZoneTimedRange:
            guard
                let start,
                let end,
                let timeZone,
                let startInstant = AppleSourceTemporalValidation.instant(start),
                let endInstant = AppleSourceTemporalValidation.instant(end),
                startInstant < endInstant,
                TimeZone(identifier: timeZone) != nil,
                startLocalDateTime == nil,
                endLocalDateTime == nil,
                startDate == nil,
                endDate == nil
            else {
                throw AppleSourceContractValidationError.invalid(
                    "invalid timezone-qualified Calendar timed range"
                )
            }
        case .allDayRange:
            guard
                let startDate,
                let endDate,
                AppleSourceTemporalValidation.isCalendarDate(startDate),
                AppleSourceTemporalValidation.isCalendarDate(endDate),
                startDate < endDate,
                startLocalDateTime == nil,
                endLocalDateTime == nil,
                start == nil,
                end == nil,
                timeZone == nil
            else {
                throw AppleSourceContractValidationError.invalid(
                    "invalid exclusive Calendar all-day range"
                )
            }
        }
    }
}

struct AppleReminderSourceRecordV1: Codable, Equatable {
    let localIdentifier: String
    let externalIdentifier: String?
    let title: String?
    let start: AppleReminderTemporalV1
    let due: AppleReminderTemporalV1
    let isCompleted: Bool
    let completionDate: String?

    func validate() throws {
        try AppleSourceContractSemantics.requireIdentifier(localIdentifier)
        try AppleSourceContractSemantics.requireOptionalIdentifier(externalIdentifier)
        try start.validate()
        try due.validate()
        if let completionDate {
            guard
                isCompleted,
                AppleSourceTemporalValidation.instant(completionDate) != nil
            else {
                throw AppleSourceContractValidationError.invalid(
                    "incomplete Reminder has a completion date"
                )
            }
        }
    }
}

enum AppleCalendarStatusV1: String, Codable {
    case none
    case confirmed
    case tentative
    case canceled
}

struct AppleCalendarSourceRecordV1: Codable, Equatable {
    let localIdentifier: String
    let eventIdentifier: String?
    let externalIdentifier: String?
    let title: String?
    let temporal: AppleCalendarTemporalV1
    let occurrenceDate: String?
    let isDetached: Bool
    let status: AppleCalendarStatusV1

    func validate() throws {
        try AppleSourceContractSemantics.requireIdentifier(localIdentifier)
        try AppleSourceContractSemantics.requireOptionalIdentifier(eventIdentifier)
        try AppleSourceContractSemantics.requireOptionalIdentifier(externalIdentifier)
        try temporal.validate()
        if let occurrenceDate,
           AppleSourceTemporalValidation.instant(occurrenceDate) == nil
        {
            throw AppleSourceContractValidationError.invalid(
                "invalid Calendar occurrence date"
            )
        }
    }
}

struct AppleReminderSourceScopeV1: Codable, Equatable {
    let sourceContainerId: String
    let allowsContentModifications: Bool

    func validate() throws {
        try AppleSourceContractSemantics.requireIdentifier(sourceContainerId)
    }
}

struct AppleCalendarSourceScopeV1: Codable, Equatable {
    let sourceContainerId: String
    let allowsContentModifications: Bool
    let isSubscribed: Bool

    func validate() throws {
        try AppleSourceContractSemantics.requireIdentifier(sourceContainerId)
    }
}

enum AppleCalendarWindowBoundarySemanticsV1: String, Codable {
    case overlapStartInclusiveEndExclusive
}

struct AppleCalendarWindowV1: Codable, Equatable {
    let start: String
    let end: String
    let timeZone: String
    let boundarySemantics: AppleCalendarWindowBoundarySemanticsV1

    func validate() throws {
        guard
            let startDate = AppleSourceTemporalValidation.instant(start),
            let endDate = AppleSourceTemporalValidation.instant(end),
            startDate < endDate,
            TimeZone(identifier: timeZone) != nil
        else {
            throw AppleSourceContractValidationError.invalid(
                "invalid Calendar snapshot window"
            )
        }
    }
}

struct AppleReminderSourceSnapshotV1: Codable, Equatable {
    let schemaVersion: Int
    let entityType: AppleSourceEntityTypeV1
    let bridgeId: String
    let source: AppleReminderSourceScopeV1
    let capturedAt: String
    let matchedCount: Int
    let truncated: Bool
    let records: [AppleReminderSourceRecordV1]

    func validate() throws {
        guard schemaVersion == 1, entityType == .reminder else {
            throw AppleSourceContractValidationError.invalid(
                "unsupported Reminder snapshot version or discriminator"
            )
        }
        try AppleSourceContractSemantics.requireIdentifier(bridgeId)
        try source.validate()
        guard AppleSourceTemporalValidation.instant(capturedAt) != nil else {
            throw AppleSourceContractValidationError.invalid("invalid capture time")
        }
        try AppleSourceContractSemantics.validateCounts(
            matchedCount: matchedCount,
            retainedCount: records.count,
            truncated: truncated
        )
        for record in records {
            try record.validate()
        }
        for index in records.indices.dropFirst() {
            let comparison = AppleSourceContractSemantics.compareReminderRecords(
                left: records[index - 1],
                leftSourceContainerId: source.sourceContainerId,
                right: records[index],
                rightSourceContainerId: source.sourceContainerId
            )
            if comparison == .orderedDescending {
                throw AppleSourceContractValidationError.invalid(
                    "Reminder records are not in deterministic provenance order"
                )
            } else if comparison == .orderedSame {
                throw AppleSourceContractValidationError.invalid(
                    "Reminder provenance ordering coordinate collides"
                )
            }
        }
    }
}

struct AppleCalendarSourceSnapshotV1: Codable, Equatable {
    let schemaVersion: Int
    let entityType: AppleSourceEntityTypeV1
    let bridgeId: String
    let source: AppleCalendarSourceScopeV1
    let capturedAt: String
    let window: AppleCalendarWindowV1
    let matchedCount: Int
    let truncated: Bool
    let records: [AppleCalendarSourceRecordV1]

    func validate() throws {
        guard schemaVersion == 1, entityType == .calendar else {
            throw AppleSourceContractValidationError.invalid(
                "unsupported Calendar snapshot version or discriminator"
            )
        }
        try AppleSourceContractSemantics.requireIdentifier(bridgeId)
        try source.validate()
        guard AppleSourceTemporalValidation.instant(capturedAt) != nil else {
            throw AppleSourceContractValidationError.invalid("invalid capture time")
        }
        try window.validate()
        try AppleSourceContractSemantics.validateCounts(
            matchedCount: matchedCount,
            retainedCount: records.count,
            truncated: truncated
        )

        guard
            let scopeStart = AppleSourceTemporalValidation.instant(window.start),
            let scopeEnd = AppleSourceTemporalValidation.instant(window.end)
        else {
            throw AppleSourceContractValidationError.invalid(
                "invalid Calendar window instants"
            )
        }

        var bounds: [AppleSourceContractSemantics.CalendarBounds] = []
        for record in records {
            try record.validate()
            let recordBounds = try AppleSourceContractSemantics.calendarBounds(
                record,
                windowTimeZone: window.timeZone
            )
            guard
                recordBounds.start < recordBounds.end,
                recordBounds.start < scopeEnd,
                recordBounds.end > scopeStart
            else {
                throw AppleSourceContractValidationError.invalid(
                    "Calendar record does not overlap its declared window"
                )
            }
            bounds.append(recordBounds)
        }

        for index in records.indices.dropFirst() {
            let comparison = AppleSourceContractSemantics.compareCalendarRecords(
                left: records[index - 1],
                leftBounds: bounds[index - 1],
                leftSourceContainerId: source.sourceContainerId,
                right: records[index],
                rightBounds: bounds[index],
                rightSourceContainerId: source.sourceContainerId
            )
            if comparison == .orderedDescending {
                throw AppleSourceContractValidationError.invalid(
                    "Calendar records are not in deterministic source order"
                )
            } else if comparison == .orderedSame {
                throw AppleSourceContractValidationError.invalid(
                    "Calendar provenance ordering coordinate collides"
                )
            }
        }
    }
}

struct ValidatedAppleSourceSnapshotV1: Equatable {
    private enum Storage: Equatable {
        case reminder(AppleReminderSourceSnapshotV1)
        case calendar(AppleCalendarSourceSnapshotV1)
    }

    private let storage: Storage

    fileprivate init(reminder: AppleReminderSourceSnapshotV1) {
        storage = .reminder(reminder)
    }

    fileprivate init(calendar: AppleCalendarSourceSnapshotV1) {
        storage = .calendar(calendar)
    }

    var reminderSnapshot: AppleReminderSourceSnapshotV1? {
        guard case let .reminder(snapshot) = storage else { return nil }
        return snapshot
    }

    var calendarSnapshot: AppleCalendarSourceSnapshotV1? {
        guard case let .calendar(snapshot) = storage else { return nil }
        return snapshot
    }

    var absenceIsAuthoritative: Bool {
        switch storage {
        case let .reminder(snapshot): !snapshot.truncated
        case let .calendar(snapshot): !snapshot.truncated
        }
    }
}

enum AppleSourceContractDecoder {
    static func decode(_ data: Data) throws -> ValidatedAppleSourceSnapshotV1 {
        let object = try JSONSerialization.jsonObject(with: data)
        try AppleSourceStrictKeyValidator.rejectNulls(object, path: "$")
        let root = try AppleSourceStrictKeyValidator.object(object, path: "$")
        guard let entityType = root["entityType"] as? String else {
            throw AppleSourceContractValidationError.invalid(
                "missing source snapshot entity discriminator"
            )
        }

        let decoder = JSONDecoder()
        switch entityType {
        case AppleSourceEntityTypeV1.reminder.rawValue:
            try AppleSourceStrictKeyValidator.validateReminderSnapshot(root)
            let snapshot = try decoder.decode(AppleReminderSourceSnapshotV1.self, from: data)
            try snapshot.validate()
            return ValidatedAppleSourceSnapshotV1(reminder: snapshot)
        case AppleSourceEntityTypeV1.calendar.rawValue:
            try AppleSourceStrictKeyValidator.validateCalendarSnapshot(root)
            let snapshot = try decoder.decode(AppleCalendarSourceSnapshotV1.self, from: data)
            try snapshot.validate()
            return ValidatedAppleSourceSnapshotV1(calendar: snapshot)
        default:
            throw AppleSourceContractValidationError.invalid(
                "unsupported source snapshot entity discriminator"
            )
        }
    }
}

private enum AppleSourceStrictKeyValidator {
    typealias JSONObject = [String: Any]

    private static let reminderSnapshotKeys: Set<String> = [
        "schemaVersion", "entityType", "bridgeId", "source", "capturedAt",
        "matchedCount", "truncated", "records",
    ]
    private static let calendarSnapshotKeys = reminderSnapshotKeys.union(["window"])
    private static let reminderSourceKeys: Set<String> = [
        "sourceContainerId", "allowsContentModifications",
    ]
    private static let calendarSourceKeys = reminderSourceKeys.union(["isSubscribed"])
    private static let calendarWindowKeys: Set<String> = [
        "start", "end", "timeZone", "boundarySemantics",
    ]
    private static let reminderRecordKeys: Set<String> = [
        "localIdentifier", "externalIdentifier", "title", "start", "due",
        "isCompleted", "completionDate",
    ]
    private static let calendarRecordKeys: Set<String> = [
        "localIdentifier", "eventIdentifier", "externalIdentifier", "title",
        "temporal", "occurrenceDate", "isDetached", "status",
    ]

    static func object(_ value: Any, path: String) throws -> JSONObject {
        guard let object = value as? JSONObject else {
            throw AppleSourceContractValidationError.invalid(
                "expected JSON object at \(path)"
            )
        }
        return object
    }

    static func rejectNulls(_ value: Any, path: String) throws {
        if value is NSNull {
            throw AppleSourceContractValidationError.invalid(
                "null is not part of the v1 contract at \(path)"
            )
        }
        if let object = value as? JSONObject {
            for (key, child) in object {
                try rejectNulls(child, path: "\(path).\(key)")
            }
        } else if let array = value as? [Any] {
            for (index, child) in array.enumerated() {
                try rejectNulls(child, path: "\(path)[\(index)]")
            }
        }
    }

    static func validateReminderSnapshot(_ root: JSONObject) throws {
        try validateKeys(root, allowed: reminderSnapshotKeys, path: "$")
        try validateKeys(
            object(try required(root, key: "source", path: "$"), path: "$.source"),
            allowed: reminderSourceKeys,
            path: "$.source"
        )
        for (index, record) in try records(root).enumerated() {
            let path = "$.records[\(index)]"
            let recordObject = try object(record, path: path)
            try validateKeys(recordObject, allowed: reminderRecordKeys, path: path)
            try validateReminderTemporal(
                object(
                    try required(recordObject, key: "start", path: path),
                    path: "\(path).start"
                ),
                path: "\(path).start"
            )
            try validateReminderTemporal(
                object(
                    try required(recordObject, key: "due", path: path),
                    path: "\(path).due"
                ),
                path: "\(path).due"
            )
        }
    }

    static func validateCalendarSnapshot(_ root: JSONObject) throws {
        try validateKeys(root, allowed: calendarSnapshotKeys, path: "$")
        try validateKeys(
            object(try required(root, key: "source", path: "$"), path: "$.source"),
            allowed: calendarSourceKeys,
            path: "$.source"
        )
        try validateKeys(
            object(try required(root, key: "window", path: "$"), path: "$.window"),
            allowed: calendarWindowKeys,
            path: "$.window"
        )
        for (index, record) in try records(root).enumerated() {
            let path = "$.records[\(index)]"
            let recordObject = try object(record, path: path)
            try validateKeys(recordObject, allowed: calendarRecordKeys, path: path)
            try validateCalendarTemporal(
                object(
                    try required(recordObject, key: "temporal", path: path),
                    path: "\(path).temporal"
                ),
                path: "\(path).temporal"
            )
        }
    }

    private static func validateReminderTemporal(
        _ object: JSONObject,
        path: String
    ) throws {
        guard let kind = object["kind"] as? String else {
            throw AppleSourceContractValidationError.invalid("missing temporal kind at \(path)")
        }
        let allowed: Set<String>
        switch kind {
        case AppleReminderTemporalKindV1.absent.rawValue:
            allowed = ["kind"]
        case AppleReminderTemporalKindV1.dateOnly.rawValue:
            allowed = ["kind", "localDate"]
        case AppleReminderTemporalKindV1.localDateTime.rawValue:
            allowed = ["kind", "localDateTime"]
        case AppleReminderTemporalKindV1.timeZoneDateTime.rawValue:
            allowed = ["kind", "localDateTime", "timeZone"]
        default:
            throw AppleSourceContractValidationError.invalid("unsupported temporal kind at \(path)")
        }
        try validateKeys(object, allowed: allowed, path: path)
    }

    private static func validateCalendarTemporal(
        _ object: JSONObject,
        path: String
    ) throws {
        guard let kind = object["kind"] as? String else {
            throw AppleSourceContractValidationError.invalid("missing temporal kind at \(path)")
        }
        let allowed: Set<String>
        switch kind {
        case AppleCalendarTemporalKindV1.localTimedRange.rawValue:
            allowed = ["kind", "startLocalDateTime", "endLocalDateTime"]
        case AppleCalendarTemporalKindV1.timeZoneTimedRange.rawValue:
            allowed = ["kind", "start", "end", "timeZone"]
        case AppleCalendarTemporalKindV1.allDayRange.rawValue:
            allowed = ["kind", "startDate", "endDate"]
        default:
            throw AppleSourceContractValidationError.invalid("unsupported temporal kind at \(path)")
        }
        try validateKeys(object, allowed: allowed, path: path)
    }

    private static func records(_ root: JSONObject) throws -> [Any] {
        guard let records = root["records"] as? [Any] else {
            throw AppleSourceContractValidationError.invalid("records must be an array")
        }
        return records
    }

    private static func required(
        _ object: JSONObject,
        key: String,
        path: String
    ) throws -> Any {
        guard let value = object[key] else {
            throw AppleSourceContractValidationError.invalid(
                "missing \(key) at \(path)"
            )
        }
        return value
    }

    private static func validateKeys(
        _ object: JSONObject,
        allowed: Set<String>,
        path: String
    ) throws {
        let unknown = Set(object.keys).subtracting(allowed)
        guard unknown.isEmpty else {
            throw AppleSourceContractValidationError.invalid(
                "unknown key at \(path): \(unknown.sorted().joined(separator: ", "))"
            )
        }
    }
}

private enum AppleSourceTemporalValidation {
    private static let instantPattern = try! NSRegularExpression(
        pattern: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?(?:Z|[+-]\d{2}:\d{2})$"#
    )

    private static let instantWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let instantWithoutFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func isCalendarDate(_ value: String) -> Bool {
        let fields = value.split(separator: "-", omittingEmptySubsequences: false)
        guard
            fields.count == 3,
            fields[0].count == 4,
            fields[1].count == 2,
            fields[2].count == 2,
            fields.allSatisfy({ $0.allSatisfy(\.isNumber) }),
            let year = Int(fields[0]),
            let month = Int(fields[1]),
            let day = Int(fields[2]),
            year > 0
        else {
            return false
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        guard let date = calendar.date(from: components) else { return false }
        let resolved = calendar.dateComponents([.year, .month, .day], from: date)
        return resolved.year == year && resolved.month == month && resolved.day == day
    }

    static func isLocalDateTime(_ value: String) -> Bool {
        guard value.count == 19 else { return false }
        let fields = value.split(separator: "T", omittingEmptySubsequences: false)
        guard fields.count == 2, isCalendarDate(String(fields[0])) else { return false }
        let clock = fields[1].split(separator: ":", omittingEmptySubsequences: false)
        guard
            clock.count == 3,
            clock.allSatisfy({ $0.count == 2 && $0.allSatisfy(\.isNumber) }),
            let hour = Int(clock[0]),
            let minute = Int(clock[1]),
            let second = Int(clock[2])
        else {
            return false
        }
        return (0 ... 23).contains(hour)
            && (0 ... 59).contains(minute)
            && (0 ... 59).contains(second)
    }

    static func instant(_ value: String) -> Date? {
        let range = NSRange(value.startIndex ..< value.endIndex, in: value)
        guard
            instantPattern.firstMatch(in: value, range: range) != nil,
            value.count >= 20,
            isLocalDateTime(String(value.prefix(19)))
        else {
            return nil
        }
        if value.last != "Z" {
            let offset = String(value.suffix(6))
            let fields = offset.dropFirst().split(separator: ":")
            guard
                fields.count == 2,
                let hour = Int(fields[0]),
                let minute = Int(fields[1]),
                hour <= 23,
                minute <= 59
            else {
                return nil
            }
        }
        return instantWithFractionalSeconds.date(from: value)
            ?? instantWithoutFractionalSeconds.date(from: value)
    }

    static func unambiguousLocalDate(_ value: String, in timeZoneIdentifier: String) -> Date? {
        guard
            isLocalDateTime(value),
            let timeZone = TimeZone(identifier: timeZoneIdentifier)
        else {
            return nil
        }

        let dateAndClock = value.split(separator: "T")
        let date = dateAndClock[0].split(separator: "-")
        let clock = dateAndClock[1].split(separator: ":")
        var matchingComponents = DateComponents()
        matchingComponents.year = Int(date[0])
        matchingComponents.month = Int(date[1])
        matchingComponents.day = Int(date[2])
        matchingComponents.hour = Int(clock[0])
        matchingComponents.minute = Int(clock[1])
        matchingComponents.second = Int(clock[2])

        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var anchorComponents = matchingComponents
        anchorComponents.calendar = utcCalendar
        anchorComponents.timeZone = utcCalendar.timeZone
        guard
            let civilAsUTC = utcCalendar.date(from: anchorComponents),
            let anchor = utcCalendar.date(byAdding: .day, value: -2, to: civilAsUTC)
        else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let first = calendar.nextDate(
            after: anchor,
            matching: matchingComponents,
            matchingPolicy: .strict,
            repeatedTimePolicy: .first,
            direction: .forward
        )
        let last = calendar.nextDate(
            after: anchor,
            matching: matchingComponents,
            matchingPolicy: .strict,
            repeatedTimePolicy: .last,
            direction: .forward
        )
        guard
            let first,
            let last,
            first == last
        else {
            return nil
        }
        return first
    }
}

private enum AppleSourceContractSemantics {
    struct CalendarBounds {
        let start: Date
        let end: Date
    }

    static func requireIdentifier(_ value: String) throws {
        guard !value.isEmpty else {
            throw AppleSourceContractValidationError.invalid("identifier cannot be empty")
        }
    }

    static func requireOptionalIdentifier(_ value: String?) throws {
        if let value {
            try requireIdentifier(value)
        }
    }

    static func validateCounts(
        matchedCount: Int,
        retainedCount: Int,
        truncated: Bool
    ) throws {
        guard matchedCount >= 0, matchedCount >= retainedCount else {
            throw AppleSourceContractValidationError.invalid(
                "matched count cannot be less than retained count"
            )
        }
        if truncated {
            guard matchedCount > retainedCount else {
                throw AppleSourceContractValidationError.invalid(
                    "truncated snapshot must omit at least one match"
                )
            }
        } else {
            guard matchedCount == retainedCount else {
                throw AppleSourceContractValidationError.invalid(
                    "non-truncated snapshot must retain every match"
                )
            }
        }
    }

    static func calendarBounds(
        _ record: AppleCalendarSourceRecordV1,
        windowTimeZone: String
    ) throws -> CalendarBounds {
        let temporal = record.temporal
        switch temporal.kind {
        case .localTimedRange:
            guard
                let start = temporal.startLocalDateTime,
                let end = temporal.endLocalDateTime,
                let startDate = AppleSourceTemporalValidation.unambiguousLocalDate(
                    start,
                    in: windowTimeZone
                ),
                let endDate = AppleSourceTemporalValidation.unambiguousLocalDate(
                    end,
                    in: windowTimeZone
                )
            else {
                throw AppleSourceContractValidationError.invalid(
                    "local Calendar range is missing, nonexistent, or ambiguous"
                )
            }
            return CalendarBounds(start: startDate, end: endDate)
        case .timeZoneTimedRange:
            guard
                temporal.timeZone != nil,
                let start = temporal.start,
                let end = temporal.end,
                let startDate = AppleSourceTemporalValidation.instant(start),
                let endDate = AppleSourceTemporalValidation.instant(end)
            else {
                throw AppleSourceContractValidationError.invalid(
                    "missing timezone-qualified Calendar range values"
                )
            }
            return CalendarBounds(start: startDate, end: endDate)
        case .allDayRange:
            guard
                let start = temporal.startDate,
                let end = temporal.endDate,
                let startDate = AppleSourceTemporalValidation.unambiguousLocalDate(
                    "\(start)T00:00:00",
                    in: windowTimeZone
                ),
                let endDate = AppleSourceTemporalValidation.unambiguousLocalDate(
                    "\(end)T00:00:00",
                    in: windowTimeZone
                )
            else {
                throw AppleSourceContractValidationError.invalid(
                    "all-day Calendar range cannot be interpreted unambiguously"
                )
            }
            return CalendarBounds(start: startDate, end: endDate)
        }
    }

    static func compareReminderRecords(
        left: AppleReminderSourceRecordV1,
        leftSourceContainerId: String,
        right: AppleReminderSourceRecordV1,
        rightSourceContainerId: String
    ) -> ComparisonResult {
        let source = compareUnicodeScalars(leftSourceContainerId, rightSourceContainerId)
        if source != .orderedSame {
            return source
        }
        let local = compareUnicodeScalars(left.localIdentifier, right.localIdentifier)
        return local == .orderedSame
            ? compareOptionalIdentifiers(left.externalIdentifier, right.externalIdentifier)
            : local
    }

    static func compareCalendarRecords(
        left: AppleCalendarSourceRecordV1,
        leftBounds: CalendarBounds,
        leftSourceContainerId: String,
        right: AppleCalendarSourceRecordV1,
        rightBounds: CalendarBounds,
        rightSourceContainerId: String
    ) -> ComparisonResult {
        if leftBounds.start != rightBounds.start {
            return leftBounds.start < rightBounds.start ? .orderedAscending : .orderedDescending
        }
        if leftBounds.end != rightBounds.end {
            return leftBounds.end < rightBounds.end ? .orderedAscending : .orderedDescending
        }
        let source = compareUnicodeScalars(leftSourceContainerId, rightSourceContainerId)
        if source != .orderedSame {
            return source
        }
        let local = compareUnicodeScalars(left.localIdentifier, right.localIdentifier)
        if local != .orderedSame {
            return local
        }
        let event = compareOptionalIdentifiers(left.eventIdentifier, right.eventIdentifier)
        if event != .orderedSame {
            return event
        }
        let occurrence = compareOptionalInstants(left.occurrenceDate, right.occurrenceDate)
        return occurrence == .orderedSame
            ? compareOptionalIdentifiers(left.externalIdentifier, right.externalIdentifier)
            : occurrence
    }

    private static func compareOptionalInstants(
        _ left: String?,
        _ right: String?
    ) -> ComparisonResult {
        switch (left, right) {
        case (nil, nil): return .orderedSame
        case (nil, _): return .orderedAscending
        case (_, nil): return .orderedDescending
        case let (left?, right?):
            guard
                let leftDate = AppleSourceTemporalValidation.instant(left),
                let rightDate = AppleSourceTemporalValidation.instant(right)
            else {
                return .orderedSame
            }
            if leftDate == rightDate {
                return .orderedSame
            }
            return leftDate < rightDate ? .orderedAscending : .orderedDescending
        }
    }

    private static func compareOptionalIdentifiers(
        _ left: String?,
        _ right: String?
    ) -> ComparisonResult {
        switch (left, right) {
        case (nil, nil): .orderedSame
        case (nil, _): .orderedAscending
        case (_, nil): .orderedDescending
        case let (left?, right?): compareUnicodeScalars(left, right)
        }
    }

    private static func compareUnicodeScalars(
        _ left: String,
        _ right: String
    ) -> ComparisonResult {
        let leftScalars = left.unicodeScalars.map(\.value)
        let rightScalars = right.unicodeScalars.map(\.value)
        for (leftValue, rightValue) in zip(leftScalars, rightScalars) {
            if leftValue != rightValue {
                return leftValue < rightValue ? .orderedAscending : .orderedDescending
            }
        }
        if leftScalars.count == rightScalars.count {
            return .orderedSame
        }
        return leftScalars.count < rightScalars.count ? .orderedAscending : .orderedDescending
    }
}
