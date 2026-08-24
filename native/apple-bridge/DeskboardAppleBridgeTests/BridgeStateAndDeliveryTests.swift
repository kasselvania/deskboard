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

    func requestPermission(for entity: BridgeSourceEntity) async -> BridgePermissionState {
        permissionState(for: entity)
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
        endpoint: LoopbackIngestionEndpoint
    ) async throws -> AppleSourceApplyResponse {
        envelopes.append(envelopeData)
        guard !outcomes.isEmpty else { throw Failure.uncertain }
        return try outcomes.removeFirst().get()
    }
}

@MainActor
final class BridgeStateAndDeliveryTests: XCTestCase {
    private let now = SyntheticSourceReader.date("2026-08-23T18:00:00Z")

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
        delivery: AppleSourceDelivering
    ) -> ManualSyncCoordinator {
        ManualSyncCoordinator(
            stateStore: store,
            sourceReader: reader,
            deliveryClient: delivery,
            clock: { self.now },
            windowTimeZone: { TimeZone(identifier: "Etc/UTC")! }
        )
    }
}
