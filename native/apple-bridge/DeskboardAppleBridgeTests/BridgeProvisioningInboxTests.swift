import Foundation
import XCTest
@testable import DeskboardAppleBridge

private final class ProvisioningMemoryStateStore: BridgeStatePersisting {
    var state: BridgePersistentState
    var savedStates: [BridgePersistentState] = []

    init(_ state: BridgePersistentState) {
        self.state = state
    }

    func loadOrCreate() throws -> BridgePersistentState { state }

    func save(_ state: BridgePersistentState) throws {
        try state.validate()
        self.state = state
        savedStates.append(state)
    }

    func reset() throws -> BridgePersistentState {
        XCTFail("Provisioning must never reset Bridge state")
        return state
    }
}

private final class ProvisioningCredentialStore: BridgeCredentialStore {
    var storedTokens: [String] = []
    var shouldFail = false

    func readToken() throws -> String? { nil }

    func storeToken(_ token: String) throws {
        if shouldFail { throw BridgeCredentialError.unavailable }
        storedTokens.append(token)
    }
}

private final class ProvisioningKeychainBackend: KeychainTokenBackend {
    var storedData: Data?

    func read(service: String, account: String) throws -> Data? { storedData }

    func write(_ data: Data, service: String, account: String) throws {
        storedData = data
    }
}

final class BridgeProvisioningInboxTests: XCTestCase {
    private let token = String(repeating: "a", count: 64)
    private let privateOrigin = "https://synthetic-device.synthetic-tailnet.ts.net"

