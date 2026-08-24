import Foundation

enum AppleSourceConverterError: Error, LocalizedError {
    case invalidSource

    var errorDescription: String? {
        "The selected source could not produce a valid snapshot."
    }
}

struct ReminderSourceRead {
    let sourceContainerId: String
    let allowsContentModifications: Bool
    let records: [ReminderRecordRead]
}

struct ReminderRecordRead {
    let localIdentifier: String
    let externalIdentifier: String?
    let title: String?
    let startComponents: DateComponents?
    let dueComponents: DateComponents?
    let isCompleted: Bool
    let completionDate: Date?
}

enum CalendarRecordTemporalRead {
    case timed(start: Date, end: Date, timeZone: TimeZone?)
    case localTimed(start: String, end: String)
    case allDay(start: Date, end: Date)
}

struct CalendarSourceRead {
    let sourceContainerId: String
    let allowsContentModifications: Bool
    let isSubscribed: Bool
    let windowStart: Date
    let windowEnd: Date
    let windowTimeZone: TimeZone
    let records: [CalendarRecordRead]
}

struct CalendarRecordRead {
    let localIdentifier: String
    let eventIdentifier: String?
    let externalIdentifier: String?
    let title: String?
    let temporal: CalendarRecordTemporalRead
    let occurrenceDate: Date?
    let isDetached: Bool
    let status: AppleCalendarStatusV1
}

enum CalendarWindowPolicy {
    static func window(now: Date, timeZone: TimeZone) throws -> (start: Date, end: Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard
            let start = calendar.date(
                byAdding: .day,
                value: -BridgeProductionLimits.calendarDaysBehind,
                to: now
            ),
            let end = calendar.date(
                byAdding: .day,
                value: BridgeProductionLimits.calendarDaysAhead,
                to: now
            ),
            start < end
        else {
            throw AppleSourceConverterError.invalidSource
        }
        return (start, end)
    }
}

enum AppleSourceConverter {
    static func reminderSnapshot(
        from source: ReminderSourceRead,
        bridgeId: String,
        capturedAt: Date,
        maximumRecords: Int = BridgeProductionLimits.maximumRetainedRecordsPerSource
    ) throws -> AppleSourceSnapshotValueV1 {
        guard maximumRecords >= 0 else {
            throw AppleSourceConverterError.invalidSource
        }
        let converted = try source.records.map { record in
            let value = AppleReminderSourceRecordV1(
                localIdentifier: record.localIdentifier,
                externalIdentifier: record.externalIdentifier,
                title: record.title,
                start: try reminderTemporal(record.startComponents),
                due: try reminderTemporal(record.dueComponents),
                isCompleted: record.isCompleted,
                completionDate: record.completionDate.map { instantString($0) }
            )
            try value.validate()
            return value
        }.sorted { left, right in
            reminderComparison(left, right) == .orderedAscending
        }
        try rejectReminderCollisions(converted)

        let retained = Array(converted.prefix(maximumRecords))
        let snapshot = AppleReminderSourceSnapshotV1(
            schemaVersion: 1,
            entityType: .reminder,
            bridgeId: bridgeId,
            source: AppleReminderSourceScopeV1(
                sourceContainerId: source.sourceContainerId,
                allowsContentModifications: source.allowsContentModifications
            ),
            capturedAt: instantString(capturedAt),
            matchedCount: converted.count,
            truncated: retained.count < converted.count,
            records: retained
        )
        try snapshot.validate()
        return .reminder(snapshot)
    }

    static func calendarSnapshot(
        from source: CalendarSourceRead,
        bridgeId: String,
        capturedAt: Date,
        maximumRecords: Int = BridgeProductionLimits.maximumRetainedRecordsPerSource
    ) throws -> AppleSourceSnapshotValueV1 {
        guard maximumRecords >= 0, source.windowStart < source.windowEnd else {
            throw AppleSourceConverterError.invalidSource
        }
        let converted = try source.records.map { input -> ConvertedCalendarRecord in
            let conversion = try calendarTemporal(
                input.temporal,
                windowTimeZone: source.windowTimeZone
            )
            let record = AppleCalendarSourceRecordV1(
                localIdentifier: input.localIdentifier,
                eventIdentifier: input.eventIdentifier,
                externalIdentifier: input.externalIdentifier,
                title: input.title,
                temporal: conversion.temporal,
                occurrenceDate: input.occurrenceDate.map { instantString($0) },
                isDetached: input.isDetached,
                status: input.status
            )
            try record.validate()
            guard
                conversion.start < conversion.end,
                conversion.start < source.windowEnd,
                conversion.end > source.windowStart
            else {
                throw AppleSourceConverterError.invalidSource
            }
            return ConvertedCalendarRecord(
                record: record,
                start: conversion.start,
                end: conversion.end
            )
        }.sorted { left, right in
            calendarComparison(left, right) == .orderedAscending
        }
        try rejectCalendarCollisions(converted)

        let retained = Array(converted.prefix(maximumRecords).map { $0.record })
        let snapshot = AppleCalendarSourceSnapshotV1(
            schemaVersion: 1,
            entityType: .calendar,
            bridgeId: bridgeId,
            source: AppleCalendarSourceScopeV1(
                sourceContainerId: source.sourceContainerId,
                allowsContentModifications: source.allowsContentModifications,
                isSubscribed: source.isSubscribed
            ),
            capturedAt: instantString(capturedAt),
            window: AppleCalendarWindowV1(
                start: instantString(source.windowStart),
                end: instantString(source.windowEnd),
                timeZone: source.windowTimeZone.identifier,
                boundarySemantics: .overlapStartInclusiveEndExclusive
            ),
            matchedCount: converted.count,
            truncated: retained.count < converted.count,
            records: retained
        )
        try snapshot.validate()
        return .calendar(snapshot)
    }

