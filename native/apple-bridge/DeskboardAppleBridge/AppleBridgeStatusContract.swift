import CoreFoundation
import Foundation

enum AppleBridgeStatusContractError: Error {
    case invalid
}

struct AppleBridgeStatusPermissionsV1: Codable, Equatable {
    let calendar: BridgePermissionState
    let reminders: BridgePermissionState
}

struct AppleBridgeSelectedSourceStatusV1: Codable, Equatable {
    let entityType: BridgeSourceEntity
    let sourceContainerId: String
    let status: BridgeSourceStatus
    let acknowledgedSourceRevision: Int
    let pendingSourceRevision: Int?
    let lastAttemptedAt: String?
    let lastAcknowledgedAt: String?

    var coordinate: BridgeSourceCoordinate {
        BridgeSourceCoordinate(
            entityType: entityType,
            sourceContainerId: sourceContainerId
        )
    }
}

struct AppleBridgeStatusSnapshotV1: Codable, Equatable {
    let schemaVersion: Int
    let bridgeId: String
    let statusRevision: Int
    let capturedAt: String
    let permissions: AppleBridgeStatusPermissionsV1
    let selectedSources: [AppleBridgeSelectedSourceStatusV1]

    func validate() throws {
        guard
            schemaVersion == 1,
            !bridgeId.isEmpty,
            statusRevision > 0,
            statusRevision <= BridgeProductionLimits.maximumSafeSourceRevision,
            let captureInstant = BridgeStatusInstant.parse(capturedAt)
        else {
            throw AppleBridgeStatusContractError.invalid
        }

        for (index, source) in selectedSources.enumerated() {
            guard
                !source.sourceContainerId.isEmpty,
                source.acknowledgedSourceRevision >= 0,
                source.acknowledgedSourceRevision
                    <= BridgeProductionLimits.maximumSafeSourceRevision
            else {
                throw AppleBridgeStatusContractError.invalid
            }

            let hasPending = source.pendingSourceRevision != nil
            if let pending = source.pendingSourceRevision {
                guard
                    pending == source.acknowledgedSourceRevision + 1,
                    pending <= BridgeProductionLimits.maximumSafeSourceRevision,
                    source.lastAttemptedAt != nil
                else {
                    throw AppleBridgeStatusContractError.invalid
                }
            }

            let pendingRequired: Set<BridgeSourceStatus> = [
                .blockedTruncated,
                .operatorActionStale,
                .operatorActionConflict,
                .retryPending,
            ]
            let pendingForbidden: Set<BridgeSourceStatus> = [
                .idle,
                .applied,
                .unchangedDuplicate,
                .permissionUnavailable,
                .sourceUnavailable,
            ]
            guard
                !pendingRequired.contains(source.status) || hasPending,
                !pendingForbidden.contains(source.status) || !hasPending
            else {
                throw AppleBridgeStatusContractError.invalid
            }

            if source.acknowledgedSourceRevision == 0 {
                guard source.lastAcknowledgedAt == nil else {
                    throw AppleBridgeStatusContractError.invalid
                }
            } else {
                guard source.lastAcknowledgedAt != nil else {
                    throw AppleBridgeStatusContractError.invalid
                }
            }

            if source.status == .applied || source.status == .unchangedDuplicate {
                guard
                    source.acknowledgedSourceRevision > 0,
                    source.lastAttemptedAt != nil
                else {
                    throw AppleBridgeStatusContractError.invalid
                }
            }
            if source.status == .idle {
                guard
                    source.acknowledgedSourceRevision == 0,
                    source.lastAttemptedAt == nil,
                    source.lastAcknowledgedAt == nil
                else {
                    throw AppleBridgeStatusContractError.invalid
                }
            }

            for instantValue in [source.lastAttemptedAt, source.lastAcknowledgedAt] {
                guard let instantValue else { continue }
                guard
                    let instant = BridgeStatusInstant.parse(instantValue),
                    instant <= captureInstant
                else {
                    throw AppleBridgeStatusContractError.invalid
                }
            }

            if index > 0 {
                let previous = selectedSources[index - 1]
                guard BridgeSourceCoordinate.ordered(previous.coordinate, source.coordinate) else {
                    throw AppleBridgeStatusContractError.invalid
                }
            }
        }
    }
}

enum AppleBridgeStatusContractDecoder {
    static func decode(_ data: Data) throws -> AppleBridgeStatusSnapshotV1 {
        let json = try JSONSerialization.jsonObject(with: data)
        try StrictBridgeStatusJSON.validate(json)
        do {
            let snapshot = try JSONDecoder().decode(
                AppleBridgeStatusSnapshotV1.self,
                from: data
            )
            try snapshot.validate()
            return snapshot
        } catch {
            throw AppleBridgeStatusContractError.invalid
        }
    }
}

enum AppleBridgeStatusEnvelopeCodec {
    static func encode(_ snapshot: AppleBridgeStatusSnapshotV1) throws -> Data {
        try snapshot.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(snapshot)
        guard data.count <= BridgeProductionLimits.maximumEncodedStatusEnvelopeBytes else {
            throw BridgeWireError.statusEnvelopeTooLarge
        }
        guard try decode(data) == snapshot else {
            throw BridgeWireError.invalidEnvelope
        }
        return data
    }

