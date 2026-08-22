import Foundation

enum TemporalNormalizationError: Error, Equatable, LocalizedError {
    case missingDate
    case incompleteClock
    case invalidDate

    var errorDescription: String? {
        switch self {
        case .missingDate: "missing-date-components"
        case .incompleteClock: "incomplete-clock-components"
        case .invalidDate: "invalid-date-components"
        }
    }
}

enum TemporalNormalizer {
    static func reminderComponents(_ components: DateComponents?) throws -> ProbeReminderTemporal? {
        guard let components else { return nil }
        guard
            let year = components.year,
            let month = components.month,
            let day = components.day
        else {
            throw TemporalNormalizationError.missingDate
        }

        try validateDate(year: year, month: month, day: day)
        let date = formatDate(year: year, month: month, day: day)
        let clockValues = [components.hour, components.minute, components.second]

        if clockValues.allSatisfy({ $0 == nil }) {
            return .dateOnly(date)
        }

        guard let hour = components.hour, let minute = components.minute else {
            throw TemporalNormalizationError.incompleteClock
        }
        let second = components.second ?? 0
        guard (0 ... 23).contains(hour), (0 ... 59).contains(minute), (0 ... 59).contains(second) else {
            throw TemporalNormalizationError.invalidDate
        }

        let localDateTime = "\(date)T\(pad(hour)):\(pad(minute)):\(pad(second))"
        if let timeZone = components.timeZone {
            return .timeZoneDateTime(localDateTime, timeZone: timeZone.identifier)
        }
        return .localDateTime(localDateTime)
    }

    static func event(
        start: Date,
        end: Date,
        timeZone: TimeZone?,
        isAllDay: Bool,
        localTimeZone: TimeZone = .current
    ) -> ProbeEventTemporal {
        let displayTimeZone = timeZone ?? localTimeZone
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = displayTimeZone

        if isAllDay {
            return .allDayRange(
                startDate: formatDate(calendar.dateComponents([.year, .month, .day], from: start)),
                endDate: formatDate(calendar.dateComponents([.year, .month, .day], from: end))
            )
        }

        let startValue = formatDateTime(
            calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: start)
        )
        let endValue = formatDateTime(
            calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: end)
        )
        if let timeZone {
            return .timeZoneDateTime(
                start: startValue,
                end: endValue,
                timeZone: timeZone.identifier
            )
        }
        return .localDateTime(start: startValue, end: endValue)
    }

    private static func validateDate(year: Int, month: Int, day: Int) throws {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        guard let date = components.date else {
            throw TemporalNormalizationError.invalidDate
        }
        let result = components.calendar?.dateComponents([.year, .month, .day], from: date)
        guard result?.year == year, result?.month == month, result?.day == day else {
            throw TemporalNormalizationError.invalidDate
        }
    }

    private static func formatDate(_ components: DateComponents) -> String {
        formatDate(
            year: components.year ?? 0,
            month: components.month ?? 0,
            day: components.day ?? 0
        )
    }

    private static func formatDate(year: Int, month: Int, day: Int) -> String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    private static func formatDateTime(_ components: DateComponents) -> String {
        "\(formatDate(components))T\(pad(components.hour ?? 0)):\(pad(components.minute ?? 0)):\(pad(components.second ?? 0))"
    }

    private static func pad(_ value: Int) -> String {
        String(format: "%02d", value)
    }
}