    private static func reminderTemporal(
        _ components: DateComponents?
    ) throws -> AppleReminderTemporalV1 {
        guard let components else {
            return AppleReminderTemporalV1(
                kind: .absent,
                localDate: nil,
                localDateTime: nil,
                timeZone: nil
            )
        }
        guard
            let year = components.year,
            let month = components.month,
            let day = components.day
        else {
            throw AppleSourceConverterError.invalidSource
        }
        let date = String(format: "%04d-%02d-%02d", year, month, day)
        let hasClock = components.hour != nil || components.minute != nil || components.second != nil
        if !hasClock {
            let value = AppleReminderTemporalV1(
                kind: .dateOnly,
                localDate: date,
                localDateTime: nil,
                timeZone: nil
            )
            try value.validate()
            return value
        }
        guard let hour = components.hour, let minute = components.minute else {
            throw AppleSourceConverterError.invalidSource
        }
        let local = String(
            format: "%@T%02d:%02d:%02d",
            date,
            hour,
            minute,
            components.second ?? 0
        )
        let value = AppleReminderTemporalV1(
            kind: components.timeZone == nil ? .localDateTime : .timeZoneDateTime,
            localDate: nil,
            localDateTime: local,
            timeZone: components.timeZone?.identifier
        )
        try value.validate()
        return value
    }

    private struct ConvertedCalendarRecord {
        let record: AppleCalendarSourceRecordV1
        let start: Date
        let end: Date
    }

    private static func calendarTemporal(
        _ input: CalendarRecordTemporalRead,
        windowTimeZone: TimeZone
    ) throws -> (temporal: AppleCalendarTemporalV1, start: Date, end: Date) {
        switch input {
        case let .timed(start, end, timeZone?):
            let temporal = AppleCalendarTemporalV1(
                kind: .timeZoneTimedRange,
                startLocalDateTime: nil,
                endLocalDateTime: nil,
                start: instantString(start, timeZone: timeZone),
                end: instantString(end, timeZone: timeZone),
                timeZone: timeZone.identifier,
                startDate: nil,
                endDate: nil
            )
            try temporal.validate()
            return (temporal, start, end)
        case let .timed(start, end, nil):
            let startLocal = localDateTimeString(start, timeZone: windowTimeZone)
            let endLocal = localDateTimeString(end, timeZone: windowTimeZone)
            guard
                let resolvedStart = unambiguousLocalDate(startLocal, in: windowTimeZone),
                let resolvedEnd = unambiguousLocalDate(endLocal, in: windowTimeZone)
            else {
                throw AppleSourceConverterError.invalidSource
            }
            let temporal = AppleCalendarTemporalV1(
                kind: .localTimedRange,
                startLocalDateTime: startLocal,
                endLocalDateTime: endLocal,
                start: nil,
                end: nil,
                timeZone: nil,
                startDate: nil,
                endDate: nil
            )
            try temporal.validate()
            return (temporal, resolvedStart, resolvedEnd)
        case let .localTimed(start, end):
            guard
                let resolvedStart = unambiguousLocalDate(start, in: windowTimeZone),
                let resolvedEnd = unambiguousLocalDate(end, in: windowTimeZone)
            else {
                throw AppleSourceConverterError.invalidSource
            }
            let temporal = AppleCalendarTemporalV1(
                kind: .localTimedRange,
                startLocalDateTime: start,
                endLocalDateTime: end,
                start: nil,
                end: nil,
                timeZone: nil,
                startDate: nil,
                endDate: nil
            )
            try temporal.validate()
            return (temporal, resolvedStart, resolvedEnd)
        case let .allDay(start, end):
            let startDate = localDateString(start, timeZone: windowTimeZone)
            let endDate = localDateString(end, timeZone: windowTimeZone)
            guard
                let interpretedStart = unambiguousLocalDate(
                    "\(startDate)T00:00:00",
                    in: windowTimeZone
                ),
                let interpretedEnd = unambiguousLocalDate(
                    "\(endDate)T00:00:00",
                    in: windowTimeZone
                )
            else {
                throw AppleSourceConverterError.invalidSource
            }
            let temporal = AppleCalendarTemporalV1(
                kind: .allDayRange,
                startLocalDateTime: nil,
                endLocalDateTime: nil,
                start: nil,
                end: nil,
                timeZone: nil,
                startDate: startDate,
                endDate: endDate
            )
            try temporal.validate()
            return (temporal, interpretedStart, interpretedEnd)
        }
    }

