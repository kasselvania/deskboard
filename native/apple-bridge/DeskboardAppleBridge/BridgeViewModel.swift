import Foundation
import SwiftUI

struct BridgeStatusRow: Identifiable {
    let id: String
    let label: String
    let entity: String
    let revision: Int
    let status: String
    let lastAttemptedAt: Date?
    let lastAcknowledgedAt: Date?
    let hasPendingEnvelope: Bool
}

@MainActor
final class BridgeViewModel: ObservableObject {
    @Published private(set) var calendarPermission: BridgePermissionState = .notDetermined
    @Published private(set) var reminderPermission: BridgePermissionState = .notDetermined
    @Published private(set) var calendarSources: [BridgeSourceDescriptor] = []
    @Published private(set) var reminderSources: [BridgeSourceDescriptor] = []
    @Published private(set) var selectedCalendarSourceIds: Set<String> = []
    @Published private(set) var selectedReminderSourceIds: Set<String> = []
    @Published private(set) var calendarPermissionRequestResult:
        BridgePermissionRequestResult?
    @Published private(set) var reminderPermissionRequestResult:
        BridgePermissionRequestResult?
    @Published private(set) var statusRows: [BridgeStatusRow] = []
    @Published private(set) var bridgeId = ""
    @Published private(set) var isSyncing = false
    @Published private(set) var notice = "Ready for manual setup."
    @Published var coreOriginInput = ""
    @Published var tokenInput = ""

    private let stateStore: BridgeStatePersisting
    private let sourceReader: AppleSourceReading
    private let credentialStore: BridgeCredentialStore
    private let provisioningInbox: BridgeProvisioningImporting
    private let coordinator: ManualSyncCoordinator

    init(
        stateStore: BridgeStatePersisting = AtomicBridgeStateFileStore(),
        sourceReader: AppleSourceReading = EventKitBridgeReader(),
        credentialStore: BridgeCredentialStore = KeychainBridgeCredentialStore(),
        transport: AppleSourceHTTPTransport = URLSessionAppleSourceHTTPTransport(),
        provisioningInbox: BridgeProvisioningImporting? = nil
    ) {
        self.stateStore = stateStore
        self.sourceReader = sourceReader
        self.credentialStore = credentialStore
        self.provisioningInbox = provisioningInbox ?? BridgeProvisioningInbox(
            stateStore: stateStore,
            credentialStore: credentialStore
        )
        coordinator = ManualSyncCoordinator(
            stateStore: stateStore,
            sourceReader: sourceReader,
            deliveryClient: AppleSourceDeliveryClient(
                credentialStore: credentialStore,
                transport: transport
            ),
            statusDeliveryClient: AppleBridgeStatusDeliveryClient(
                credentialStore: credentialStore,
                transport: transport
            )
        )
        importProvisioningRequest()
    }

    var selectedCalendarCount: Int { selectedCalendarSourceIds.count }
    var selectedReminderCount: Int { selectedReminderSourceIds.count }
    @Published private(set) var hasPendingStatus = false

    var pendingCount: Int {
        statusRows.filter(\.hasPendingEnvelope).count + (hasPendingStatus ? 1 : 0)
    }

    func refresh() {
        do {
            let state = try stateStore.loadOrCreate()
            bridgeId = state.bridgeId
            coreOriginInput = state.coreOrigin ?? ""
            selectedCalendarSourceIds = Set(state.selectedCalendarSourceIds)
            selectedReminderSourceIds = Set(state.selectedReminderSourceIds)
            calendarPermission = sourceReader.permissionState(for: .calendar)
            reminderPermission = sourceReader.permissionState(for: .reminder)
            calendarSources = sourceReader.availableSources(for: .calendar)
            reminderSources = sourceReader.availableSources(for: .reminder)
            statusRows = makeStatusRows(state.deliveries)
            hasPendingStatus = state.pendingStatus != nil
        } catch {
            notice = "Bridge state requires operator action."
        }
    }

    func importProvisioningRequest() {
        let result = provisioningInbox.importRequestIfPresent()
        refresh()
        switch result {
        case .applied:
            notice = "Bootstrap provisioning applied."
        case .rejectedInvalid, .unavailable:
            notice = "Bootstrap provisioning requires operator action."
        case nil:
            break
        }
    }

