import Foundation
import XCTest
@testable import DeskboardAppleBridge

private final class MemoryStateStore: BridgeStatePersisting {
    var state: BridgePersistentState
    var savedStates: [BridgePersistentState] = []

    init(_ state: BridgePersistentState) { self.state = state }

    func loadOrCreate() throws -> BridgePersistentState { state }

    func save(_ state: BridgePersistentState) throws {
        try state.validate()
        self.state = state
        savedStates.append(state)
    }

    func reset() throws -> BridgePersistentState {
        state = .fresh()
        savedStates.append(state)
        return state
    }
}

private final class SyntheticSourceReader: AppleSourceReading {
    var reminderPermission: BridgePermissionState = .granted
    var calendarPermission: BridgePermissionState = .granted
    var permissionRequestResults: [
        BridgeSourceEntity: BridgePermissionRequestResult
    ] = [:]
    var reminderRead: ReminderSourceRead
    var calendarRead: CalendarSourceRead
    var reminderReadCount = 0
    var calendarReadCount = 0

    init() {
        reminderRead = ReminderSourceRead(
            sourceContainerId: "synthetic-reminder-source",
            allowsContentModifications: true,
            records: [Self.reminderRecord(title: "Synthetic initial")]
        )
        let zone = TimeZone(identifier: "Etc/UTC")!
        calendarRead = CalendarSourceRead(
            sourceContainerId: "synthetic-calendar-source",
            allowsContentModifications: true,
            isSubscribed: false,
            windowStart: Self.date("2026-08-16T18:00:00Z"),
            windowEnd: Self.date("2026-10-07T18:00:00Z"),
            windowTimeZone: zone,
            records: []
        )
    }

    func permissionState(for entity: BridgeSourceEntity) -> BridgePermissionState {
        entity == .reminder ? reminderPermission : calendarPermission
    }

    func requestPermission(
        for entity: BridgeSourceEntity
    ) async -> BridgePermissionRequestResult {
        let current = permissionState(for: entity)
        let result = permissionRequestResults[entity] ?? .completed(
            entity: entity,
            stateBefore: current,
            returnedGranted: current == .granted,
            stateAfter: current
        )
        switch entity {
        case .calendar:
            calendarPermission = result.stateAfter
        case .reminder:
            reminderPermission = result.stateAfter
        }
        return result
    }

    func availableSources(for entity: BridgeSourceEntity) -> [BridgeSourceDescriptor] {
        guard permissionState(for: entity) == .granted else { return [] }
        let id = entity == .reminder
            ? reminderRead.sourceContainerId
            : calendarRead.sourceContainerId
        return [
            BridgeSourceDescriptor(
                entityType: entity,
                sourceContainerId: id,
                localDisplayName: "Synthetic source"
            ),
        ]
    }

    func readReminderSource(sourceContainerId: String) async throws -> ReminderSourceRead {
        reminderReadCount += 1
        guard sourceContainerId == reminderRead.sourceContainerId else {
            throw EventKitBridgeReaderError.sourceUnavailable
        }
        return reminderRead
    }

    func readCalendarSource(
        sourceContainerId: String,
        now: Date,
        windowTimeZone: TimeZone
    ) throws -> CalendarSourceRead {
        calendarReadCount += 1
        guard sourceContainerId == calendarRead.sourceContainerId else {
            throw EventKitBridgeReaderError.sourceUnavailable
        }
        return calendarRead
    }

    static func reminderRecord(title: String) -> ReminderRecordRead {
        ReminderRecordRead(
            localIdentifier: "synthetic-reminder",
            externalIdentifier: nil,
            title: title,
            startComponents: nil,
            dueComponents: nil,
            isCompleted: false,
            completionDate: nil
        )
    }

    static func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}

private final class QueueDeliveryClient: AppleSourceDelivering {
    enum Failure: Error { case uncertain }

    var outcomes: [Result<AppleSourceApplyResponse, Error>]
    var envelopes: [Data] = []

    init(_ outcomes: [Result<AppleSourceApplyResponse, Error>]) {
        self.outcomes = outcomes
    }

    func deliver(
        envelopeData: Data,
        endpoint: CoreIngestionEndpoint
    ) async throws -> AppleSourceApplyResponse {
        envelopes.append(envelopeData)
        guard !outcomes.isEmpty else { throw Failure.uncertain }
        return try outcomes.removeFirst().get()
    }
}

private final class QueueStatusDeliveryClient: AppleBridgeStatusDelivering {
    enum Failure: Error { case uncertain }