    private static func reminderComparison(
        _ left: AppleReminderSourceRecordV1,
        _ right: AppleReminderSourceRecordV1
    ) -> ComparisonResult {
        let local = scalarComparison(left.localIdentifier, right.localIdentifier)
        return local == .orderedSame
            ? optionalScalarComparison(left.externalIdentifier, right.externalIdentifier)
            : local
    }

    private static func calendarComparison(
        _ left: ConvertedCalendarRecord,
        _ right: ConvertedCalendarRecord
    ) -> ComparisonResult {
        if left.start != right.start {
            return left.start < right.start ? .orderedAscending : .orderedDescending
        }
        if left.end != right.end {
            return left.end < right.end ? .orderedAscending : .orderedDescending
        }
        let local = scalarComparison(
            left.record.localIdentifier,
            right.record.localIdentifier
        )
        if local != .orderedSame { return local }
        let event = optionalScalarComparison(
            left.record.eventIdentifier,
            right.record.eventIdentifier
        )
        if event != .orderedSame { return event }
        let occurrence = optionalDateComparison(
            left.record.occurrenceDate,
            right.record.occurrenceDate
        )
        return occurrence == .orderedSame
            ? optionalScalarComparison(
                left.record.externalIdentifier,
                right.record.externalIdentifier
            )
            : occurrence
    }

    private static func rejectReminderCollisions(
        _ records: [AppleReminderSourceRecordV1]
    ) throws {
        for index in records.indices.dropFirst()
        where reminderComparison(records[index - 1], records[index]) == .orderedSame {
            throw AppleSourceConverterError.invalidSource
        }
    }

    private static func rejectCalendarCollisions(
        _ records: [ConvertedCalendarRecord]
    ) throws {
        for index in records.indices.dropFirst()
        where calendarComparison(records[index - 1], records[index]) == .orderedSame {
            throw AppleSourceConverterError.invalidSource
        }
    }

    private static func scalarComparison(_ left: String, _ right: String) -> ComparisonResult {
        let leftValues = left.unicodeScalars.map(\.value)
        let rightValues = right.unicodeScalars.map(\.value)
        for (leftValue, rightValue) in zip(leftValues, rightValues) where leftValue != rightValue {
            return leftValue < rightValue ? .orderedAscending : .orderedDescending
        }
        if leftValues.count == rightValues.count { return .orderedSame }
        return leftValues.count < rightValues.count ? .orderedAscending : .orderedDescending
    }

    private static func optionalScalarComparison(
        _ left: String?,
        _ right: String?
    ) -> ComparisonResult {
        switch (left, right) {
        case (nil, nil): return .orderedSame
        case (nil, _): return .orderedAscending
        case (_, nil): return .orderedDescending
        case let (left?, right?): return scalarComparison(left, right)
        }
    }

    private static func optionalDateComparison(
        _ left: String?,
        _ right: String?
    ) -> ComparisonResult {
        switch (left, right) {
        case (nil, nil): return .orderedSame
        case (nil, _): return .orderedAscending
        case (_, nil): return .orderedDescending
        case let (left?, right?):
            guard
                let leftDate = instantDate(left),
                let rightDate = instantDate(right)
            else { return .orderedSame }
            if leftDate == rightDate { return .orderedSame }
            return leftDate < rightDate ? .orderedAscending : .orderedDescending
        }
    }

    private static func instantString(_ date: Date, timeZone: TimeZone? = nil) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = timeZone ?? TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private static func instantDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private static func localDateString(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    private static func localDateTimeString(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        return String(
            format: "%04d-%02d-%02dT%02d:%02d:%02d",
            parts.year!, parts.month!, parts.day!,
            parts.hour!, parts.minute!, parts.second!
        )
    }

    private static func unambiguousLocalDate(_ value: String, in timeZone: TimeZone) -> Date? {
        let pieces = value.split(separator: "T")
        guard pieces.count == 2 else { return nil }
        let date = pieces[0].split(separator: "-")
        let time = pieces[1].split(separator: ":")
        guard date.count == 3, time.count == 3 else { return nil }
        var components = DateComponents()
        components.year = Int(date[0])
        components.month = Int(date[1])
        components.day = Int(date[2])
        components.hour = Int(time[0])
        components.minute = Int(time[1])
        components.second = Int(time[2])

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        var anchorComponents = components
        anchorComponents.calendar = utc
        anchorComponents.timeZone = utc.timeZone
        guard
            let civilAsUTC = utc.date(from: anchorComponents),
            let anchor = utc.date(byAdding: .day, value: -2, to: civilAsUTC)
        else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let first = calendar.nextDate(
            after: anchor,
            matching: components,
            matchingPolicy: .strict,
            repeatedTimePolicy: .first,
            direction: .forward
        )
        let last = calendar.nextDate(
            after: anchor,
            matching: components,
            matchingPolicy: .strict,
            repeatedTimePolicy: .last,
            direction: .forward
        )
        guard let first, let last, first == last else { return nil }
        return first
    }
}
