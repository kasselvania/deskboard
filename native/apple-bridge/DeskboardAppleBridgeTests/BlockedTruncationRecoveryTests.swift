import Foundation
import XCTest
@testable import DeskboardAppleBridge

private enum SyntheticRecoveryFailure: Error {
    case refused
}

private final class RecoveryStateStore: BridgeStatePersisting {
    var state: BridgePersistentState
    var savedStates: [BridgePersistentState] = []
    var saveShouldFail = false

    init(_ state: BridgePersistentState) {
        self.state = state
    }

    func loadOrCreate() throws -> BridgePersistentState { state }

    func save(_ state: BridgePersistentState) throws {
        if saveShouldFail { throw SyntheticRecoveryFailure.refused }
        try state.validate()
        self.state = state
        savedStates.append(state)
    }

    func reset() throws -> BridgePersistentState {
        throw SyntheticRecoveryFailure.refused
    }
}

private final class RecoverySourceReader: AppleSourceReading {
    var permission: BridgePermissionState = .granted
    var sourceAvailable = true
    var source: ReminderSourceRead
    var acceptedRequestSourceContainerId: String
    var readError: Error?
    var beforeReadReturn: (() -> Void)?
    private(set) var readCount = 0

    init(source: ReminderSourceRead) {
        self.source = source
        acceptedRequestSourceContainerId = source.sourceContainerId
    }

    func permissionState(for entity: BridgeSourceEntity) -> BridgePermissionState {
        entity == .reminder ? permission : .granted
    }

    func requestPermission(
        for entity: BridgeSourceEntity
    ) async -> BridgePermissionRequestResult {
        .completed(
            entity: entity,
            stateBefore: permissionState(for: entity),
            returnedGranted: permissionState(for: entity) == .granted,
            stateAfter: permissionState(for: entity)
        )
    }

    func availableSources(for entity: BridgeSourceEntity) -> [BridgeSourceDescriptor] {
        guard entity == .reminder, sourceAvailable else { return [] }
        return [
            BridgeSourceDescriptor(
                entityType: .reminder,
                sourceContainerId: acceptedRequestSourceContainerId,
                localDisplayName: "Synthetic masked source"
            ),
        ]
    }

    func readReminderSource(sourceContainerId: String) async throws -> ReminderSourceRead {
        readCount += 1
        if let readError { throw readError }
        guard sourceContainerId == acceptedRequestSourceContainerId else {
            throw SyntheticRecoveryFailure.refused
        }
        beforeReadReturn?()
        return source
    }

    func readCalendarSource(
        sourceContainerId: String,
        now: Date,
        windowTimeZone: TimeZone
    ) throws -> CalendarSourceRead {
        throw SyntheticRecoveryFailure.refused
    }
}

private final class RecoveryDeliveryClient: AppleSourceDelivering {
    var outcomes: [Result<AppleSourceApplyResponse, Error>]
    let stateStore: RecoveryStateStore
    private(set) var envelopes: [Data] = []
    private(set) var everyEnvelopeWasPersistedBeforeTransport = true

    init(
        stateStore: RecoveryStateStore,
        outcomes: [Result<AppleSourceApplyResponse, Error>]
    ) {
        self.stateStore = stateStore
        self.outcomes = outcomes
    }

    func deliver(
        envelopeData: Data,
        endpoint: CoreIngestionEndpoint
    ) async throws -> AppleSourceApplyResponse {
        envelopes.append(envelopeData)
        everyEnvelopeWasPersistedBeforeTransport =
            everyEnvelopeWasPersistedBeforeTransport
                && stateStore.state.deliveries.contains(where: {
                    $0.pending?.encodedEnvelope == envelopeData
                        && $0.status == .retryPending
                })
        guard !outcomes.isEmpty else { throw SyntheticRecoveryFailure.refused }
        return try outcomes.removeFirst().get()
    }
}

private final class RecoveryStatusDeliveryClient: AppleBridgeStatusDelivering {
    func deliverStatus(
        envelopeData: Data,
        endpoint: CoreIngestionEndpoint
    ) async throws -> AppleBridgeStatusApplyResponse {
        let snapshot = try AppleBridgeStatusEnvelopeCodec.decode(envelopeData)
        return AppleBridgeStatusApplyResponse(
            kind: .applied,
            statusRevision: snapshot.statusRevision
        )
    }
}

@MainActor
final class BlockedTruncationRecoveryTests: XCTestCase {
    private let targetId = "synthetic-blocked-source"
    private let bridgeId = "synthetic-bridge"