    var outcomes: [Result<AppleBridgeStatusApplyResponse, Error>]
    var envelopes: [Data] = []

    init(_ outcomes: [Result<AppleBridgeStatusApplyResponse, Error>]) {
        self.outcomes = outcomes
    }

    func deliverStatus(
        envelopeData: Data,
        endpoint: CoreIngestionEndpoint
    ) async throws -> AppleBridgeStatusApplyResponse {
        envelopes.append(envelopeData)
        guard !outcomes.isEmpty else { throw Failure.uncertain }
        return try outcomes.removeFirst().get()
    }
}

private final class AcknowledgingStatusDeliveryClient: AppleBridgeStatusDelivering {
    var envelopes: [Data] = []

    func deliverStatus(
        envelopeData: Data,
        endpoint: CoreIngestionEndpoint
    ) async throws -> AppleBridgeStatusApplyResponse {
        envelopes.append(envelopeData)
        let snapshot = try AppleBridgeStatusEnvelopeCodec.decode(envelopeData)
        return AppleBridgeStatusApplyResponse(
            kind: .applied,
            statusRevision: snapshot.statusRevision
        )
    }
}

private final class SyntheticCredentialStore: BridgeCredentialStore {
    func readToken() throws -> String? { nil }
    func storeToken(_ token: String) throws {}
}

private final class UnusedHTTPTransport: AppleSourceHTTPTransport {
    enum Failure: Error { case unexpectedUse }

    func upload(_ request: AppleSourceUploadRequest) async throws -> AppleSourceUploadResponse {
        throw Failure.unexpectedUse
    }
}

@MainActor
final class BridgeStateAndDeliveryTests: XCTestCase {
    private let now = SyntheticSourceReader.date("2026-08-23T18:00:00Z")

    func testCalendarPermissionGrantCapturesBeforeBooleanAndAfterState() {
        let result = BridgePermissionRequestResult.completed(
            entity: .calendar,
            stateBefore: .notDetermined,
            returnedGranted: true,
            stateAfter: .granted
        )

        XCTAssertEqual(result.entity, .calendar)
        XCTAssertEqual(result.stateBefore, .notDetermined)
        XCTAssertEqual(result.returnedGranted, true)
        XCTAssertEqual(result.stateAfter, .granted)
        XCTAssertEqual(result.outcome, .granted)
    }

    func testRemindersPermissionGrantIsClassifiedIndependently() {
        let result = BridgePermissionRequestResult.completed(
            entity: .reminder,
            stateBefore: .notDetermined,
            returnedGranted: true,
            stateAfter: .granted
        )

        XCTAssertEqual(result.entity, .reminder)
        XCTAssertEqual(result.outcome, .granted)
    }

    func testPermissionCompletionClassifiesDeniedRestrictedAndUnavailable() {
        let cases: [
            (BridgePermissionState, BridgePermissionRequestOutcome)
        ] = [
            (.denied, .denied),
            (.restricted, .restricted),
            (.unavailable, .unavailable),
        ]

        for (stateAfter, expectedOutcome) in cases {
            let result = BridgePermissionRequestResult.completed(
                entity: .calendar,
                stateBefore: .notDetermined,
                returnedGranted: false,
                stateAfter: stateAfter
            )
            XCTAssertEqual(result.returnedGranted, false)
            XCTAssertEqual(result.outcome, expectedOutcome)
        }
    }

    func testThrownPermissionRequestRemainsDistinctFromAuthorizationState() {
        let result = BridgePermissionRequestResult.systemRequestError(
            entity: .calendar,
            stateBefore: .notDetermined,
            stateAfter: .notDetermined
        )

        XCTAssertNil(result.returnedGranted)
        XCTAssertEqual(result.stateAfter, .notDetermined)
        XCTAssertEqual(result.outcome, .systemRequestError)
    }

    func testCompletedPermissionRequestWithoutDecisionIsExplicit() {
        let result = BridgePermissionRequestResult.completed(
            entity: .calendar,
            stateBefore: .notDetermined,
            returnedGranted: false,
            stateAfter: .notDetermined
        )

        XCTAssertEqual(result.returnedGranted, false)
        XCTAssertEqual(result.outcome, .noSystemDecision)
    }

