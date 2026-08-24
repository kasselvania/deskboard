import CoreFoundation
import Foundation

enum BridgeWireError: Error, LocalizedError {
    case invalidEnvelope
    case envelopeTooLarge
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidEnvelope: "The pending delivery envelope is invalid."
        case .envelopeTooLarge: "The source snapshot exceeds the delivery limit."
        case .invalidResponse: "Core returned an invalid delivery response."
        }
    }
}

enum BridgeSourceEntity: String, Codable, CaseIterable, Hashable {
    case reminder
    case calendar
}

enum AppleSourceSnapshotValueV1: Equatable, Encodable {
    case reminder(AppleReminderSourceSnapshotV1)
    case calendar(AppleCalendarSourceSnapshotV1)

    var entityType: BridgeSourceEntity {
        switch self {
        case .reminder: .reminder
        case .calendar: .calendar
        }
    }

    var bridgeId: String {
        switch self {
        case let .reminder(snapshot): snapshot.bridgeId
        case let .calendar(snapshot): snapshot.bridgeId
        }
    }

    var sourceContainerId: String {
        switch self {
        case let .reminder(snapshot): snapshot.source.sourceContainerId
        case let .calendar(snapshot): snapshot.source.sourceContainerId
        }
    }

    var matchedCount: Int {
        switch self {
        case let .reminder(snapshot): snapshot.matchedCount
        case let .calendar(snapshot): snapshot.matchedCount
        }
    }

    var retainedCount: Int {
        switch self {
        case let .reminder(snapshot): snapshot.records.count
        case let .calendar(snapshot): snapshot.records.count
        }
    }

    var truncated: Bool {
        switch self {
        case let .reminder(snapshot): snapshot.truncated
        case let .calendar(snapshot): snapshot.truncated
        }
    }

    func validate() throws {
        switch self {
        case let .reminder(snapshot): try snapshot.validate()
        case let .calendar(snapshot): try snapshot.validate()
        }
    }

    func retainingPrefix(_ count: Int) throws -> AppleSourceSnapshotValueV1 {
        guard count >= 0, count <= retainedCount else {
            throw BridgeWireError.invalidEnvelope
        }
        switch self {
        case let .reminder(snapshot):
            let replacement = AppleReminderSourceSnapshotV1(
                schemaVersion: snapshot.schemaVersion,
                entityType: snapshot.entityType,
                bridgeId: snapshot.bridgeId,
                source: snapshot.source,
                capturedAt: snapshot.capturedAt,
                matchedCount: snapshot.matchedCount,
                truncated: count < snapshot.matchedCount,
                records: Array(snapshot.records.prefix(count))
            )
            try replacement.validate()
            return .reminder(replacement)
        case let .calendar(snapshot):
            let replacement = AppleCalendarSourceSnapshotV1(
                schemaVersion: snapshot.schemaVersion,
                entityType: snapshot.entityType,
                bridgeId: snapshot.bridgeId,
                source: snapshot.source,
                capturedAt: snapshot.capturedAt,
                window: snapshot.window,
                matchedCount: snapshot.matchedCount,
                truncated: count < snapshot.matchedCount,
                records: Array(snapshot.records.prefix(count))
            )
            try replacement.validate()
            return .calendar(replacement)
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case let .reminder(snapshot): try snapshot.encode(to: encoder)
        case let .calendar(snapshot): try snapshot.encode(to: encoder)
        }
    }
}

struct AppleSourceOperationalEnvelopeV1: Equatable, Encodable {
    let sourceRevision: Int
    let snapshot: AppleSourceSnapshotValueV1

    private enum CodingKeys: String, CodingKey {
        case sourceRevision
        case snapshot
    }

    func validate() throws {
        guard
            sourceRevision > 0,
            sourceRevision <= BridgeProductionLimits.maximumSafeSourceRevision
        else {
            throw BridgeWireError.invalidEnvelope
        }
        try snapshot.validate()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sourceRevision, forKey: .sourceRevision)
        try container.encode(snapshot, forKey: .snapshot)
    }
}

enum AppleSourceEnvelopeCodec {
    static func encode(_ envelope: AppleSourceOperationalEnvelopeV1) throws -> Data {
        try envelope.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(envelope)
        guard try decode(data) == envelope else {
            throw BridgeWireError.invalidEnvelope
        }
        return data
    }