    func requestPermission(for entity: BridgeSourceEntity) async {
        let result = await sourceReader.requestPermission(for: entity)
        switch entity {
        case .calendar:
            calendarPermissionRequestResult = result
        case .reminder:
            reminderPermissionRequestResult = result
        }
        refresh()
        notice = permissionNotice(for: result)
    }

    func setSelected(
        _ selected: Bool,
        sourceContainerId: String,
        entity: BridgeSourceEntity
    ) {
        do {
            var state = try stateStore.loadOrCreate()
            var values = Set(state.selections(for: entity))
            if selected {
                values.insert(sourceContainerId)
            } else {
                values.remove(sourceContainerId)
            }
            state.setSelections(values, for: entity)
            try stateStore.save(state)
            refresh()
        } catch {
            notice = "Source selection could not be stored."
        }
    }

    func saveCoreOrigin() {
        do {
            let endpoint = try CoreIngestionEndpoint(origin: coreOriginInput)
            var state = try stateStore.loadOrCreate()
            state.coreOrigin = endpoint.origin.absoluteString
            try stateStore.save(state)
            coreOriginInput = endpoint.origin.absoluteString
            notice = "Core origin stored."
        } catch {
            notice = "Core origin must be numeric loopback HTTP or private Tailscale HTTPS."
        }
    }

    func storeToken() {
        do {
            try credentialStore.storeToken(tokenInput)
            tokenInput = ""
            notice = "Credential stored in Keychain."
        } catch {
            tokenInput = ""
            notice = "Credential must be a 64-character lowercase hexadecimal value."
        }
    }

    func syncNow() {
        guard !isSyncing else { return }
        isSyncing = true
        notice = pendingCount > 0
            ? "Retrying persisted pending delivery before reading Apple."
            : "Manual synchronization in progress."
        Task {
            defer { isSyncing = false }
            do {
                let state = try await coordinator.syncNow()
                statusRows = makeStatusRows(state.deliveries)
                hasPendingStatus = state.pendingStatus != nil
                notice = state.pendingStatus != nil
                    || state.deliveries.contains(where: { $0.pending != nil })
                    ? "A persisted delivery remains pending or blocked."
                    : "Manual synchronization finished."
                refresh()
            } catch {
                notice = (error as? LocalizedError)?.errorDescription
                    ?? "Manual synchronization could not start."
                refresh()
            }
        }
    }

    private func makeStatusRows(
        _ deliveries: [BridgeSourceDeliveryState]
    ) -> [BridgeStatusRow] {
        var entityOrdinals: [BridgeSourceEntity: Int] = [:]
        return deliveries.map { delivery in
            let ordinal = (entityOrdinals[delivery.coordinate.entityType] ?? 0) + 1
            entityOrdinals[delivery.coordinate.entityType] = ordinal
            let entityLabel = delivery.coordinate.entityType == .calendar
                ? "Calendar"
                : "Reminder"
            return BridgeStatusRow(
                id: "\(delivery.coordinate.entityType.rawValue)-\(ordinal)",
                label: "\(entityLabel) source \(ordinal)",
                entity: entityLabel,
                revision: delivery.pending?.sourceRevision
                    ?? delivery.acknowledgedRevision,
                status: delivery.status.rawValue,
                lastAttemptedAt: delivery.lastAttemptedAt,
                lastAcknowledgedAt: delivery.lastAcknowledgedAt,
                hasPendingEnvelope: delivery.pending != nil
            )
        }
    }

    private func permissionNotice(
        for result: BridgePermissionRequestResult
    ) -> String {
        let entity = result.entity == .calendar ? "Calendar" : "Reminders"
        switch result.outcome {
        case .granted:
            return "\(entity) access granted."
        case .denied:
            return "\(entity) access denied."
        case .restricted:
            return "\(entity) access is restricted."
        case .unavailable:
            return "\(entity) full access is unavailable."
        case .systemRequestError:
            return "\(entity) access request could not be completed. Verify signing and installation, then retry."
        case .noSystemDecision:
            return "\(entity) access request did not produce a system decision. Verify signing and installation, then retry."
        }
    }
}
