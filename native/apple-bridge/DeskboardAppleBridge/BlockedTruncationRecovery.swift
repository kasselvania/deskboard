import Foundation

enum BlockedTruncationRecoveryResult: String, Equatable {
    case replacementPersisted
    case stillTruncated
    case operatorActionRequired
}

struct PersistedBlockedTruncationReplacement: Equatable {
    let coordinate: BridgeSourceCoordinate
    let sourceRevision: Int
}

enum BlockedTruncationRecoveryOutcome: Equatable {
    case replacementPersisted(PersistedBlockedTruncationReplacement)
    case stillTruncated
    case operatorActionRequired

    var result: BlockedTruncationRecoveryResult {
        switch self {
        case .replacementPersisted: .replacementPersisted
        case .stillTruncated: .stillTruncated
        case .operatorActionRequired: .operatorActionRequired
        }
    }
}

@MainActor
final class BlockedTruncationRecoveryCoordinator {
    private struct EligibleDelivery {
        let index: Int
        let coordinate: BridgeSourceCoordinate
        let pending: BridgePendingEnvelope
    }

    private let stateStore: BridgeStatePersisting
    private let sourceReader: AppleSourceReading
    private let clock: () -> Date

    init(
        stateStore: BridgeStatePersisting,
        sourceReader: AppleSourceReading,
        clock: @escaping () -> Date = Date.init
    ) {
        self.stateStore = stateStore
        self.sourceReader = sourceReader
        self.clock = clock
    }

    func eligibleReminderSourceIds() -> [String] {
        let state: BridgePersistentState
        do {
            state = try stateStore.loadOrCreate()
            try state.validate()
        } catch {
            return []
        }
        return state.selectedReminderSourceIds.filter {
            eligibleDelivery(
                in: state,
                sourceContainerId: $0,
                requireCurrentAccess: true
            ) != nil
        }
    }

    func rebuildBlockedReminder(
        sourceContainerId: String
    ) async -> BlockedTruncationRecoveryOutcome {
        do {
            let original = try stateStore.loadOrCreate()
            try original.validate()
            guard let eligible = eligibleDelivery(
                in: original,
                sourceContainerId: sourceContainerId,
                requireCurrentAccess: true
            ) else {
                return .operatorActionRequired
            }

            let source = try await sourceReader.readReminderSource(
                sourceContainerId: sourceContainerId
            )
            let snapshot = try AppleSourceConverter.reminderSnapshot(
                from: source,
                bridgeId: original.bridgeId,
                capturedAt: clock(),
                maximumRecords:
                    BridgeProductionLimits.maximumRetainedReminderRecordsPerSource
            )
            guard !snapshot.truncated else {
                return .stillTruncated
            }
            guard
                snapshot.bridgeId == original.bridgeId,
                snapshot.entityType == eligible.coordinate.entityType,
                snapshot.sourceContainerId == eligible.coordinate.sourceContainerId
            else {
                return .operatorActionRequired
            }

            let replacementEnvelope = AppleSourceOperationalEnvelopeV1(
                sourceRevision: eligible.pending.sourceRevision,
                snapshot: snapshot
            )
            let replacementBytes = try AppleSourceEnvelopeCodec.encode(
                replacementEnvelope
            )
            guard
                replacementBytes.count
                    <= BridgeProductionLimits.maximumEncodedEnvelopeBytes,
                try AppleSourceEnvelopeCodec.decode(replacementBytes)
                    == replacementEnvelope
            else {
                return .operatorActionRequired
            }

            // Re-read after the asynchronous source operation. Any concurrent
            // state or prerequisite change refuses replacement rather than
            // overwriting newer state.
            let current = try stateStore.loadOrCreate()
            guard current == original,
                  let currentEligible = eligibleDelivery(
                      in: current,
                      sourceContainerId: sourceContainerId,
                      requireCurrentAccess: true
                  ),
                  currentEligible.index == eligible.index,
                  currentEligible.pending == eligible.pending
            else {
                return .operatorActionRequired
            }

            var replacement = current
            replacement.deliveries[currentEligible.index].pending =
                BridgePendingEnvelope(
                    sourceRevision: currentEligible.pending.sourceRevision,
                    encodedEnvelope: replacementBytes
                )
            replacement.deliveries[currentEligible.index].status = .retryPending
            try replacement.validate()
            try stateStore.save(replacement)

            return .replacementPersisted(
                PersistedBlockedTruncationReplacement(
                    coordinate: currentEligible.coordinate,
                    sourceRevision: currentEligible.pending.sourceRevision
                )
            )
        } catch {
            return .operatorActionRequired
        }
    }

    private func eligibleDelivery(
        in state: BridgePersistentState,
        sourceContainerId: String,
        requireCurrentAccess: Bool
    ) -> EligibleDelivery? {
        let coordinate = BridgeSourceCoordinate(
            entityType: .reminder,
            sourceContainerId: sourceContainerId
        )
        guard
            state.selectedReminderSourceIds.contains(sourceContainerId),
            let index = state.deliveries.firstIndex(where: {
                $0.coordinate == coordinate
            })
        else {
            return nil
        }
        let delivery = state.deliveries[index]
        guard
            delivery.status == .blockedTruncated,
            let pending = delivery.pending,
            pending.sourceRevision == delivery.acknowledgedRevision + 1,
            let envelope = try? AppleSourceEnvelopeCodec.decode(
                pending.encodedEnvelope
            ),
            envelope.sourceRevision == pending.sourceRevision,
            envelope.snapshot.truncated,
            envelope.snapshot.bridgeId == state.bridgeId,
            envelope.snapshot.entityType == coordinate.entityType,
            envelope.snapshot.sourceContainerId == coordinate.sourceContainerId
        else {
            return nil
        }
        if requireCurrentAccess {
            guard
                sourceReader.permissionState(for: .reminder) == .granted,
                sourceReader.availableSources(for: .reminder).contains(where: {
                    $0.sourceContainerId == sourceContainerId
                })
            else {
                return nil
            }
        }
        return EligibleDelivery(
            index: index,
            coordinate: coordinate,
            pending: pending
        )
    }
}