    static func encodeWithinProductionLimit(
        sourceRevision: Int,
        snapshot: AppleSourceSnapshotValueV1
    ) throws -> Data {
        var retainedCount = snapshot.retainedCount
        while true {
            let boundedSnapshot = try snapshot.retainingPrefix(retainedCount)
            let data = try encode(
                AppleSourceOperationalEnvelopeV1(
                    sourceRevision: sourceRevision,
                    snapshot: boundedSnapshot
                )
            )
            if data.count <= BridgeProductionLimits.maximumEncodedEnvelopeBytes {
                return data
            }
            guard retainedCount > 0 else {
                throw BridgeWireError.envelopeTooLarge
            }
            retainedCount -= 1
        }
    }

    static func decode(_ data: Data) throws -> AppleSourceOperationalEnvelopeV1 {
        let value = try JSONSerialization.jsonObject(with: data)
        guard
            let root = value as? [String: Any],
            Set(root.keys) == ["sourceRevision", "snapshot"],
            let sourceRevision = safeInteger(root["sourceRevision"]),
            sourceRevision > 0,
            sourceRevision <= BridgeProductionLimits.maximumSafeSourceRevision,
            let snapshotObject = root["snapshot"]
        else {
            throw BridgeWireError.invalidEnvelope
        }

        let snapshotData = try JSONSerialization.data(
            withJSONObject: snapshotObject,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        let validated = try AppleSourceContractDecoder.decode(snapshotData)
        let snapshot: AppleSourceSnapshotValueV1
        if let reminder = validated.reminderSnapshot {
            snapshot = .reminder(reminder)
        } else if let calendar = validated.calendarSnapshot {
            snapshot = .calendar(calendar)
        } else {
            throw BridgeWireError.invalidEnvelope
        }
        return AppleSourceOperationalEnvelopeV1(
            sourceRevision: sourceRevision,
            snapshot: snapshot
        )
    }

    private static func safeInteger(_ value: Any?) -> Int? {
        guard
            let number = value as? NSNumber,
            CFGetTypeID(number) != CFBooleanGetTypeID()
        else {
            return nil
        }
        let double = number.doubleValue
        guard
            double.isFinite,
            double.rounded(.towardZero) == double,
            double >= 0,
            double <= Double(BridgeProductionLimits.maximumSafeSourceRevision)
        else {
            return nil
        }
        return Int(double)
    }
}

enum AppleSourceApplyResultKind: String, Codable, CaseIterable {
    case applied
    case unchangedDuplicate
    case rejectedStale
    case rejectedRevisionConflict
    case rejectedTruncated
    case rejectedInvalid
}

struct AppleSourceApplyResponse: Equatable {
    let kind: AppleSourceApplyResultKind
    let entityType: BridgeSourceEntity?
    let sourceRevision: Int?

    var expectedHTTPStatus: Int {
        switch kind {
        case .applied, .unchangedDuplicate: 200
        case .rejectedStale, .rejectedRevisionConflict: 409
        case .rejectedTruncated: 422
        case .rejectedInvalid: 400
        }
    }
}

enum AppleSourceApplyResponseCodec {
    static func decode(_ data: Data) throws -> AppleSourceApplyResponse {
        guard data.count <= BridgeProductionLimits.maximumResponseBytes else {
            throw BridgeWireError.invalidResponse
        }
        let value = try JSONSerialization.jsonObject(with: data)
        guard
            let root = value as? [String: Any],
            let rawKind = root["kind"] as? String,
            let kind = AppleSourceApplyResultKind(rawValue: rawKind)
        else {
            throw BridgeWireError.invalidResponse
        }

        if kind == .rejectedInvalid {
            guard Set(root.keys) == ["kind"] else {
                throw BridgeWireError.invalidResponse
            }
            return AppleSourceApplyResponse(
                kind: kind,
                entityType: nil,
                sourceRevision: nil
            )
        }

        guard
            Set(root.keys) == ["kind", "entityType", "sourceRevision"],
            let rawEntity = root["entityType"] as? String,
            let entityType = BridgeSourceEntity(rawValue: rawEntity),
            let sourceRevision = safePositiveRevision(root["sourceRevision"])
        else {
            throw BridgeWireError.invalidResponse
        }
        return AppleSourceApplyResponse(
            kind: kind,
            entityType: entityType,
            sourceRevision: sourceRevision
        )
    }

    private static func safePositiveRevision(_ value: Any?) -> Int? {
        guard
            let number = value as? NSNumber,
            CFGetTypeID(number) != CFBooleanGetTypeID()
        else {
            return nil
        }
        let double = number.doubleValue
        guard
            double > 0,
            double.rounded(.towardZero) == double,
            double <= Double(BridgeProductionLimits.maximumSafeSourceRevision)
        else {
            return nil
        }
        return Int(double)
    }
}
