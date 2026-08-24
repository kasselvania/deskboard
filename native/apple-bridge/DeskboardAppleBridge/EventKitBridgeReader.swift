import EventKit
import Foundation

enum BridgePermissionState: String, Codable, CaseIterable {
    case notDetermined
    case denied
    case restricted
    case granted
    case unavailable
}

struct BridgeSourceDescriptor: Equatable {
    let entityType: BridgeSourceEntity
    let sourceContainerId: String
    let localDisplayName: String
}

enum EventKitBridgeReaderError: Error, LocalizedError {
    case permissionUnavailable
    case sourceUnavailable
    case readFailed
    case unsupportedStatus

    var errorDescription: String? {
        switch self {
        case .permissionUnavailable: "The selected permission is unavailable."
        case .sourceUnavailable: "A selected source is unavailable."
        case .readFailed: "The selected source could not be read completely."
        case .unsupportedStatus: "A Calendar status could not be normalized safely."
        }
    }
}

protocol AppleSourceReading: AnyObject {
    func permissionState(for entity: BridgeSourceEntity) -> BridgePermissionState
    func requestPermission(for entity: BridgeSourceEntity) async -> BridgePermissionState
    func availableSources(for entity: BridgeSourceEntity) -> [BridgeSourceDescriptor]
    func readReminderSource(sourceContainerId: String) async throws -> ReminderSourceRead
    func readCalendarSource(
        sourceContainerId: String,
        now: Date,
        windowTimeZone: TimeZone
    ) throws -> CalendarSourceRead
}

final class EventKitBridgeReader: AppleSourceReading {
    private let store: EKEventStore

    init(store: EKEventStore = EKEventStore()) {
        self.store = store
    }

    func permissionState(for entity: BridgeSourceEntity) -> BridgePermissionState {
        let type: EKEntityType = entity == .calendar ? .event : .reminder
        switch EKEventStore.authorizationStatus(for: type) {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .restricted: return .restricted
        case .fullAccess: return .granted
        case .writeOnly: return .unavailable
        @unknown default: return .unavailable
        }
    }

    func requestPermission(for entity: BridgeSourceEntity) async -> BridgePermissionState {
        do {
            if entity == .calendar {
                _ = try await store.requestFullAccessToEvents()
            } else {
                _ = try await store.requestFullAccessToReminders()
            }
        } catch {
            return permissionState(for: entity)
        }
        return permissionState(for: entity)
    }

    func availableSources(for entity: BridgeSourceEntity) -> [BridgeSourceDescriptor] {
        guard permissionState(for: entity) == .granted else { return [] }
        let eventKitEntity: EKEntityType = entity == .calendar ? .event : .reminder
        return store.calendars(for: eventKitEntity)
            .map {
                BridgeSourceDescriptor(
                    entityType: entity,
                    sourceContainerId: $0.calendarIdentifier,
                    localDisplayName: $0.title
                )
            }
            .sorted {
                if $0.localDisplayName != $1.localDisplayName {
                    return $0.localDisplayName.localizedStandardCompare($1.localDisplayName)
                        == .orderedAscending
                }
                return $0.sourceContainerId.unicodeScalars.map(\.value)
                    .lexicographicallyPrecedes($1.sourceContainerId.unicodeScalars.map(\.value))
            }
    }

    func readReminderSource(sourceContainerId: String) async throws -> ReminderSourceRead {
        guard permissionState(for: .reminder) == .granted else {
            throw EventKitBridgeReaderError.permissionUnavailable
        }
        guard let calendar = store.calendars(for: .reminder).first(where: {
            $0.calendarIdentifier == sourceContainerId
        }) else {
            throw EventKitBridgeReaderError.sourceUnavailable
        }
        let predicate = store.predicateForReminders(in: [calendar])
        let reminders: [EKReminder] = try await withCheckedThrowingContinuation { continuation in
            store.fetchReminders(matching: predicate) { values in
                guard let values else {
                    continuation.resume(throwing: EventKitBridgeReaderError.readFailed)
                    return
                }
                continuation.resume(returning: values)
            }
        }
        return ReminderSourceRead(
            sourceContainerId: calendar.calendarIdentifier,
            allowsContentModifications: calendar.allowsContentModifications,
            records: reminders.map {
                ReminderRecordRead(
                    localIdentifier: $0.calendarItemIdentifier,
                    externalIdentifier: $0.calendarItemExternalIdentifier,
                    title: $0.title,
                    startComponents: $0.startDateComponents,
                    dueComponents: $0.dueDateComponents,
                    isCompleted: $0.isCompleted,
                    completionDate: $0.completionDate
                )
            }
        )
    }

    func readCalendarSource(
        sourceContainerId: String,
        now: Date,
        windowTimeZone: TimeZone
    ) throws -> CalendarSourceRead {
        guard permissionState(for: .calendar) == .granted else {
            throw EventKitBridgeReaderError.permissionUnavailable
        }
        guard let calendar = store.calendars(for: .event).first(where: {
            $0.calendarIdentifier == sourceContainerId
        }) else {
            throw EventKitBridgeReaderError.sourceUnavailable
        }
        let window = try CalendarWindowPolicy.window(now: now, timeZone: windowTimeZone)
        let predicate = store.predicateForEvents(
            withStart: window.start,
            end: window.end,
            calendars: [calendar]
        )
        let records = try store.events(matching: predicate).map { event in
            CalendarRecordRead(
                localIdentifier: event.calendarItemIdentifier,
                eventIdentifier: event.eventIdentifier,
                externalIdentifier: event.calendarItemExternalIdentifier,
                title: event.title,
                temporal: event.isAllDay
                    ? .allDay(start: event.startDate, end: event.endDate)
                    : .timed(
                        start: event.startDate,
                        end: event.endDate,
                        timeZone: event.timeZone
                    ),
                occurrenceDate: event.occurrenceDate,
                isDetached: event.isDetached,
                status: try normalizedStatus(event.status)
            )
        }
        return CalendarSourceRead(
            sourceContainerId: calendar.calendarIdentifier,
            allowsContentModifications: calendar.allowsContentModifications,
            isSubscribed: calendar.isSubscribed,
            windowStart: window.start,
            windowEnd: window.end,
            windowTimeZone: windowTimeZone,
            records: records
        )
    }

    private func normalizedStatus(_ status: EKEventStatus) throws -> AppleCalendarStatusV1 {
        switch status {
        case .none: return .none
        case .confirmed: return .confirmed
        case .tentative: return .tentative
        case .canceled: return .canceled
        @unknown default: throw EventKitBridgeReaderError.unsupportedStatus
        }
    }
}
