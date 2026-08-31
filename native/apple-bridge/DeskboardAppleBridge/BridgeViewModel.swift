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
    @Published private(set) var isMeasuringReminderCompleteness = false
    @Published private(set) var reminderCompletenessReport:
        ReminderCompletenessDiagnosticReport?
    @Published private(set) var hasBlockedSelectedReminder = false
    @Published private(set) var ownerOptedIntoUnattended = false
    @Published private(set) var unattendedEnabled = false
    @Published private(set) var loginItemState: BridgeLoginItemState = .notRegistered
    @Published private(set) var lastBackgroundAttempt: Date?
    @Published private(set) var lastContentFreeResult: BridgeContentFreeResult?
    @Published private(set) var isRequestQueued = false
    @Published private(set) var eligibleBlockedTruncationRecoveryCount = 0
    @Published private(set) var isRebuildingBlockedTruncation = false
    @Published private(set) var blockedTruncationRecoveryResult:
        BlockedTruncationRecoveryResult?
    @Published private(set) var replacementPersisted = false
    @Published private(set) var completeReplacementApplied = false
    @Published private(set) var sourceRemainsBlockedTruncated = true
    @Published private(set) var notice = "Ready for manual setup."
    @Published var coreOriginInput = ""
    @Published var tokenInput = ""

    private let stateStore: BridgeStatePersisting
    private let sourceReader: AppleSourceReading
    private let credentialStore: BridgeCredentialStore
    private let provisioningInbox: BridgeProvisioningImporting
    private let unattendedController: UnattendedBridgeController
    private let reminderCompletenessDiagnostic: ReminderCompletenessDiagnostic
    private let blockedTruncationRecovery: BlockedTruncationRecoveryCoordinator
    private var eligibleBlockedTruncationSourceIds: [String] = []
    private var persistedReplacement: PersistedBlockedTruncationReplacement?

    init(
        stateStore: BridgeStatePersisting = AtomicBridgeStateFileStore(),
        sourceReader: AppleSourceReading = EventKitBridgeReader(),
        credentialStore: BridgeCredentialStore = KeychainBridgeCredentialStore(),
        transport: AppleSourceHTTPTransport = URLSessionAppleSourceHTTPTransport(),
        provisioningInbox: BridgeProvisioningImporting? = nil,
        loginItemController: MainAppLoginItemControlling? = nil,
        backgroundScheduler: BridgeBackgroundActivityScheduling? = nil,
        wakeObserver: BridgeWakeEventObserving? = nil,
        unattendedStateStore: UnattendedStatePersisting? = nil
    ) {
        self.stateStore = stateStore
        self.sourceReader = sourceReader
        self.credentialStore = credentialStore
        self.provisioningInbox = provisioningInbox ?? BridgeProvisioningInbox(
            stateStore: stateStore,
            credentialStore: credentialStore
        )
        let manualCoordinator = ManualSyncCoordinator(
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
        reminderCompletenessDiagnostic = ReminderCompletenessDiagnostic(
            stateStore: stateStore,
            sourceReader: sourceReader
        )
        blockedTruncationRecovery = BlockedTruncationRecoveryCoordinator(
            stateStore: stateStore,
            sourceReader: sourceReader
        )
        unattendedController = UnattendedBridgeController(
            loginItem: loginItemController ?? SMMainAppLoginItemController(),
            backgroundScheduler: backgroundScheduler
                ?? FoundationBackgroundActivityScheduler(),
            wakeObserver: wakeObserver ?? WorkspaceWakeEventObserver(),
            stateStore: unattendedStateStore ?? UserDefaultsUnattendedStateStore(),
            syncRunner: { try await manualCoordinator.syncNow() }
        )
        unattendedController.onStateChange = { [weak self] in
            self?.refreshUnattendedState()
        }
        unattendedController.onRunFinished = { [weak self] trigger, result in
            self?.handleRunFinished(trigger: trigger, result: result)
        }
        refreshUnattendedState()
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
            hasBlockedSelectedReminder = state.deliveries.contains {
                $0.coordinate.entityType == .reminder
                    && state.selectedReminderSourceIds.contains(
                        $0.coordinate.sourceContainerId
                    )
                    && $0.status == .blockedTruncated
                    && $0.pending != nil
            }
            eligibleBlockedTruncationSourceIds = blockedTruncationRecovery
                .eligibleReminderSourceIds()
            eligibleBlockedTruncationRecoveryCount =
                eligibleBlockedTruncationSourceIds.count
            sourceRemainsBlockedTruncated = hasBlockedSelectedReminder
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

    func applicationDidBecomeActive() {
        importProvisioningRequest()
        unattendedController.refreshLoginItemStatus()
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
        guard !isMeasuringReminderCompleteness else { return }
        notice = isSyncing
            ? "One synchronization request is queued behind the active run."
            : pendingCount > 0
                ? "Retrying persisted pending delivery before reading Apple."
                : "Manual synchronization in progress."
        unattendedController.requestManualSync()
    }

    func setKeepBoardCurrent(_ enabled: Bool) {
        let result = unattendedController.setOwnerOptIn(enabled)
        presentUnattendedOwnerAction(result)
    }

    func retryLoginItemRegistration() {
        let result = unattendedController
            .retryOwnerApprovedLoginItemRegistration()
        presentUnattendedOwnerAction(result)
    }

    private func presentUnattendedOwnerAction(
        _ result: UnattendedOwnerActionResult
    ) {
        refreshUnattendedState()
        switch result {
        case .enabled:
            notice = "Keep Board Current is enabled."
        case .disabled:
            notice = "Keep Board Current is disabled."
        case .approvalRequired:
            notice = "Login-item approval is required in System Settings."
        case .failed:
            notice = "Login-item registration requires operator action."
        }
    }

    func openLoginItemSettings() {
        unattendedController.openLoginItemSettings()
    }

    func prepareToQuit() {
        unattendedController.stopForQuit()
    }

    func rebuildBlockedSourceWithCurrentLimits() {
        guard
            !isSyncing,
            !isMeasuringReminderCompleteness,
            !isRebuildingBlockedTruncation,
            eligibleBlockedTruncationSourceIds.count == 1,
            let sourceContainerId = eligibleBlockedTruncationSourceIds.first
        else {
            return
        }
        isRebuildingBlockedTruncation = true
        blockedTruncationRecoveryResult = nil
        replacementPersisted = false
        completeReplacementApplied = false
        notice = "Rebuilding the blocked source with current finite limits."
        Task {
            let outcome = await blockedTruncationRecovery.rebuildBlockedReminder(
                sourceContainerId: sourceContainerId
            )
            isRebuildingBlockedTruncation = false
            blockedTruncationRecoveryResult = outcome.result
            switch outcome {
            case let .replacementPersisted(replacement):
                persistedReplacement = replacement
                replacementPersisted = true
                notice = "Complete replacement persisted; existing delivery path is running."
                refresh()
                unattendedController.requestManualSync()
            case .stillTruncated:
                notice = "Source remains truncated; existing pending state is unchanged."
                refresh()
            case .operatorActionRequired:
                notice = "Blocked-source recovery requires operator action."
                refresh()
            }
        }
    }

    func measureBlockedSelectedReminder() {
        guard
            !isSyncing,
            !isMeasuringReminderCompleteness,
            hasBlockedSelectedReminder
        else {
            return
        }
        isMeasuringReminderCompleteness = true
        reminderCompletenessReport = nil
        notice = "Measuring selected Reminder completeness without exposing source content."
        Task {
            defer { isMeasuringReminderCompleteness = false }
            do {
                reminderCompletenessReport = try await reminderCompletenessDiagnostic
                    .measureBlockedSelectedReminder()
                notice = "Selected Reminder completeness measurement finished."
            } catch {
                reminderCompletenessReport = nil
                notice = "Selected Reminder completeness measurement requires operator action."
            }
            refresh()
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

    private func refreshUnattendedState() {
        ownerOptedIntoUnattended = unattendedController.ownerOptIn
        unattendedEnabled = unattendedController.unattendedEnabled
        loginItemState = unattendedController.loginItemState
        lastBackgroundAttempt = unattendedController.lastBackgroundAttempt
        lastContentFreeResult = unattendedController.lastContentFreeResult
        isSyncing = unattendedController.isRunActive
        isRequestQueued = unattendedController.isRequestQueued
    }

    private func handleRunFinished(
        trigger: BridgeSyncTrigger,
        result: BridgeContentFreeResult
    ) {
        refresh()
        refreshPersistedReplacementResult()
        refreshUnattendedState()
        let prefix: String
        switch trigger {
        case .manual: prefix = "Manual synchronization"
        case .scheduled: prefix = "Scheduled synchronization"
        case .wake: prefix = "Wake synchronization"
        }
        switch result {
        case .completed:
            notice = "\(prefix) finished."
        case .pendingOrBlocked:
            notice = "\(prefix) left a delivery pending or blocked."
        case .unavailable:
            notice = "\(prefix) found a required capability unavailable."
        case .operatorAction:
            notice = "\(prefix) requires operator action."
        case .failed:
            notice = "\(prefix) failed content-free."
        case .deferred:
            notice = "\(prefix) was deferred by macOS."
        }
    }

    private func refreshPersistedReplacementResult() {
        guard let persistedReplacement else { return }
        guard let state = try? stateStore.loadOrCreate(),
              let delivery = state.deliveries.first(where: {
                  $0.coordinate == persistedReplacement.coordinate
              })
        else {
            return
        }
        sourceRemainsBlockedTruncated = delivery.status == .blockedTruncated
        completeReplacementApplied =
            delivery.acknowledgedRevision == persistedReplacement.sourceRevision
                && delivery.pending == nil
                && (delivery.status == .applied
                    || delivery.status == .unchangedDuplicate)
        if completeReplacementApplied {
            self.persistedReplacement = nil
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