    func testEligibleDeliveryReplacesOnlyPendingBytesAtSameRevision() async throws {
        let original = try blockedState(includeUnrelatedState: true)
        let store = RecoveryStateStore(original)
        let reader = RecoverySourceReader(source: completeSource(recordCount: 3))
        let recovery = makeRecovery(store: store, reader: reader)

        XCTAssertEqual(recovery.eligibleReminderSourceIds(), [targetId])
        let outcome = await recovery.rebuildBlockedReminder(
            sourceContainerId: targetId
        )

        guard case let .replacementPersisted(persisted) = outcome else {
            return XCTFail("Expected replacementPersisted")
        }
        XCTAssertEqual(persisted.sourceRevision, 7)
        XCTAssertEqual(persisted.coordinate.entityType, .reminder)
        let replacement = store.state
        let beforeTarget = try XCTUnwrap(
            original.deliveries.first(where: { $0.coordinate == persisted.coordinate })
        )
        let afterTarget = try XCTUnwrap(
            replacement.deliveries.first(where: { $0.coordinate == persisted.coordinate })
        )
        XCTAssertEqual(afterTarget.acknowledgedRevision, 6)
        XCTAssertEqual(afterTarget.pending?.sourceRevision, 7)
        XCTAssertNotEqual(
            afterTarget.pending?.encodedEnvelope,
            beforeTarget.pending?.encodedEnvelope
        )
        XCTAssertEqual(afterTarget.status, .retryPending)
        XCTAssertEqual(afterTarget.lastAttemptedAt, beforeTarget.lastAttemptedAt)
        XCTAssertEqual(afterTarget.lastAcknowledgedAt, beforeTarget.lastAcknowledgedAt)
        let decoded = try AppleSourceEnvelopeCodec.decode(
            XCTUnwrap(afterTarget.pending?.encodedEnvelope)
        )
        XCTAssertEqual(decoded.sourceRevision, 7)
        XCTAssertFalse(decoded.snapshot.truncated)
        XCTAssertEqual(decoded.snapshot.matchedCount, 3)

        XCTAssertEqual(replacement.bridgeId, original.bridgeId)
        XCTAssertEqual(
            replacement.selectedCalendarSourceIds,
            original.selectedCalendarSourceIds
        )
        XCTAssertEqual(
            replacement.selectedReminderSourceIds,
            original.selectedReminderSourceIds
        )
        XCTAssertEqual(replacement.coreOrigin, original.coreOrigin)
        XCTAssertEqual(
            replacement.acknowledgedStatusRevision,
            original.acknowledgedStatusRevision
        )
        XCTAssertEqual(replacement.pendingStatus, original.pendingStatus)
        XCTAssertEqual(
            replacement.statusDeliveryResult,
            original.statusDeliveryResult
        )
        XCTAssertEqual(
            replacement.deliveries.filter { $0.coordinate != persisted.coordinate },
            original.deliveries.filter { $0.coordinate != persisted.coordinate }
        )
        XCTAssertEqual(store.savedStates.count, 1)
        XCTAssertTrue(
            store.savedStates.allSatisfy {
                $0.deliveries.first(where: { $0.coordinate == persisted.coordinate })?
                    .pending != nil
            }
        )
    }

    func testEveryIneligibleStatePreservesExactStateAndDoesNotRead() async throws {
        let base = try blockedState()
        let completePending = try envelope(
            sourceRevision: 7,
            source: completeSource(recordCount: 2),
            maximumRecords:
                BridgeProductionLimits.maximumRetainedReminderRecordsPerSource
        )
        var unselected = base
        unselected.selectedReminderSourceIds = []
        var wrongStatus = base
        wrongStatus.deliveries[0].status = .retryPending
        var noPending = base
        noPending.deliveries[0].pending = nil
        var wrongRevision = base
        wrongRevision.deliveries[0].pending = BridgePendingEnvelope(
            sourceRevision: 8,
            encodedEnvelope: try envelope(
                sourceRevision: 8,
                source: completeSource(recordCount: 2),
                maximumRecords: 1
            )
        )
        var nonTruncated = base
        nonTruncated.deliveries[0].pending = BridgePendingEnvelope(
            sourceRevision: 7,
            encodedEnvelope: completePending
        )

        let cases: [(BridgePersistentState, BridgePermissionState, Bool)] = [
            (unselected, .granted, true),
            (wrongStatus, .granted, true),
            (noPending, .granted, true),
            (wrongRevision, .granted, true),
            (nonTruncated, .granted, true),
            (base, .denied, true),
            (base, .granted, false),
        ]

        for (state, permission, available) in cases {
            let store = RecoveryStateStore(state)
            let reader = RecoverySourceReader(source: completeSource(recordCount: 2))
            reader.permission = permission
            reader.sourceAvailable = available
            let outcome = await makeRecovery(
                store: store,
                reader: reader
            ).rebuildBlockedReminder(sourceContainerId: targetId)

            XCTAssertEqual(outcome, .operatorActionRequired)
            XCTAssertEqual(store.state, state)
            XCTAssertTrue(store.savedStates.isEmpty)
            XCTAssertEqual(reader.readCount, 0)
        }
    }