    func testCalendarNoDecisionLeavesRemindersUnchangedAndShowsSafeNotice() async {
        let reader = SyntheticSourceReader()
        reader.calendarPermission = .notDetermined
        reader.reminderPermission = .granted
        reader.permissionRequestResults[.calendar] = .completed(
            entity: .calendar,
            stateBefore: .notDetermined,
            returnedGranted: false,
            stateAfter: .notDetermined
        )
        let model = makeViewModel(reader: reader)

        await model.requestPermission(for: .calendar)

        XCTAssertEqual(model.calendarPermission, .notDetermined)
        XCTAssertEqual(model.reminderPermission, .granted)
        XCTAssertEqual(
            model.calendarPermissionRequestResult?.outcome,
            .noSystemDecision
        )
        XCTAssertNil(model.reminderPermissionRequestResult)
        XCTAssertEqual(
            model.notice,
            "Calendar access request did not produce a system decision. Verify signing and installation, then retry."
        )
    }

    func testRemindersSystemErrorLeavesCalendarUnchangedAndShowsSafeNotice() async {
        let reader = SyntheticSourceReader()
        reader.calendarPermission = .granted
        reader.reminderPermission = .notDetermined
        reader.permissionRequestResults[.reminder] = .systemRequestError(
            entity: .reminder,
            stateBefore: .notDetermined,
            stateAfter: .notDetermined
        )
        let model = makeViewModel(reader: reader)

        await model.requestPermission(for: .reminder)

        XCTAssertEqual(model.calendarPermission, .granted)
        XCTAssertEqual(model.reminderPermission, .notDetermined)
        XCTAssertNil(model.calendarPermissionRequestResult)
        XCTAssertEqual(
            model.reminderPermissionRequestResult?.outcome,
            .systemRequestError
        )
        XCTAssertEqual(
            model.notice,
            "Reminders access request could not be completed. Verify signing and installation, then retry."
        )
    }

    func testFirstDeliveryUsesRevisionOneAndAcknowledgesExactlyOnce() async throws {
        let store = MemoryStateStore(configuredState())
        let reader = SyntheticSourceReader()
        let delivery = QueueDeliveryClient([
            .success(response(.applied, revision: 1)),
        ])
        let coordinator = makeCoordinator(store: store, reader: reader, delivery: delivery)

        let state = try await coordinator.syncNow()

        XCTAssertEqual(reader.reminderReadCount, 1)
        XCTAssertEqual(delivery.envelopes.count, 1)
        let sent = try AppleSourceEnvelopeCodec.decode(XCTUnwrap(delivery.envelopes.first))
        XCTAssertEqual(sent.sourceRevision, 1)
        let sourceState = try XCTUnwrap(state.deliveries.first)
        XCTAssertEqual(sourceState.acknowledgedRevision, 1)
        XCTAssertNil(sourceState.pending)
        XCTAssertEqual(sourceState.status, .applied)
    }

    func testTimeoutAndProcessRestartRetryExactBytesBeforeReadingChangedAppleData() async throws {
        let store = MemoryStateStore(configuredState())
        let reader = SyntheticSourceReader()
        let firstDelivery = QueueDeliveryClient([.failure(QueueDeliveryClient.Failure.uncertain)])
        let first = makeCoordinator(store: store, reader: reader, delivery: firstDelivery)

        let timedOut = try await first.syncNow()
        let pending = try XCTUnwrap(timedOut.deliveries.first?.pending)
        XCTAssertEqual(pending.sourceRevision, 1)
        XCTAssertEqual(reader.reminderReadCount, 1)

        reader.reminderRead = ReminderSourceRead(
            sourceContainerId: "synthetic-reminder-source",
            allowsContentModifications: true,
            records: [SyntheticSourceReader.reminderRecord(title: "Synthetic changed")]
        )
        let retryDelivery = QueueDeliveryClient([
            .success(response(.unchangedDuplicate, revision: 1)),
        ])
        let relaunched = makeCoordinator(
            store: store,
            reader: reader,
            delivery: retryDelivery
        )
        let retried = try await relaunched.syncNow()

        XCTAssertEqual(reader.reminderReadCount, 1)
        XCTAssertEqual(retryDelivery.envelopes, [pending.encodedEnvelope])
        XCTAssertEqual(retried.deliveries.first?.acknowledgedRevision, 1)
        XCTAssertNil(retried.deliveries.first?.pending)
        XCTAssertEqual(retried.deliveries.first?.status, .unchangedDuplicate)

        let newerDelivery = QueueDeliveryClient([
            .success(response(.applied, revision: 2)),
        ])
        let newer = makeCoordinator(store: store, reader: reader, delivery: newerDelivery)
        let updated = try await newer.syncNow()
        XCTAssertEqual(reader.reminderReadCount, 2)
        let newerBytes = try XCTUnwrap(newerDelivery.envelopes.first)
        XCTAssertNotEqual(newerBytes, pending.encodedEnvelope)
        XCTAssertEqual(try AppleSourceEnvelopeCodec.decode(newerBytes).sourceRevision, 2)
        XCTAssertEqual(updated.deliveries.first?.acknowledgedRevision, 2)
    }