    func testStrictProvisioningRotatesCredentialAndChangesOnlyCoreOrigin() throws {
        let original = try continuityState()
        let originalSourceBytes = try XCTUnwrap(
            original.deliveries.first(where: {
                $0.coordinate.entityType == .reminder
            })?.pending?.encodedEnvelope
        )
        let originalStatusBytes = try XCTUnwrap(original.pendingStatus?.encodedEnvelope)
        let directory = try makeOwnerOnlyDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProvisioningMemoryStateStore(original)
        let keychainBackend = ProvisioningKeychainBackend()
        let credentials = KeychainBridgeCredentialStore(backend: keychainBackend)
        let inbox = BridgeProvisioningInbox(
            stateStore: store,
            credentialStore: credentials,
            directoryURL: directory
        )
        try writeRequest(
            [
                "schemaVersion": 1,
                "coreOrigin": privateOrigin,
                "bearerToken": token,
            ],
            to: inbox.requestURL
        )
        XCTAssertEqual(try permissions(of: inbox.requestURL), 0o600)

        XCTAssertEqual(inbox.importRequestIfPresent(), .applied)

        var expected = original
        expected.coreOrigin = privateOrigin
        XCTAssertEqual(store.state, expected)
        XCTAssertEqual(try credentials.readToken(), token)
        XCTAssertEqual(keychainBackend.storedData, token.data(using: .utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: inbox.requestURL.path))
        XCTAssertEqual(
            try XCTUnwrap(
                store.state.deliveries.first(where: {
                    $0.coordinate.entityType == .reminder
                })?.pending?.encodedEnvelope
            ),
            originalSourceBytes
        )
        XCTAssertEqual(store.state.pendingStatus?.encodedEnvelope, originalStatusBytes)

        XCTAssertEqual(store.state.bridgeId, original.bridgeId)
        XCTAssertEqual(
            store.state.selectedCalendarSourceIds,
            original.selectedCalendarSourceIds
        )
        XCTAssertEqual(
            store.state.selectedReminderSourceIds,
            original.selectedReminderSourceIds
        )
        XCTAssertEqual(
            store.state.deliveries.map(\.coordinate),
            original.deliveries.map(\.coordinate)
        )
        XCTAssertEqual(
            store.state.deliveries.map(\.acknowledgedRevision),
            original.deliveries.map(\.acknowledgedRevision)
        )
        XCTAssertEqual(
            store.state.deliveries.map(\.lastAttemptedAt),
            original.deliveries.map(\.lastAttemptedAt)
        )
        XCTAssertEqual(
            store.state.deliveries.map(\.lastAcknowledgedAt),
            original.deliveries.map(\.lastAcknowledgedAt)
        )
        XCTAssertEqual(
            store.state.acknowledgedStatusRevision,
            original.acknowledgedStatusRevision
        )

        let receipt = try String(contentsOf: inbox.receiptURL, encoding: .utf8)
        XCTAssertEqual(receipt, #"{"result":"applied","schemaVersion":1}"#)
        XCTAssertFalse(receipt.contains(token))
        XCTAssertFalse(receipt.contains(privateOrigin))
        XCTAssertEqual(try permissions(of: inbox.receiptURL), 0o600)
    }

    func testMalformedOrOverpermissiveProvisioningChangesNothing() throws {
        let invalidRequests: [[String: Any]] = [
            [
                "schemaVersion": 1,
                "coreOrigin": privateOrigin,
                "bearerToken": "short",
            ],
            [
                "schemaVersion": 1,
                "coreOrigin": "https://example.com",
                "bearerToken": token,
            ],
            [
                "schemaVersion": 1,
                "coreOrigin": privateOrigin,
                "bearerToken": token,
                "unexpected": true,
            ],
            [
                "schemaVersion": 2,
                "coreOrigin": privateOrigin,
                "bearerToken": token,
            ],
        ]

        for request in invalidRequests {
            let original = try continuityState()
            let directory = try makeOwnerOnlyDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = ProvisioningMemoryStateStore(original)
            let credentials = ProvisioningCredentialStore()
            let inbox = BridgeProvisioningInbox(
                stateStore: store,
                credentialStore: credentials,
                directoryURL: directory
            )
            try writeRequest(request, to: inbox.requestURL)

            XCTAssertEqual(inbox.importRequestIfPresent(), .rejectedInvalid)
            XCTAssertEqual(store.state, original)
            XCTAssertTrue(credentials.storedTokens.isEmpty)
            XCTAssertTrue(FileManager.default.fileExists(atPath: inbox.requestURL.path))
            let receipt = try String(contentsOf: inbox.receiptURL, encoding: .utf8)
            XCTAssertEqual(
                receipt,
                #"{"result":"rejectedInvalid","schemaVersion":1}"#
            )
            XCTAssertFalse(receipt.contains(token))
            XCTAssertFalse(receipt.contains(privateOrigin))
        }

        let original = try continuityState()
        let directory = try makeOwnerOnlyDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProvisioningMemoryStateStore(original)
        let credentials = ProvisioningCredentialStore()
        let inbox = BridgeProvisioningInbox(
            stateStore: store,
            credentialStore: credentials,
            directoryURL: directory
        )
        try writeRequest(
            [
                "schemaVersion": 1,
                "coreOrigin": privateOrigin,
                "bearerToken": token,
            ],
            to: inbox.requestURL,
            mode: 0o644
        )
        XCTAssertEqual(inbox.importRequestIfPresent(), .rejectedInvalid)
        XCTAssertEqual(store.state, original)
        XCTAssertTrue(credentials.storedTokens.isEmpty)

        let malformedOriginal = try continuityState()
        let malformedDirectory = try makeOwnerOnlyDirectory()
        defer { try? FileManager.default.removeItem(at: malformedDirectory) }
        let malformedStore = ProvisioningMemoryStateStore(malformedOriginal)
        let malformedCredentials = ProvisioningCredentialStore()
        let malformedInbox = BridgeProvisioningInbox(
            stateStore: malformedStore,
            credentialStore: malformedCredentials,
            directoryURL: malformedDirectory
        )
        try Data("{".utf8).write(to: malformedInbox.requestURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: malformedInbox.requestURL.path
        )
        XCTAssertEqual(malformedInbox.importRequestIfPresent(), .rejectedInvalid)
        XCTAssertEqual(malformedStore.state, malformedOriginal)
        XCTAssertTrue(malformedCredentials.storedTokens.isEmpty)
    }

    func testProvisioningRerunRotatesAgainWithoutChangingOperationalState() throws {
        let original = try continuityState()
        let directory = try makeOwnerOnlyDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProvisioningMemoryStateStore(original)
        let credentials = ProvisioningCredentialStore()
        let inbox = BridgeProvisioningInbox(
            stateStore: store,
            credentialStore: credentials,
            directoryURL: directory
        )
        let secondToken = String(repeating: "b", count: 64)
        let secondOrigin = "https://second-device.synthetic-tailnet.ts.net"

        for (origin, credential) in [
            (privateOrigin, token),
            (secondOrigin, secondToken),
        ] {
            try writeRequest(
                [
                    "schemaVersion": 1,
                    "coreOrigin": origin,
                    "bearerToken": credential,
                ],
                to: inbox.requestURL
            )
            XCTAssertEqual(inbox.importRequestIfPresent(), .applied)
        }

        var expected = original
        expected.coreOrigin = secondOrigin
        XCTAssertEqual(store.state, expected)
        XCTAssertEqual(credentials.storedTokens, [token, secondToken])
        XCTAssertFalse(FileManager.default.fileExists(atPath: inbox.requestURL.path))
    }

    func testCredentialFailureRollsBackDestinationAndLeavesRequest() throws {
        let original = try continuityState()
        let directory = try makeOwnerOnlyDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProvisioningMemoryStateStore(original)
        let credentials = ProvisioningCredentialStore()
        credentials.shouldFail = true
        let inbox = BridgeProvisioningInbox(
            stateStore: store,
            credentialStore: credentials,
            directoryURL: directory
        )
        try writeRequest(
            [
                "schemaVersion": 1,
                "coreOrigin": privateOrigin,
                "bearerToken": token,
            ],
            to: inbox.requestURL
        )

        XCTAssertEqual(inbox.importRequestIfPresent(), .unavailable)
        XCTAssertEqual(store.state, original)
        XCTAssertTrue(credentials.storedTokens.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: inbox.requestURL.path))
        XCTAssertEqual(
            try String(contentsOf: inbox.receiptURL, encoding: .utf8),
            #"{"result":"unavailable","schemaVersion":1}"#
        )
    }