    func testStillTruncatedInvalidOversizeAndSaveFailurePreserveOldState() async throws {
        let original = try blockedState()
        let sources = [
            completeSource(recordCount: 1_001),
            collidingSource(),
            oversizedCompleteSource(),
        ]
        let expected: [BlockedTruncationRecoveryOutcome] = [
            .stillTruncated,
            .operatorActionRequired,
            .operatorActionRequired,
        ]

        for (source, expectedOutcome) in zip(sources, expected) {
            let store = RecoveryStateStore(original)
            let reader = RecoverySourceReader(source: source)
            let outcome = await makeRecovery(
                store: store,
                reader: reader
            ).rebuildBlockedReminder(sourceContainerId: targetId)

            XCTAssertEqual(outcome, expectedOutcome)
            XCTAssertEqual(store.state, original)
            XCTAssertTrue(store.savedStates.isEmpty)
            XCTAssertEqual(reader.readCount, 1)
        }

        let failingStore = RecoveryStateStore(original)
        failingStore.saveShouldFail = true
        let failure = await makeRecovery(
            store: failingStore,
            reader: RecoverySourceReader(source: completeSource(recordCount: 2))
        ).rebuildBlockedReminder(sourceContainerId: targetId)
        XCTAssertEqual(failure, .operatorActionRequired)
        XCTAssertEqual(failingStore.state, original)
        XCTAssertTrue(failingStore.savedStates.isEmpty)
    }

    func testReadFailureMismatchedCandidateAndConcurrentStateChangeDoNotOverwriteState() async throws {
        let original = try blockedState(includeUnrelatedState: true)

        let readFailureStore = RecoveryStateStore(original)
        let readFailureReader = RecoverySourceReader(
            source: completeSource(recordCount: 2)
        )
        readFailureReader.readError = SyntheticRecoveryFailure.refused
        let readFailure = await makeRecovery(
            store: readFailureStore,
            reader: readFailureReader
        ).rebuildBlockedReminder(sourceContainerId: targetId)
        XCTAssertEqual(readFailure, .operatorActionRequired)
        XCTAssertEqual(readFailureStore.state, original)
        XCTAssertTrue(readFailureStore.savedStates.isEmpty)

        let mismatchedStore = RecoveryStateStore(original)
        let mismatchedReader = RecoverySourceReader(
            source: ReminderSourceRead(
                sourceContainerId: "synthetic-other-container",
                allowsContentModifications: true,
                records: []
            )
        )
        mismatchedReader.acceptedRequestSourceContainerId = targetId
        let mismatched = await makeRecovery(
            store: mismatchedStore,
            reader: mismatchedReader
        ).rebuildBlockedReminder(sourceContainerId: targetId)
        XCTAssertEqual(mismatched, .operatorActionRequired)
        XCTAssertEqual(mismatchedStore.state, original)
        XCTAssertTrue(mismatchedStore.savedStates.isEmpty)

        let concurrentStore = RecoveryStateStore(original)
        let concurrentReader = RecoverySourceReader(
            source: completeSource(recordCount: 2)
        )
        var concurrentlyChanged = original
        concurrentlyChanged.statusDeliveryResult = .blockedInvalid
        concurrentReader.beforeReadReturn = {
            concurrentStore.state = concurrentlyChanged
        }
        let concurrent = await makeRecovery(
            store: concurrentStore,
            reader: concurrentReader
        ).rebuildBlockedReminder(sourceContainerId: targetId)
        XCTAssertEqual(concurrent, .operatorActionRequired)
        XCTAssertEqual(concurrentStore.state, concurrentlyChanged)
        XCTAssertTrue(concurrentStore.savedStates.isEmpty)
    }