    func testScheduledOutagePreservesExactPendingBytesUntilNextOpportunity() async throws {
        let store = MemoryStateStore(configuredState())
        let reader = SyntheticSourceReader()
        let delivery = QueueDeliveryClient([
            .failure(QueueDeliveryClient.Failure.uncertain),
        ])
        let manualCoordinator = makeCoordinator(
            store: store,
            reader: reader,
            delivery: delivery
        )
        let scheduler = SyntheticBackgroundScheduler()
        let unattended = UnattendedBridgeController(
            loginItem: SyntheticLoginItemController(status: .enabled),
            backgroundScheduler: scheduler,
            wakeObserver: SyntheticWakeObserver(),
            stateStore: MemoryUnattendedStateStore(ownerOptIn: true),
            clock: { self.now },
            syncRunner: { try await manualCoordinator.syncNow() }
        )
        var firstCompletion: BridgeBackgroundActivityCompletion?

        scheduler.fire(shouldDefer: false) { firstCompletion = $0 }
        await waitUntil { firstCompletion == .finished }

        let pending = try XCTUnwrap(store.state.deliveries.first?.pending)
        XCTAssertEqual(delivery.envelopes, [pending.encodedEnvelope])
        XCTAssertEqual(reader.reminderReadCount, 1)
        XCTAssertEqual(unattended.lastContentFreeResult, .pendingOrBlocked)

        reader.reminderRead = ReminderSourceRead(
            sourceContainerId: "synthetic-reminder-source",
            allowsContentModifications: true,
            records: [SyntheticSourceReader.reminderRecord(title: "Synthetic changed")]
        )
        delivery.outcomes.append(
            .success(response(.unchangedDuplicate, revision: 1))
        )
        var secondCompletion: BridgeBackgroundActivityCompletion?

        scheduler.fire(shouldDefer: false) { secondCompletion = $0 }
        await waitUntil { secondCompletion == .finished }

        XCTAssertEqual(
            delivery.envelopes,
            [pending.encodedEnvelope, pending.encodedEnvelope]
        )
        XCTAssertEqual(reader.reminderReadCount, 1)
        XCTAssertNil(store.state.deliveries.first?.pending)
        XCTAssertEqual(store.state.deliveries.first?.acknowledgedRevision, 1)
        XCTAssertEqual(unattended.lastContentFreeResult, .completed)
    }

    func testStatusTimeoutAndRelaunchRetryExactBytesBeforeFurtherSourceRead() async throws {
        let store = MemoryStateStore(configuredState())
        let reader = SyntheticSourceReader()
        let firstStatus = QueueStatusDeliveryClient([
            .failure(QueueStatusDeliveryClient.Failure.uncertain),
        ])
        let first = makeCoordinator(
            store: store,
            reader: reader,
            delivery: QueueDeliveryClient([
                .success(response(.applied, revision: 1)),
            ]),
            statusDelivery: firstStatus
        )

        let timedOut = try await first.syncNow()
        let pendingStatus = try XCTUnwrap(timedOut.pendingStatus)
        XCTAssertEqual(pendingStatus.statusRevision, 1)
        XCTAssertEqual(timedOut.acknowledgedStatusRevision, 0)
        XCTAssertEqual(reader.reminderReadCount, 1)

        reader.reminderRead = ReminderSourceRead(
            sourceContainerId: "synthetic-reminder-source",
            allowsContentModifications: true,
            records: [SyntheticSourceReader.reminderRecord(title: "Synthetic changed")]
        )
        let retryStatus = QueueStatusDeliveryClient([
            .success(
                AppleBridgeStatusApplyResponse(
                    kind: .unchangedDuplicate,
                    statusRevision: 1
                )
            ),
            .success(
                AppleBridgeStatusApplyResponse(
                    kind: .applied,
                    statusRevision: 2
                )
            ),
        ])
        let relaunched = makeCoordinator(
            store: store,
            reader: reader,
            delivery: QueueDeliveryClient([
                .success(response(.applied, revision: 2)),
            ]),
            statusDelivery: retryStatus
        )

        let completed = try await relaunched.syncNow()

        XCTAssertEqual(retryStatus.envelopes.first, pendingStatus.encodedEnvelope)
        XCTAssertEqual(
            try AppleBridgeStatusEnvelopeCodec.decode(
                XCTUnwrap(retryStatus.envelopes.first)
            ).statusRevision,
            1
        )
        XCTAssertEqual(
            try AppleBridgeStatusEnvelopeCodec.decode(
                XCTUnwrap(retryStatus.envelopes.last)
            ).statusRevision,
            2
        )
        XCTAssertEqual(reader.reminderReadCount, 2)
        XCTAssertEqual(completed.acknowledgedStatusRevision, 2)
        XCTAssertNil(completed.pendingStatus)
    }