    static func decode(_ data: Data) throws -> AppleBridgeStatusSnapshotV1 {
        guard data.count <= BridgeProductionLimits.maximumEncodedStatusEnvelopeBytes else {
            throw BridgeWireError.statusEnvelopeTooLarge
        }
        return try AppleBridgeStatusContractDecoder.decode(data)
    }
}

enum AppleBridgeStatusApplyResultKind: String, Codable, CaseIterable {
    case applied
    case unchangedDuplicate
    case rejectedStale
    case rejectedRevisionConflict
    case rejectedInvalid
}

struct AppleBridgeStatusApplyResponse: Equatable {
    let kind: AppleBridgeStatusApplyResultKind
    let statusRevision: Int?

    var expectedHTTPStatus: Int {
        switch kind {
        case .applied, .unchangedDuplicate: 200
        case .rejectedStale, .rejectedRevisionConflict: 409
        case .rejectedInvalid: 400
        }
    }
}

enum AppleBridgeStatusApplyResponseCodec {
    static func decode(_ data: Data) throws -> AppleBridgeStatusApplyResponse {
        guard data.count <= BridgeProductionLimits.maximumResponseBytes else {
            throw BridgeWireError.invalidResponse
        }
        let value = try JSONSerialization.jsonObject(with: data)
        guard
            let root = value as? [String: Any],
            let rawKind = root["kind"] as? String,
            let kind = AppleBridgeStatusApplyResultKind(rawValue: rawKind)
        else {
            throw BridgeWireError.invalidResponse
        }
        if kind == .rejectedInvalid {
            guard Set(root.keys) == ["kind"] else {
                throw BridgeWireError.invalidResponse
            }
            return AppleBridgeStatusApplyResponse(kind: kind, statusRevision: nil)
        }
        guard
            Set(root.keys) == ["kind", "statusRevision"],
            let statusRevision = safePositiveRevision(root["statusRevision"])
        else {
            throw BridgeWireError.invalidResponse
        }
        return AppleBridgeStatusApplyResponse(
            kind: kind,
            statusRevision: statusRevision
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

private enum StrictBridgeStatusJSON {
    private typealias JSONObject = [String: Any]

    static func validate(_ value: Any) throws {
        try rejectNull(value)
        guard let root = value as? JSONObject else {
            throw AppleBridgeStatusContractError.invalid
        }
        guard Set(root.keys) == [
            "schemaVersion",
            "bridgeId",
            "statusRevision",
            "capturedAt",
            "permissions",
            "selectedSources",
        ] else {
            throw AppleBridgeStatusContractError.invalid
        }
        guard
            let permissions = root["permissions"] as? JSONObject,
            Set(permissions.keys) == ["calendar", "reminders"],
            let selectedSources = root["selectedSources"] as? [Any]
        else {
            throw AppleBridgeStatusContractError.invalid
        }

        let requiredSourceKeys: Set<String> = [
            "entityType",
            "sourceContainerId",
            "status",
            "acknowledgedSourceRevision",
        ]
        let allowedSourceKeys = requiredSourceKeys.union([
            "pendingSourceRevision",
            "lastAttemptedAt",
            "lastAcknowledgedAt",
        ])
        for value in selectedSources {
            guard let source = value as? JSONObject else {
                throw AppleBridgeStatusContractError.invalid
            }
            let keys = Set(source.keys)
            guard
                requiredSourceKeys.isSubset(of: keys),
                keys.isSubset(of: allowedSourceKeys)
            else {
                throw AppleBridgeStatusContractError.invalid
            }
        }
    }

    private static func rejectNull(_ value: Any) throws {
        if value is NSNull {
            throw AppleBridgeStatusContractError.invalid
        }
        if let array = value as? [Any] {
            try array.forEach(rejectNull)
        } else if let object = value as? JSONObject {
            try object.values.forEach(rejectNull)
        }
    }
}

private enum BridgeStatusInstant {
    private static let pattern = try! NSRegularExpression(
        pattern: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?(?:Z|[+-]\d{2}:\d{2})$"#
    )
    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let wholeSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ value: String) -> Date? {
        let range = NSRange(value.startIndex..., in: value)
        guard pattern.firstMatch(in: value, range: range)?.range == range else {
            return nil
        }
        if let offsetMarker = value.lastIndex(where: { $0 == "+" || $0 == "-" }),
           offsetMarker > value.firstIndex(of: "T") ?? value.startIndex
        {
            let offset = value[offsetMarker...]
            let fields = offset.dropFirst().split(separator: ":")
            guard
                fields.count == 2,
                let hours = Int(fields[0]),
                let minutes = Int(fields[1]),
                hours <= 23,
                minutes <= 59
            else {
                return nil
            }
        }
        return fractional.date(from: value) ?? wholeSeconds.date(from: value)
    }
}