    func testReplacementPersistsBeforeTransportAndUncertaintyRetriesExactNewBytes() async throws {
        let store = RecoveryStateStore(try blockedState())
        let reader = RecoverySourceReader(source: completeSource(recordCount: 3))
        let recovery = makeRecovery(store: store, reader: reader)
        guard case .replacementPersisted = await recovery.rebuildBlockedReminder(
            sourceContainerId: targetId
        ) else {
            return XCTFail("Expected replacementPersisted")
        }
        let replacementBytes = try XCTUnwrap(
            store.state.deliveries.first?.pending?.encodedEnvelope
        )
        let delivery = RecoveryDeliveryClient(
            stateStore: store,
            outcomes: [.failure(SyntheticRecoveryFailure.refused)]
        )

        _ = try await makeManualCoordinator(
            store: store,
            reader: reader,
            delivery: delivery
        ).syncNow()

        XCTAssertTrue(delivery.everyEnvelopeWasPersistedBeforeTransport)
        XCTAssertEqual(delivery.envelopes, [replacementBytes])
        XCTAssertEqual(
            store.state.deliveries.first?.pending?.encodedEnvelope,
            replacementBytes
        )
        XCTAssertEqual(store.state.deliveries.first?.status, .retryPending)
        XCTAssertEqual(reader.readCount, 1)

        reader.source = completeSource(recordCount: 4)
        delivery.outcomes.append(
            .success(
                AppleSourceApplyResponse(
                    kind: .unchangedDuplicate,
                    entityType: .reminder,
                    sourceRevision: 7
                )
            )
        )
        _ = try await makeManualCoordinator(
            store: store,
            reader: reader,
            delivery: delivery
        ).syncNow()

        XCTAssertTrue(delivery.everyEnvelopeWasPersistedBeforeTransport)
        XCTAssertEqual(delivery.envelopes, [replacementBytes, replacementBytes])
        XCTAssertEqual(reader.readCount, 1)
        XCTAssertEqual(store.state.deliveries.first?.acknowledgedRevision, 7)
        XCTAssertNil(store.state.deliveries.first?.pending)
        XCTAssertEqual(
            store.state.deliveries.first?.status,
            .unchangedDuplicate
        )
    }

    func testAppliedAndDuplicateBothAcknowledgeAndClearReplacement() async throws {
        for kind in [
            AppleSourceApplyResultKind.applied,
            .unchangedDuplicate,
        ] {
            let store = RecoveryStateStore(try blockedState())
            let reader = RecoverySourceReader(source: completeSource(recordCount: 2))
            guard case .replacementPersisted = await makeRecovery(
                store: store,
                reader: reader
            ).rebuildBlockedReminder(sourceContainerId: targetId) else {
                return XCTFail("Expected replacementPersisted")
            }
            let delivery = RecoveryDeliveryClient(
                stateStore: store,
                outcomes: [
                    .success(
                        AppleSourceApplyResponse(
                            kind: kind,
                            entityType: .reminder,
                            sourceRevision: 7
                        )
                    ),
                ]
            )

            _ = try await makeManualCoordinator(
                store: store,
                reader: reader,
                delivery: delivery
            ).syncNow()

            XCTAssertEqual(store.state.deliveries.first?.acknowledgedRevision, 7)
            XCTAssertNil(store.state.deliveries.first?.pending)
            XCTAssertEqual(store.state.deliveries.first?.status.rawValue, kind.rawValue)
        }
    }

    func testRecoveryResultsAreFixedAndContentFree() {
        XCTAssertEqual(
            Set([
                BlockedTruncationRecoveryResult.replacementPersisted.rawValue,
                BlockedTruncationRecoveryResult.stillTruncated.rawValue,
                BlockedTruncationRecoveryResult.operatorActionRequired.rawValue,
            ]),
            Set([
                "replacementPersisted",
                "stillTruncated",
                "operatorActionRequired",
            ])
        )
    }

    private func makeRecovery(
        store: BridgeStatePersisting,
        reader: AppleSourceReading
    ) -> BlockedTruncationRecoveryCoordinator {
        BlockedTruncationRecoveryCoordinator(
            stateStore: store,
            sourceReader: reader,
            clock: { self.date("2026-08-26T12:00:00Z") }
        )
    }

    private func makeManualCoordinator(
        store: BridgeStatePersisting,
        reader: AppleSourceReading,
        delivery: AppleSourceDelivering
    ) -> ManualSyncCoordinator {
        ManualSyncCoordinator(
            stateStore: store,
            sourceReader: reader,
            deliveryClient: delivery,
            statusDeliveryClient: RecoveryStatusDeliveryClient(),
            clock: { self.date("2026-08-26T12:01:00Z") },
            windowTimeZone: { TimeZone(identifier: "Etc/UTC")! }
        )
    }

