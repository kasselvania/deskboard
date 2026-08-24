import Foundation

enum ManualSyncError: Error, LocalizedError {
    case configurationRequired
    case alreadyInProgress
    case revisionExhausted

    var errorDescription: String? {
        switch self {
        case .configurationRequired: "Store a valid loopback Core origin before syncing."
        case .alreadyInProgress: "Manual synchronization is already in progress."
        case .revisionExhausted: "A source revision requires operator action."
        }
    }
}

@MainActor
final class ManualSyncCoordinator {
    private let stateStore: BridgeStatePersisting
    private let sourceReader: AppleSourceReading
    private let deliveryClient: AppleSourceDelivering
    private let clock: () -> Date
    private let windowTimeZone: () -> TimeZone
    private(set) var isInProgress = false

    init(
        stateStore: BridgeStatePersisting,
        sourceReader: AppleSourceReading,
        deliveryClient: AppleSourceDelivering,
        clock: @escaping () -> Date = Date.init,
        windowTimeZone: @escaping () -> TimeZone = { .current }
    ) {
        self.stateStore = stateStore
        self.sourceReader = sourceReader
        self.deliveryClient = deliveryClient
        self.clock = clock
        self.windowTimeZone = windowTimeZone
    }

    func syncNow() async throws -> BridgePersistentState {
        guard !isInProgress else { throw ManualSyncError.alreadyInProgress }
        isInProgress = true
        defer { isInProgress = false }

        var state = try stateStore.loadOrCreate()
        guard let origin = state.coreOrigin else {
            throw ManualSyncError.configurationRequired
        }
        let endpoint = try LoopbackIngestionEndpoint(origin: origin)

        let pendingCoordinates = state.deliveries
            .filter { $0.pending != nil }
            .map(\.coordinate)
            .sorted(by: BridgeSourceCoordinate.ordered)
        let retriedCoordinates = Set(pendingCoordinates)
        for coordinate in pendingCoordinates {
            try await attemptPending(
                coordinate: coordinate,
                endpoint: endpoint,
                state: &state
            )
        }

        for entity in [BridgeSourceEntity.calendar, .reminder] {
            let selections = state.selections(for: entity)
            for sourceContainerId in selections {
                let coordinate = BridgeSourceCoordinate(
                    entityType: entity,
                    sourceContainerId: sourceContainerId
                )
                if retriedCoordinates.contains(coordinate) {
                    continue
                }
                let current = state.deliveryState(for: coordinate)
                if current.pending != nil {
                    continue
                }
                guard sourceReader.permissionState(for: entity) == .granted else {
                    var blocked = current
                    blocked.status = .permissionUnavailable
                    state.replaceDeliveryState(blocked)
                    try stateStore.save(state)
                    continue
                }
                let available = sourceReader.availableSources(for: entity)
                guard available.contains(where: {
                    $0.sourceContainerId == sourceContainerId
                }) else {
                    var blocked = current
                    blocked.status = .sourceUnavailable
                    state.replaceDeliveryState(blocked)
                    try stateStore.save(state)
                    continue
                }

                do {
                    let snapshot: AppleSourceSnapshotValueV1
                    let capturedAt = clock()
                    if entity == .reminder {
                        let source = try await sourceReader.readReminderSource(
                            sourceContainerId: sourceContainerId
                        )
                        snapshot = try AppleSourceConverter.reminderSnapshot(
                            from: source,
                            bridgeId: state.bridgeId,
                            capturedAt: capturedAt
                        )
                    } else {
                        let source = try sourceReader.readCalendarSource(
                            sourceContainerId: sourceContainerId,
                            now: capturedAt,
                            windowTimeZone: windowTimeZone()
                        )
                        snapshot = try AppleSourceConverter.calendarSnapshot(
                            from: source,
                            bridgeId: state.bridgeId,
                            capturedAt: capturedAt
                        )
                    }
                    guard
                        current.acknowledgedRevision
                            < BridgeProductionLimits.maximumSafeSourceRevision
                    else {
                        throw ManualSyncError.revisionExhausted
                    }
                    let revision = current.acknowledgedRevision + 1
                    let encoded = try AppleSourceEnvelopeCodec.encodeWithinProductionLimit(
                        sourceRevision: revision,
                        snapshot: snapshot
                    )
                    var pendingState = current
                    pendingState.pending = BridgePendingEnvelope(
                        sourceRevision: revision,
                        encodedEnvelope: encoded
                    )
                    pendingState.status = .retryPending
                    pendingState.lastAttemptedAt = clock()
                    state.replaceDeliveryState(pendingState)
                    try stateStore.save(state)
                    try await attemptPending(
                        coordinate: coordinate,
                        endpoint: endpoint,
                        state: &state,
                        attemptAlreadyRecorded: true
                    )
                } catch let error as ManualSyncError {
                    throw error
                } catch {
                    var blocked = state.deliveryState(for: coordinate)
                    blocked.status = .blockedInvalid
                    state.replaceDeliveryState(blocked)
                    try stateStore.save(state)
                }
            }
        }

        return state
    }

    private func attemptPending(
        coordinate: BridgeSourceCoordinate,
        endpoint: LoopbackIngestionEndpoint,
        state: inout BridgePersistentState,
        attemptAlreadyRecorded: Bool = false
    ) async throws {
        var delivery = state.deliveryState(for: coordinate)
        guard let pending = delivery.pending else { return }
        if !attemptAlreadyRecorded {
            delivery.lastAttemptedAt = clock()
            delivery.status = .retryPending
            state.replaceDeliveryState(delivery)
            try stateStore.save(state)
        }

        let response: AppleSourceApplyResponse
        do {
            response = try await deliveryClient.deliver(
                envelopeData: pending.encodedEnvelope,
                endpoint: endpoint
            )
        } catch {
            delivery = state.deliveryState(for: coordinate)
            delivery.status = .retryPending
            state.replaceDeliveryState(delivery)
            try stateStore.save(state)
            return
        }

        delivery = state.deliveryState(for: coordinate)
        switch response.kind {
        case .applied, .unchangedDuplicate:
            delivery.acknowledgedRevision = pending.sourceRevision
            delivery.pending = nil
            delivery.status = response.kind == .applied ? .applied : .unchangedDuplicate
            delivery.lastAcknowledgedAt = clock()
        case .rejectedTruncated:
            delivery.status = .blockedTruncated
        case .rejectedInvalid:
            delivery.status = .blockedInvalid
        case .rejectedStale:
            delivery.status = .operatorActionStale
        case .rejectedRevisionConflict:
            delivery.status = .operatorActionConflict
        }
        state.replaceDeliveryState(delivery)
        try stateStore.save(state)
    }
}