    func testUnresolvedStatusRetryLeavesSourcePendingBytesUntouched() async throws {
        var state = try stateWithPending()
        let originalSourcePending = try XCTUnwrap(state.deliveries.first?.pending)
        let statusBytes = try statusEnvelopeData(for: state, revision: 1)
        state.pendingStatus = BridgePendingStatusEnvelope(
            statusRevision: 1,
            encodedEnvelope: statusBytes
        )
        state.statusDeliveryResult = .retryPending
        let store = MemoryStateStore(state)
        let reader = SyntheticSourceReader()
        let sourceDelivery = QueueDeliveryClient([
            .success(response(.applied, revision: 1)),
        ])
        let statusDelivery = QueueStatusDeliveryClient([
            .failure(QueueStatusDeliveryClient.Failure.uncertain),
        ])

        let result = try await makeCoordinator(
            store: store,
            reader: reader,
            delivery: sourceDelivery,
            statusDelivery: statusDelivery
        ).syncNow()

        XCTAssertEqual(statusDelivery.envelopes, [statusBytes])
        XCTAssertTrue(sourceDelivery.envelopes.isEmpty)
        XCTAssertEqual(reader.reminderReadCount, 0)
        XCTAssertEqual(
            result.deliveries.first?.pending?.encodedEnvelope,
            originalSourcePending.encodedEnvelope
        )
        XCTAssertEqual(result.deliveries.first?.pending?.sourceRevision, 1)
        XCTAssertEqual(result.pendingStatus?.encodedEnvelope, statusBytes)
    }

    func testRejectedStatusResultsPreserveExactPendingStatusEnvelope() async throws {
        let cases: [(
            AppleBridgeStatusApplyResponse,
            BridgeStatusDeliveryResult
        )] = [
            (
                AppleBridgeStatusApplyResponse(
                    kind: .rejectedInvalid,
                    statusRevision: nil
                ),
                .blockedInvalid
            ),
            (
                AppleBridgeStatusApplyResponse(
                    kind: .rejectedStale,
                    statusRevision: 1
                ),
                .operatorActionStale
            ),
            (
                AppleBridgeStatusApplyResponse(
                    kind: .rejectedRevisionConflict,
                    statusRevision: 1
                ),
                .operatorActionConflict
            ),
        ]

        for (response, expectedResult) in cases {
            let state = try stateWithPendingStatusOnly()
            let original = try XCTUnwrap(state.pendingStatus)
            let store = MemoryStateStore(state)
            let result = try await makeCoordinator(
                store: store,
                reader: SyntheticSourceReader(),
                delivery: QueueDeliveryClient([]),
                statusDelivery: QueueStatusDeliveryClient([.success(response)])
            ).syncNow()

            XCTAssertEqual(result.pendingStatus, original)
            XCTAssertEqual(result.acknowledgedStatusRevision, 0)
            XCTAssertEqual(result.statusDeliveryResult, expectedResult)
        }
    }

    func testOnlySuccessfulStatusResultsAcknowledgeAndClearPending() async throws {
        for kind in [
            AppleBridgeStatusApplyResultKind.applied,
            .unchangedDuplicate,
        ] {
            let state = try stateWithPendingStatusOnly()
            let store = MemoryStateStore(state)
            _ = try await makeCoordinator(
                store: store,
                reader: SyntheticSourceReader(),
                delivery: QueueDeliveryClient([]),
                statusDelivery: QueueStatusDeliveryClient([
                    .success(
                        AppleBridgeStatusApplyResponse(
                            kind: kind,
                            statusRevision: 1
                        )
                    ),
                    .failure(QueueStatusDeliveryClient.Failure.uncertain),
                ])
            ).syncNow()

            XCTAssertTrue(
                store.savedStates.contains(where: {
                    $0.acknowledgedStatusRevision == 1
                        && $0.pendingStatus == nil
                        && $0.statusDeliveryResult.rawValue == kind.rawValue
                })
            )
            XCTAssertEqual(store.state.pendingStatus?.statusRevision, 2)
        }
    }