    private func blockedState(
        includeUnrelatedState: Bool = false
    ) throws -> BridgePersistentState {
        let target = BridgeSourceCoordinate(
            entityType: .reminder,
            sourceContainerId: targetId
        )
        let oldBytes = try envelope(
            sourceRevision: 7,
            source: completeSource(recordCount: 2),
            maximumRecords: 1
        )
        var deliveries = [
            BridgeSourceDeliveryState(
                coordinate: target,
                acknowledgedRevision: 6,
                pending: BridgePendingEnvelope(
                    sourceRevision: 7,
                    encodedEnvelope: oldBytes
                ),
                status: .blockedTruncated,
                lastAttemptedAt: date("2026-08-25T12:00:00Z"),
                lastAcknowledgedAt: date("2026-08-24T12:00:00Z")
            ),
        ]
        var selectedCalendars: [String] = []
        var acknowledgedStatusRevision = 0
        var pendingStatus: BridgePendingStatusEnvelope?
        var statusDeliveryResult = BridgeStatusDeliveryResult.idle
        if includeUnrelatedState {
            let other = BridgeSourceDeliveryState(
                coordinate: BridgeSourceCoordinate(
                    entityType: .calendar,
                    sourceContainerId: "synthetic-other-source"
                ),
                acknowledgedRevision: 4,
                pending: nil,
                status: .applied,
                lastAttemptedAt: date("2026-08-25T11:00:00Z"),
                lastAcknowledgedAt: date("2026-08-25T11:01:00Z")
            )
            deliveries.append(other)
            deliveries.sort { BridgeSourceCoordinate.ordered($0.coordinate, $1.coordinate) }
            selectedCalendars = ["synthetic-other-source"]
            acknowledgedStatusRevision = 3
            pendingStatus = BridgePendingStatusEnvelope(
                statusRevision: 4,
                encodedEnvelope: try AppleBridgeStatusEnvelopeCodec.encode(
                    AppleBridgeStatusSnapshotV1(
                        schemaVersion: 1,
                        bridgeId: bridgeId,
                        statusRevision: 4,
                        capturedAt: "2026-08-25T12:00:00.000Z",
                        permissions: AppleBridgeStatusPermissionsV1(
                            calendar: .granted,
                            reminders: .granted
                        ),
                        selectedSources: []
                    )
                )
            )
            statusDeliveryResult = .retryPending
        }
        let state = BridgePersistentState(
            version: BridgePersistentState.schemaVersion,
            bridgeId: bridgeId,
            selectedCalendarSourceIds: selectedCalendars,
            selectedReminderSourceIds: [targetId],
            coreOrigin: "http://127.0.0.1:3001",
            deliveries: deliveries,
            acknowledgedStatusRevision: acknowledgedStatusRevision,
            pendingStatus: pendingStatus,
            statusDeliveryResult: statusDeliveryResult
        )
        try state.validate()
        return state
    }

    private func envelope(
        sourceRevision: Int,
        source: ReminderSourceRead,
        maximumRecords: Int
    ) throws -> Data {
        let snapshot = try AppleSourceConverter.reminderSnapshot(
            from: source,
            bridgeId: bridgeId,
            capturedAt: date("2026-08-25T12:00:00Z"),
            maximumRecords: maximumRecords
        )
        return try AppleSourceEnvelopeCodec.encode(
            AppleSourceOperationalEnvelopeV1(
                sourceRevision: sourceRevision,
                snapshot: snapshot
            )
        )
    }

    private func completeSource(recordCount: Int) -> ReminderSourceRead {
        ReminderSourceRead(
            sourceContainerId: targetId,
            allowsContentModifications: true,
            records: (0 ..< recordCount).map { index in
                reminderRecord(id: String(format: "synthetic-%05d", index))
            }
        )
    }

    private func collidingSource() -> ReminderSourceRead {
        let record = reminderRecord(id: "synthetic-collision")
        return ReminderSourceRead(
            sourceContainerId: targetId,
            allowsContentModifications: true,
            records: [record, record]
        )
    }

    private func oversizedCompleteSource() -> ReminderSourceRead {
        ReminderSourceRead(
            sourceContainerId: targetId,
            allowsContentModifications: true,
            records: [
                ReminderRecordRead(
                    localIdentifier: "synthetic-oversize",
                    externalIdentifier: nil,
                    title: String(repeating: "x", count: 800 * 1024),
                    startComponents: nil,
                    dueComponents: nil,
                    isCompleted: false,
                    completionDate: nil
                ),
            ]
        )
    }

    private func reminderRecord(id: String) -> ReminderRecordRead {
        ReminderRecordRead(
            localIdentifier: id,
            externalIdentifier: nil,
            title: "Synthetic recovery record",
            startComponents: nil,
            dueComponents: nil,
            isCompleted: false,
            completionDate: nil
        )
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