    func testDestinationRollbackAfterProvisioningPreservesOperationalState() throws {
        let original = try continuityState()
        let directory = try makeOwnerOnlyDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProvisioningMemoryStateStore(original)
        let credentials = ProvisioningCredentialStore()
        let inbox = BridgeProvisioningInbox(
            stateStore: store,
            credentialStore: credentials,
            directoryURL: directory
        )
        try writeRequest(
            [
                "schemaVersion": 1,
                "coreOrigin": privateOrigin,
                "bearerToken": token,
            ],
            to: inbox.requestURL
        )
        XCTAssertEqual(inbox.importRequestIfPresent(), .applied)

        let provisioned = store.state
        var rolledBack = provisioned
        rolledBack.coreOrigin = "http://127.0.0.1:3001"
        try store.save(rolledBack)

        var expected = original
        expected.coreOrigin = "http://127.0.0.1:3001"
        XCTAssertEqual(store.state, expected)
        XCTAssertEqual(credentials.storedTokens, [token])
    }

    func testProvisioningSourceHasNoPermissionOrGeneralCommandBoundary() throws {
        let source = try String(
            contentsOf: projectRoot()
                .appendingPathComponent("DeskboardAppleBridge", isDirectory: true)
                .appendingPathComponent("BridgeProvisioningInbox.swift"),
            encoding: .utf8
        )
        for forbidden in [
            "EventKit",
            "requestPermission",
            "tccutil",
            "CommandLine.arguments",
            "ProcessInfo.processInfo.arguments",
            "NSOpenPanel",
            "NSSavePanel",
        ] {
            XCTAssertFalse(source.contains(forbidden))
        }
    }

