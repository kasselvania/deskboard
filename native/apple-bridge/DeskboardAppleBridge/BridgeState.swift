import Foundation

enum BridgeStateError: Error, LocalizedError {
    case unavailable
    case invalid

    var errorDescription: String? {
        switch self {
        case .unavailable: "Bridge state is unavailable."
        case .invalid: "Bridge state is invalid and requires operator action."
        }
    }
}

struct BridgeSourceCoordinate: Codable, Equatable, Hashable {
    let entityType: BridgeSourceEntity
    let sourceContainerId: String

    static func ordered(_ left: BridgeSourceCoordinate, _ right: BridgeSourceCoordinate) -> Bool {
        if left.entityType.rawValue != right.entityType.rawValue {
            return left.entityType.rawValue < right.entityType.rawValue
        }
        return unicodeScalarLess(left.sourceContainerId, right.sourceContainerId)
    }

    private static func unicodeScalarLess(_ left: String, _ right: String) -> Bool {
        left.unicodeScalars.map(\.value).lexicographicallyPrecedes(
            right.unicodeScalars.map(\.value)
        )
    }
}

enum BridgeSourceStatus: String, Codable, CaseIterable {
    case idle
    case applied
    case unchangedDuplicate
    case blockedTruncated
    case blockedInvalid
    case operatorActionStale
    case operatorActionConflict
    case retryPending
    case permissionUnavailable
    case sourceUnavailable
}

struct BridgePendingEnvelope: Codable, Equatable {
    let sourceRevision: Int
    let encodedEnvelope: Data
}

struct BridgePendingStatusEnvelope: Codable, Equatable {
    let statusRevision: Int
    let encodedEnvelope: Data
}

enum BridgeStatusDeliveryResult: String, Codable, CaseIterable {
    case idle
    case applied
    case unchangedDuplicate
    case blockedInvalid
    case operatorActionStale
    case operatorActionConflict
    case retryPending
}

struct BridgeSourceDeliveryState: Codable, Equatable {
    let coordinate: BridgeSourceCoordinate
    var acknowledgedRevision: Int
    var pending: BridgePendingEnvelope?
    var status: BridgeSourceStatus
    var lastAttemptedAt: Date?
    var lastAcknowledgedAt: Date?
}

struct BridgePersistentState: Codable, Equatable {
    static let schemaVersion = 1

    let version: Int
    let bridgeId: String
    var selectedCalendarSourceIds: [String]
    var selectedReminderSourceIds: [String]
    var coreOrigin: String?
    var deliveries: [BridgeSourceDeliveryState]
    var acknowledgedStatusRevision: Int
    var pendingStatus: BridgePendingStatusEnvelope?
    var statusDeliveryResult: BridgeStatusDeliveryResult

    private enum CodingKeys: String, CodingKey {
        case version
        case bridgeId
        case selectedCalendarSourceIds
        case selectedReminderSourceIds
        case coreOrigin
        case deliveries
        case acknowledgedStatusRevision
        case pendingStatus
        case statusDeliveryResult
    }

    init(
        version: Int,
        bridgeId: String,
        selectedCalendarSourceIds: [String],
        selectedReminderSourceIds: [String],
        coreOrigin: String?,
        deliveries: [BridgeSourceDeliveryState],
        acknowledgedStatusRevision: Int = 0,
        pendingStatus: BridgePendingStatusEnvelope? = nil,
        statusDeliveryResult: BridgeStatusDeliveryResult = .idle
    ) {
        self.version = version
        self.bridgeId = bridgeId
        self.selectedCalendarSourceIds = selectedCalendarSourceIds
        self.selectedReminderSourceIds = selectedReminderSourceIds
        self.coreOrigin = coreOrigin
        self.deliveries = deliveries
        self.acknowledgedStatusRevision = acknowledgedStatusRevision
        self.pendingStatus = pendingStatus
        self.statusDeliveryResult = statusDeliveryResult
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        bridgeId = try container.decode(String.self, forKey: .bridgeId)
        selectedCalendarSourceIds = try container.decode(
            [String].self,
            forKey: .selectedCalendarSourceIds
        )
        selectedReminderSourceIds = try container.decode(
            [String].self,
            forKey: .selectedReminderSourceIds
        )
        coreOrigin = try container.decodeIfPresent(String.self, forKey: .coreOrigin)
        deliveries = try container.decode(
            [BridgeSourceDeliveryState].self,
            forKey: .deliveries
        )
        acknowledgedStatusRevision = try container.decodeIfPresent(
            Int.self,
            forKey: .acknowledgedStatusRevision
        ) ?? 0
        pendingStatus = try container.decodeIfPresent(
            BridgePendingStatusEnvelope.self,
            forKey: .pendingStatus
        )
        statusDeliveryResult = try container.decodeIfPresent(
            BridgeStatusDeliveryResult.self,
            forKey: .statusDeliveryResult
        ) ?? .idle
    }