    func testDeselectionChangesNextStatusRosterWithoutDiscardingDeliveryState() async throws {
        let store = MemoryStateStore(configuredState())
        let reader = SyntheticSourceReader()
        let statusDelivery = AcknowledgingStatusDeliveryClient()

        _ = try await makeCoordinator(
            store: store,
            reader: reader,
            delivery: QueueDeliveryClient([
                .success(response(.applied, revision: 1)),
            ]),
            statusDelivery: statusDelivery
        ).syncNow()
        var deselected = store.state
        deselected.setSelections([], for: .reminder)
        try store.save(deselected)

        let completed = try await makeCoordinator(
            store: store,
            reader: reader,
            delivery: QueueDeliveryClient([]),
            statusDelivery: statusDelivery
        ).syncNow()

        let finalStatus = try AppleBridgeStatusEnvelopeCodec.decode(
            XCTUnwrap(statusDelivery.envelopes.last)
        )
        XCTAssertTrue(finalStatus.selectedSources.isEmpty)
        XCTAssertEqual(completed.deliveries.count, 1)
        XCTAssertEqual(completed.deliveries.first?.acknowledgedRevision, 1)
        XCTAssertEqual(reader.reminderReadCount, 1)
    }

    func testPhaseThreeBStateDecodesWithEmptyStatusOutboxDefaults() throws {
        let state = configuredState()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(state)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "acknowledgedStatusRevision")
        object.removeValue(forKey: "pendingStatus")
        object.removeValue(forKey: "statusDeliveryResult")
        let priorVersionBytes = try JSONSerialization.data(withJSONObject: object)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(
            BridgePersistentState.self,
            from: priorVersionBytes
        )