    private func continuityState() throws -> BridgePersistentState {
        let bridgeID = "11111111-2222-3333-4444-555555555555"
        let calendarCoordinate = BridgeSourceCoordinate(
            entityType: .calendar,
            sourceContainerId: "synthetic-calendar"
        )
        let reminderCoordinate = BridgeSourceCoordinate(
            entityType: .reminder,
            sourceContainerId: "synthetic-reminder"
        )
        let attempted = date("2026-08-23T17:59:00Z")
        let acknowledged = date("2026-08-23T17:58:00Z")
        let reminderSnapshot = AppleReminderSourceSnapshotV1(
            schemaVersion: 1,
            entityType: .reminder,
            bridgeId: bridgeID,
            source: AppleReminderSourceScopeV1(
                sourceContainerId: reminderCoordinate.sourceContainerId,
                allowsContentModifications: true
            ),
            capturedAt: "2026-08-23T18:00:00.000Z",
            matchedCount: 0,
            truncated: false,
            records: []
        )
        let pendingSourceBytes = try AppleSourceEnvelopeCodec.encodeWithinProductionLimit(
            sourceRevision: 4,
            snapshot: .reminder(reminderSnapshot)
        )
        let deliveries = [
            BridgeSourceDeliveryState(
                coordinate: calendarCoordinate,
                acknowledgedRevision: 8,
                pending: nil,
                status: .applied,
                lastAttemptedAt: attempted,
                lastAcknowledgedAt: acknowledged
            ),
            BridgeSourceDeliveryState(
                coordinate: reminderCoordinate,
                acknowledgedRevision: 3,
                pending: BridgePendingEnvelope(
                    sourceRevision: 4,
                    encodedEnvelope: pendingSourceBytes
                ),
                status: .retryPending,
                lastAttemptedAt: attempted,
                lastAcknowledgedAt: acknowledged
            ),
        ]
        let statusBytes = try AppleBridgeStatusEnvelopeCodec.encode(
            AppleBridgeStatusSnapshotV1(
                schemaVersion: 1,
                bridgeId: bridgeID,
                statusRevision: 12,
                capturedAt: "2026-08-23T18:00:00.000Z",
                permissions: AppleBridgeStatusPermissionsV1(
                    calendar: .denied,
                    reminders: .granted
                ),
                selectedSources: [
                    AppleBridgeSelectedSourceStatusV1(
                        entityType: .calendar,
                        sourceContainerId: calendarCoordinate.sourceContainerId,
                        status: .applied,
                        acknowledgedSourceRevision: 8,
                        pendingSourceRevision: nil,
                        lastAttemptedAt: "2026-08-23T17:59:00.000Z",
                        lastAcknowledgedAt: "2026-08-23T17:58:00.000Z"
                    ),
                    AppleBridgeSelectedSourceStatusV1(
                        entityType: .reminder,
                        sourceContainerId: reminderCoordinate.sourceContainerId,
                        status: .retryPending,
                        acknowledgedSourceRevision: 3,
                        pendingSourceRevision: 4,
                        lastAttemptedAt: "2026-08-23T17:59:00.000Z",
                        lastAcknowledgedAt: "2026-08-23T17:58:00.000Z"
                    ),
                ]
            )
        )
        let state = BridgePersistentState(
            version: 1,
            bridgeId: bridgeID,
            selectedCalendarSourceIds: [calendarCoordinate.sourceContainerId],
            selectedReminderSourceIds: [reminderCoordinate.sourceContainerId],
            coreOrigin: "http://127.0.0.1:3001",
            deliveries: deliveries,
            acknowledgedStatusRevision: 11,
            pendingStatus: BridgePendingStatusEnvelope(
                statusRevision: 12,
                encodedEnvelope: statusBytes
            ),
            statusDeliveryResult: .retryPending
        )
        try state.validate()
        return state
    }

    private func makeOwnerOnlyDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )
        return directory
    }

    private func writeRequest(
        _ object: [String: Any],
        to url: URL,
        mode: Int = 0o600
    ) throws {
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        )
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: mode],
            ofItemAtPath: url.path
        )
    }

    private func permissions(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(
            attributes[.posixPermissions] as? NSNumber
        ).intValue
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    private func projectRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