    static func fresh(bridgeId: String = UUID().uuidString.lowercased()) -> BridgePersistentState {
        BridgePersistentState(
            version: schemaVersion,
            bridgeId: bridgeId,
            selectedCalendarSourceIds: [],
            selectedReminderSourceIds: [],
            coreOrigin: nil,
            deliveries: [],
            acknowledgedStatusRevision: 0,
            pendingStatus: nil,
            statusDeliveryResult: .idle
        )
    }

    mutating func setSelections(_ sourceIds: Set<String>, for entity: BridgeSourceEntity) {
        let sorted = sourceIds.sorted(by: Self.unicodeScalarLess)
        switch entity {
        case .calendar: selectedCalendarSourceIds = sorted
        case .reminder: selectedReminderSourceIds = sorted
        }
    }

    func selections(for entity: BridgeSourceEntity) -> [String] {
        switch entity {
        case .calendar: selectedCalendarSourceIds
        case .reminder: selectedReminderSourceIds
        }
    }

    mutating func deliveryState(for coordinate: BridgeSourceCoordinate) -> BridgeSourceDeliveryState {
        if let existing = deliveries.first(where: { $0.coordinate == coordinate }) {
            return existing
        }
        let created = BridgeSourceDeliveryState(
            coordinate: coordinate,
            acknowledgedRevision: 0,
            pending: nil,
            status: .idle,
            lastAttemptedAt: nil,
            lastAcknowledgedAt: nil
        )
        deliveries.append(created)
        deliveries.sort { BridgeSourceCoordinate.ordered($0.coordinate, $1.coordinate) }
        return created
    }

    mutating func replaceDeliveryState(_ replacement: BridgeSourceDeliveryState) {
        if let index = deliveries.firstIndex(where: { $0.coordinate == replacement.coordinate }) {
            deliveries[index] = replacement
        } else {
            deliveries.append(replacement)
        }
        deliveries.sort { BridgeSourceCoordinate.ordered($0.coordinate, $1.coordinate) }
    }