        XCTAssertEqual(decoded.acknowledgedStatusRevision, 0)
        XCTAssertNil(decoded.pendingStatus)
        XCTAssertEqual(decoded.statusDeliveryResult, .idle)
        XCTAssertNoThrow(try decoded.validate())
    }

    func testAllApplyResultTransitionsPreserveOrClearPendingExactly() async throws {
        let cases: [(
            AppleSourceApplyResponse,
            BridgeSourceStatus,
            Int,
            Bool
        )] = [
            (response(.applied, revision: 1), .applied, 1, false),
            (response(.unchangedDuplicate, revision: 1), .unchangedDuplicate, 1, false),
            (response(.rejectedTruncated, revision: 1), .blockedTruncated, 0, true),
            (
                AppleSourceApplyResponse(
                    kind: .rejectedInvalid,
                    entityType: nil,
                    sourceRevision: nil
                ),
                .blockedInvalid,
                0,
                true
            ),
            (response(.rejectedStale, revision: 1), .operatorActionStale, 0, true),
            (
                response(.rejectedRevisionConflict, revision: 1),
                .operatorActionConflict,
                0,
                true
            ),
        ]

        for (result, expectedStatus, expectedRevision, keepsPending) in cases {
            let store = MemoryStateStore(try stateWithPending())
            let delivery = QueueDeliveryClient([.success(result)])
            let coordinator = makeCoordinator(
                store: store,
                reader: SyntheticSourceReader(),
                delivery: delivery
            )
            let state = try await coordinator.syncNow()
            let source = try XCTUnwrap(state.deliveries.first)
            XCTAssertEqual(source.status, expectedStatus)
            XCTAssertEqual(source.acknowledgedRevision, expectedRevision)
            XCTAssertEqual(source.pending != nil, keepsPending)
        }
    }

    func testTransportFailureDoesNotAdvanceOrDiscardPending() async throws {
        let original = try stateWithPending()
        let store = MemoryStateStore(original)
        let coordinator = makeCoordinator(
            store: store,
            reader: SyntheticSourceReader(),
            delivery: QueueDeliveryClient([.failure(QueueDeliveryClient.Failure.uncertain)])
        )

        let state = try await coordinator.syncNow()

        XCTAssertEqual(state.deliveries.first?.acknowledgedRevision, 0)
        XCTAssertEqual(
            state.deliveries.first?.pending?.encodedEnvelope,
            original.deliveries.first?.pending?.encodedEnvelope
        )
        XCTAssertEqual(state.deliveries.first?.status, .retryPending)
    }

    func testPermissionLossKeepsSelectionsAndOtherEntityUsable() async throws {
        var state = configuredState()
        state.setSelections(["synthetic-calendar-source"], for: .calendar)
        let store = MemoryStateStore(state)
        let reader = SyntheticSourceReader()
        reader.reminderPermission = .denied
        let delivery = QueueDeliveryClient([
            .success(
                AppleSourceApplyResponse(
                    kind: .applied,
                    entityType: .calendar,
                    sourceRevision: 1
                )
            ),
        ])
        let coordinator = makeCoordinator(store: store, reader: reader, delivery: delivery)

        let result = try await coordinator.syncNow()

        XCTAssertEqual(result.selectedReminderSourceIds, ["synthetic-reminder-source"])
        XCTAssertEqual(result.selectedCalendarSourceIds, ["synthetic-calendar-source"])
        XCTAssertEqual(reader.reminderReadCount, 0)
        XCTAssertEqual(reader.calendarReadCount, 1)
        XCTAssertEqual(
            result.deliveries.first(where: { $0.coordinate.entityType == .calendar })?
                .acknowledgedRevision,
            1
        )
        XCTAssertEqual(
            result.deliveries.first(where: { $0.coordinate.entityType == .reminder })?.status,
            .permissionUnavailable
        )
    }

    func testAtomicFileStateSurvivesRelaunchAndResetCreatesNewBridgeIdentity() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("state.json")
        let firstStore = AtomicBridgeStateFileStore(stateURL: url)
        var state = try firstStore.loadOrCreate()
        let originalBridgeId = state.bridgeId
        state.coreOrigin = "http://127.0.0.1:3001"
        state.setSelections(["synthetic-reminder-source"], for: .reminder)
        try firstStore.save(state)

        let reopened = try AtomicBridgeStateFileStore(stateURL: url).loadOrCreate()
        XCTAssertEqual(reopened, state)
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[
            .posixPermissions
        ] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)

        let reset = try firstStore.reset()
        XCTAssertNotEqual(reset.bridgeId, originalBridgeId)
        XCTAssertTrue(reset.selectedReminderSourceIds.isEmpty)
        XCTAssertTrue(reset.deliveries.isEmpty)
    }

    func testChangingCoreOriginChangesOnlyTheStoredDestination() throws {
        var original = try stateWithPending()
        original.acknowledgedStatusRevision = 6
        original.pendingStatus = BridgePendingStatusEnvelope(
            statusRevision: 7,
            encodedEnvelope: try statusEnvelopeData(for: original, revision: 7)
        )
        original.statusDeliveryResult = .retryPending
        try original.validate()
        let store = MemoryStateStore(original)
        let model = BridgeViewModel(
            stateStore: store,
            sourceReader: SyntheticSourceReader(),
            credentialStore: SyntheticCredentialStore(),
            transport: UnusedHTTPTransport(),
            provisioningInbox: NoopBridgeProvisioningInbox(),
            loginItemController: SyntheticLoginItemController(status: .notRegistered),
            backgroundScheduler: SyntheticBackgroundScheduler(),
            wakeObserver: SyntheticWakeObserver(),
            unattendedStateStore: MemoryUnattendedStateStore()
        )

        model.coreOriginInput = "https://synthetic-device.synthetic-tailnet.ts.net"
        model.saveCoreOrigin()

        var expected = original
        expected.coreOrigin = "https://synthetic-device.synthetic-tailnet.ts.net"
        XCTAssertEqual(try store.loadOrCreate(), expected)
        XCTAssertEqual(model.notice, "Core origin stored.")
    }

    func testPendingPayloadNeverAppearsInStateFailureDescription() throws {
        let privateShapedMarker = "SYNTHETIC_PRIVATE_MARKER"
        var state = try stateWithPending(title: privateShapedMarker)
        state = BridgePersistentState(
            version: state.version,
            bridgeId: "mismatched-bridge",
            selectedCalendarSourceIds: state.selectedCalendarSourceIds,
            selectedReminderSourceIds: state.selectedReminderSourceIds,
            coreOrigin: state.coreOrigin,
            deliveries: state.deliveries
        )
        do {
            try state.validate()
            XCTFail("Expected invalid persisted envelope binding")
        } catch {
            XCTAssertFalse(error.localizedDescription.contains(privateShapedMarker))
            XCTAssertEqual(error.localizedDescription, BridgeStateError.invalid.localizedDescription)
        }
    }

    private func configuredState() -> BridgePersistentState {
        var state = BridgePersistentState.fresh(bridgeId: "synthetic-bridge")
        state.coreOrigin = "http://127.0.0.1:3001"
        state.setSelections(["synthetic-reminder-source"], for: .reminder)
        return state
    }

    private func stateWithPending(
        title: String = "Synthetic initial"
    ) throws -> BridgePersistentState {
        var state = configuredState()
        let reader = SyntheticSourceReader()
        reader.reminderRead = ReminderSourceRead(
            sourceContainerId: "synthetic-reminder-source",
            allowsContentModifications: true,
            records: [SyntheticSourceReader.reminderRecord(title: title)]
        )
        let snapshot = try AppleSourceConverter.reminderSnapshot(
            from: reader.reminderRead,
            bridgeId: state.bridgeId,
            capturedAt: now
        )
        let bytes = try AppleSourceEnvelopeCodec.encodeWithinProductionLimit(
            sourceRevision: 1,
            snapshot: snapshot
        )
        let coordinate = BridgeSourceCoordinate(
            entityType: .reminder,
            sourceContainerId: "synthetic-reminder-source"
        )
        var delivery = state.deliveryState(for: coordinate)
        delivery.pending = BridgePendingEnvelope(
            sourceRevision: 1,
            encodedEnvelope: bytes
        )
        delivery.status = .retryPending
        state.replaceDeliveryState(delivery)
        try state.validate()
        return state
    }

    private func statusEnvelopeData(
        for state: BridgePersistentState,
        revision: Int
    ) throws -> Data {
        let delivery = try XCTUnwrap(state.deliveries.first)
        let instant = "2026-08-23T18:00:00.000Z"
        return try AppleBridgeStatusEnvelopeCodec.encode(
            AppleBridgeStatusSnapshotV1(
                schemaVersion: 1,
                bridgeId: state.bridgeId,
                statusRevision: revision,
                capturedAt: instant,
                permissions: AppleBridgeStatusPermissionsV1(
                    calendar: .granted,
                    reminders: .granted
                ),
                selectedSources: [
                    AppleBridgeSelectedSourceStatusV1(
                        entityType: delivery.coordinate.entityType,
                        sourceContainerId: delivery.coordinate.sourceContainerId,
                        status: .retryPending,
                        acknowledgedSourceRevision: delivery.acknowledgedRevision,
                        pendingSourceRevision: delivery.pending?.sourceRevision,
                        lastAttemptedAt: instant,
                        lastAcknowledgedAt: nil
                    ),
                ]
            )
        )
    }

    private func stateWithPendingStatusOnly() throws -> BridgePersistentState {
        var state = BridgePersistentState.fresh(bridgeId: "synthetic-bridge")
        state.coreOrigin = "http://127.0.0.1:3001"
        let bytes = try AppleBridgeStatusEnvelopeCodec.encode(
            AppleBridgeStatusSnapshotV1(
                schemaVersion: 1,
                bridgeId: state.bridgeId,
                statusRevision: 1,
                capturedAt: "2026-08-23T18:00:00.000Z",
                permissions: AppleBridgeStatusPermissionsV1(
                    calendar: .granted,
                    reminders: .granted
                ),
                selectedSources: []
            )
        )
        state.pendingStatus = BridgePendingStatusEnvelope(
            statusRevision: 1,
            encodedEnvelope: bytes
        )
        state.statusDeliveryResult = .retryPending
        try state.validate()
        return state
    }

    private func response(
        _ kind: AppleSourceApplyResultKind,
        revision: Int
    ) -> AppleSourceApplyResponse {
        AppleSourceApplyResponse(
            kind: kind,
            entityType: .reminder,
            sourceRevision: revision
        )
    }

    private func makeCoordinator(
        store: BridgeStatePersisting,
        reader: AppleSourceReading,
        delivery: AppleSourceDelivering,
        statusDelivery: AppleBridgeStatusDelivering = AcknowledgingStatusDeliveryClient()
    ) -> ManualSyncCoordinator {
        ManualSyncCoordinator(
            stateStore: store,
            sourceReader: reader,
            deliveryClient: delivery,
            statusDeliveryClient: statusDelivery,
            clock: { self.now },
            windowTimeZone: { TimeZone(identifier: "Etc/UTC")! }
        )
    }

    private func makeViewModel(reader: AppleSourceReading) -> BridgeViewModel {
        BridgeViewModel(
            stateStore: MemoryStateStore(
                BridgePersistentState.fresh(bridgeId: "synthetic-bridge")
            ),
            sourceReader: reader,
            credentialStore: SyntheticCredentialStore(),
            transport: UnusedHTTPTransport(),
            provisioningInbox: NoopBridgeProvisioningInbox(),
            loginItemController: SyntheticLoginItemController(status: .notRegistered),
            backgroundScheduler: SyntheticBackgroundScheduler(),
            wakeObserver: SyntheticWakeObserver(),
            unattendedStateStore: MemoryUnattendedStateStore()
        )
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0 ..< 200 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for synthetic delivery")
    }
}