    func validate() throws {
        guard version == Self.schemaVersion, !bridgeId.isEmpty else {
            throw BridgeStateError.invalid
        }
        guard
            selectedCalendarSourceIds == Set(selectedCalendarSourceIds).sorted(by: Self.unicodeScalarLess),
            selectedReminderSourceIds == Set(selectedReminderSourceIds).sorted(by: Self.unicodeScalarLess),
            deliveries == deliveries.sorted(by: {
                BridgeSourceCoordinate.ordered($0.coordinate, $1.coordinate)
            }),
            Set(deliveries.map(\.coordinate)).count == deliveries.count
        else {
            throw BridgeStateError.invalid
        }
        if let coreOrigin {
            _ = try CoreIngestionEndpoint(origin: coreOrigin)
        }
        guard
            acknowledgedStatusRevision >= 0,
            acknowledgedStatusRevision <= BridgeProductionLimits.maximumSafeSourceRevision
        else {
            throw BridgeStateError.invalid
        }

        let statusResultsRequiringPending: Set<BridgeStatusDeliveryResult> = [
            .blockedInvalid,
            .operatorActionStale,
            .operatorActionConflict,
            .retryPending,
        ]
        if let pendingStatus {
            guard
                statusResultsRequiringPending.contains(statusDeliveryResult),
                pendingStatus.statusRevision == acknowledgedStatusRevision + 1,
                pendingStatus.statusRevision
                    <= BridgeProductionLimits.maximumSafeSourceRevision,
                pendingStatus.encodedEnvelope.count
                    <= BridgeProductionLimits.maximumEncodedStatusEnvelopeBytes
            else {
                throw BridgeStateError.invalid
            }
            let snapshot = try AppleBridgeStatusEnvelopeCodec.decode(
                pendingStatus.encodedEnvelope
            )
            guard
                snapshot.bridgeId == bridgeId,
                snapshot.statusRevision == pendingStatus.statusRevision
            else {
                throw BridgeStateError.invalid
            }
        } else if statusResultsRequiringPending.contains(statusDeliveryResult) {
            throw BridgeStateError.invalid
        }

        for delivery in deliveries {
            guard
                !delivery.coordinate.sourceContainerId.isEmpty,
                delivery.acknowledgedRevision >= 0,
                delivery.acknowledgedRevision <= BridgeProductionLimits.maximumSafeSourceRevision
            else {
                throw BridgeStateError.invalid
            }
            guard let pending = delivery.pending else { continue }
            guard
                pending.sourceRevision == delivery.acknowledgedRevision + 1,
                pending.sourceRevision <= BridgeProductionLimits.maximumSafeSourceRevision,
                pending.encodedEnvelope.count <= BridgeProductionLimits.maximumEncodedEnvelopeBytes
            else {
                throw BridgeStateError.invalid
            }
            let envelope = try AppleSourceEnvelopeCodec.decode(pending.encodedEnvelope)
            guard
                envelope.sourceRevision == pending.sourceRevision,
                envelope.snapshot.bridgeId == bridgeId,
                envelope.snapshot.entityType == delivery.coordinate.entityType,
                envelope.snapshot.sourceContainerId == delivery.coordinate.sourceContainerId
            else {
                throw BridgeStateError.invalid
            }
        }
    }

    private static func unicodeScalarLess(_ left: String, _ right: String) -> Bool {
        left.unicodeScalars.map(\.value).lexicographicallyPrecedes(
            right.unicodeScalars.map(\.value)
        )
    }
}

protocol BridgeStatePersisting: AnyObject {
    func loadOrCreate() throws -> BridgePersistentState
    func save(_ state: BridgePersistentState) throws
    func reset() throws -> BridgePersistentState
}

final class AtomicBridgeStateFileStore: BridgeStatePersisting {
    let stateURL: URL

    init(stateURL: URL = AtomicBridgeStateFileStore.defaultStateURL()) {
        self.stateURL = stateURL
    }

    func loadOrCreate() throws -> BridgePersistentState {
        if !FileManager.default.fileExists(atPath: stateURL.path) {
            let state = BridgePersistentState.fresh()
            try save(state)
            return state
        }
        do {
            let data = try Data(contentsOf: stateURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let state = try decoder.decode(BridgePersistentState.self, from: data)
            try state.validate()
            return state
        } catch {
            throw BridgeStateError.invalid
        }
    }

    func save(_ state: BridgePersistentState) throws {
        do {
            try state.validate()
            let directory = stateURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(state).write(to: stateURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: stateURL.path
            )
        } catch let error as BridgeStateError {
            throw error
        } catch {
            throw BridgeStateError.unavailable
        }
    }

    func reset() throws -> BridgePersistentState {
        let replacement = BridgePersistentState.fresh()
        try save(replacement)
        return replacement
    }

    static func defaultSupportDirectoryURL() -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return base
            .appendingPathComponent("DeskboardAppleBridge", isDirectory: true)
    }

    private static func defaultStateURL() -> URL {
        defaultSupportDirectoryURL()
            .appendingPathComponent("bridge-state-v1.json", isDirectory: false)
    }
}
