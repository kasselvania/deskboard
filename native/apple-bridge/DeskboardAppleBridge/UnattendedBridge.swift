import AppKit
import Foundation
import ServiceManagement

enum BridgeSyncTrigger: String, Hashable {
    case manual
    case scheduled
    case wake
}

enum BridgeContentFreeResult: String, Codable, Equatable {
    case completed
    case pendingOrBlocked
    case unavailable
    case operatorAction
    case failed
    case deferred

    static func classify(
        _ result: Result<BridgePersistentState, Error>
    ) -> BridgeContentFreeResult {
        switch result {
        case let .success(state):
            if state.statusDeliveryResult == .operatorActionStale
                || state.statusDeliveryResult == .operatorActionConflict
                || state.deliveries.contains(where: {
                    $0.status == .operatorActionStale
                        || $0.status == .operatorActionConflict
                })
            {
                return .operatorAction
            }
            if state.pendingStatus != nil
                || state.deliveries.contains(where: { $0.pending != nil })
                || state.statusDeliveryResult == .blockedInvalid
                || state.statusDeliveryResult == .retryPending
                || state.deliveries.contains(where: {
                    $0.status == .blockedTruncated
                        || $0.status == .blockedInvalid
                        || $0.status == .retryPending
                })
            {
                return .pendingOrBlocked
            }
            if state.deliveries.contains(where: {
                $0.status == .permissionUnavailable
                    || $0.status == .sourceUnavailable
            }) {
                return .unavailable
            }
            return .completed
        case let .failure(error):
            if let manualError = error as? ManualSyncError {
                switch manualError {
                case .configurationRequired, .revisionExhausted:
                    return .operatorAction
                case .alreadyInProgress:
                    return .failed
                }
            }
            if let stateError = error as? BridgeStateError {
                switch stateError {
                case .invalid: return .operatorAction
                case .unavailable: return .unavailable
                }
            }
            return .failed
        }
    }
}

struct BridgeSyncQueueState: Equatable {
    let isActive: Bool
    let isQueued: Bool
}

@MainActor
final class BridgeSyncRequestCoalescer {
    typealias Runner = () async throws -> BridgePersistentState
    typealias Completion = (Result<BridgePersistentState, Error>) -> Void

    private let runner: Runner
    private var active = false
    private var queuedTriggers: Set<BridgeSyncTrigger> = []
    private var queuedCompletions: [Completion] = []
    var onStateChange: ((BridgeSyncQueueState) -> Void)?

    init(runner: @escaping Runner) {
        self.runner = runner
    }

    var state: BridgeSyncQueueState {
        BridgeSyncQueueState(
            isActive: active,
            isQueued: !queuedTriggers.isEmpty
        )
    }

    func request(
        _ trigger: BridgeSyncTrigger,
        completion: @escaping Completion = { _ in }
    ) {
        if active {
            queuedTriggers.insert(trigger)
            queuedCompletions.append(completion)
            publishState()
            return
        }
        begin(triggers: [trigger], completions: [completion])
    }

    private func begin(
        triggers _: Set<BridgeSyncTrigger>,
        completions: [Completion]
    ) {
        active = true
        publishState()
        Task {
            let result: Result<BridgePersistentState, Error>
            do {
                result = .success(try await runner())
            } catch {
                result = .failure(error)
            }
            finish(result, completions: completions)
        }
    }

    private func finish(
        _ result: Result<BridgePersistentState, Error>,
        completions: [Completion]
    ) {
        let nextTriggers = queuedTriggers
        let nextCompletions = queuedCompletions
        queuedTriggers.removeAll()
        queuedCompletions.removeAll()

        if nextTriggers.isEmpty {
            active = false
            publishState()
            completions.forEach { $0(result) }
            return
        }

        // Keep the active flag set while handing off to the one coalesced run.
        // Requests made by a completion callback therefore cannot overlap it.
        publishState()
        completions.forEach { $0(result) }
        begin(triggers: nextTriggers, completions: nextCompletions)
    }

    private func publishState() {
        onStateChange?(state)
    }
}

enum BridgeLoginItemState: String, Equatable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
}

@MainActor
protocol MainAppLoginItemControlling: AnyObject {
    var status: BridgeLoginItemState { get }
    func register() throws
    func unregister() throws
    func openSystemSettings()
}

@MainActor
final class SMMainAppLoginItemController: MainAppLoginItemControlling {
    var status: BridgeLoginItemState {
        Self.map(SMAppService.mainApp.status)
    }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    static func map(_ status: SMAppService.Status) -> BridgeLoginItemState {
        switch status {
        case .notRegistered: .notRegistered
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        @unknown default: .notFound
        }
    }
}

enum BridgeBackgroundQualityOfService: String, Equatable {
    case background
}

struct BridgeBackgroundScheduleConfiguration: Equatable {
    let identifier: String
    let interval: TimeInterval
    let tolerance: TimeInterval
    let repeats: Bool
    let qualityOfService: BridgeBackgroundQualityOfService
}

enum BridgeBackgroundActivityCompletion: Equatable {
    case finished
    case deferred
}

@MainActor
protocol BridgeBackgroundActivityScheduling: AnyObject {
    func schedule(
        configuration: BridgeBackgroundScheduleConfiguration,
        handler: @escaping (
            _ shouldDefer: Bool,
            _ completion: @escaping (BridgeBackgroundActivityCompletion) -> Void
        ) -> Void
    )
    func invalidate()
}

@MainActor
final class FoundationBackgroundActivityScheduler: BridgeBackgroundActivityScheduling {
    private final class SchedulerReference: @unchecked Sendable {
        weak var value: NSBackgroundActivityScheduler?
    }

    private var scheduler: NSBackgroundActivityScheduler?

    func schedule(
        configuration: BridgeBackgroundScheduleConfiguration,
        handler: @escaping (
            _ shouldDefer: Bool,
            _ completion: @escaping (BridgeBackgroundActivityCompletion) -> Void
        ) -> Void
    ) {
        invalidate()
        let scheduled = NSBackgroundActivityScheduler(
            identifier: configuration.identifier
        )
        scheduled.interval = configuration.interval
        scheduled.tolerance = configuration.tolerance
        scheduled.repeats = configuration.repeats
        scheduled.qualityOfService = .background
        let reference = SchedulerReference()
        reference.value = scheduled
        scheduled.schedule { [reference] completion in
            handler(reference.value?.shouldDefer ?? true) { result in
                switch result {
                case .finished: completion(.finished)
                case .deferred: completion(.deferred)
                }
            }
        }
        scheduler = scheduled
    }

    func invalidate() {
        scheduler?.invalidate()
        scheduler = nil
    }
}

@MainActor
protocol BridgeWakeEventObserving: AnyObject {
    func start(handler: @escaping () -> Void)
    func stop()
}

@MainActor
final class WorkspaceWakeEventObserver: BridgeWakeEventObserving {
    private var token: NSObjectProtocol?

    func start(handler: @escaping () -> Void) {
        stop()
        token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            handler()
        }
    }

    func stop() {
        if let token {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
            self.token = nil
        }
    }
}

protocol UnattendedStatePersisting: AnyObject {
    var ownerOptIn: Bool { get set }
    var lastBackgroundAttempt: Date? { get set }
    var lastSyncRequest: Date? { get set }
    var lastContentFreeResult: BridgeContentFreeResult? { get set }
}

final class UserDefaultsUnattendedStateStore: UnattendedStatePersisting {
    private enum Key {
        static let ownerOptIn = "unattended.owner-opt-in"
        static let lastBackgroundAttempt = "unattended.last-background-attempt"
        static let lastSyncRequest = "unattended.last-sync-request"
        static let lastContentFreeResult = "unattended.last-content-free-result"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var ownerOptIn: Bool {
        get { defaults.bool(forKey: Key.ownerOptIn) }
        set { defaults.set(newValue, forKey: Key.ownerOptIn) }
    }

    var lastBackgroundAttempt: Date? {
        get { defaults.object(forKey: Key.lastBackgroundAttempt) as? Date }
        set { defaults.set(newValue, forKey: Key.lastBackgroundAttempt) }
    }

    var lastSyncRequest: Date? {
        get { defaults.object(forKey: Key.lastSyncRequest) as? Date }
        set { defaults.set(newValue, forKey: Key.lastSyncRequest) }
    }

    var lastContentFreeResult: BridgeContentFreeResult? {
        get {
            defaults.string(forKey: Key.lastContentFreeResult)
                .flatMap(BridgeContentFreeResult.init(rawValue:))
        }
        set { defaults.set(newValue?.rawValue, forKey: Key.lastContentFreeResult) }
    }
}

enum UnattendedOwnerActionResult: Equatable {
    case enabled
    case disabled
    case approvalRequired
    case failed
}

@MainActor
final class UnattendedBridgeController {
    static let scheduleConfiguration = BridgeBackgroundScheduleConfiguration(
        identifier: "com.kasselvania.deskboard.AppleBridge.sync",
        interval: 10 * 60,
        tolerance: 2 * 60,
        repeats: true,
        qualityOfService: .background
    )
    static let wakeThreshold: TimeInterval = 10 * 60

    private let loginItem: MainAppLoginItemControlling
    private let backgroundScheduler: BridgeBackgroundActivityScheduling
    private let wakeObserver: BridgeWakeEventObserving
    private let stateStore: UnattendedStatePersisting
    private let clock: () -> Date
    private let coalescer: BridgeSyncRequestCoalescer
    private var schedulerRunning = false

    private(set) var loginItemState: BridgeLoginItemState
    private(set) var unattendedEnabled = false
    var onStateChange: (() -> Void)?
    var onRunFinished: ((BridgeSyncTrigger, BridgeContentFreeResult) -> Void)?

    init(
        loginItem: MainAppLoginItemControlling,
        backgroundScheduler: BridgeBackgroundActivityScheduling,
        wakeObserver: BridgeWakeEventObserving,
        stateStore: UnattendedStatePersisting,
        clock: @escaping () -> Date = Date.init,
        syncRunner: @escaping BridgeSyncRequestCoalescer.Runner
    ) {
        self.loginItem = loginItem
        self.backgroundScheduler = backgroundScheduler
        self.wakeObserver = wakeObserver
        self.stateStore = stateStore
        self.clock = clock
        coalescer = BridgeSyncRequestCoalescer(runner: syncRunner)
        loginItemState = loginItem.status
        coalescer.onStateChange = { [weak self] _ in
            self?.publishState()
        }
        // Launch is never registration authority. A missing or disabled
        // System Settings entry remains missing or disabled until the owner
        // explicitly uses Keep Board Current or Retry Login Item Registration.
        reconcileScheduling()
    }

    var ownerOptIn: Bool { stateStore.ownerOptIn }
    var lastBackgroundAttempt: Date? { stateStore.lastBackgroundAttempt }
    var lastContentFreeResult: BridgeContentFreeResult? {
        stateStore.lastContentFreeResult
    }
    var isRunActive: Bool { coalescer.state.isActive }
    var isRequestQueued: Bool { coalescer.state.isQueued }

    func setOwnerOptIn(_ enabled: Bool) -> UnattendedOwnerActionResult {
        stateStore.ownerOptIn = enabled
        if enabled {
            return registerOwnerApprovedLoginItem()
        }

        reconcileScheduling()
        do {
            if loginItem.status != .notRegistered {
                try loginItem.unregister()
            }
        } catch {
            refreshLoginItemStatus()
            return .failed
        }
        refreshLoginItemStatus()
        return loginItemState == .notRegistered ? .disabled : .failed
    }

    func retryOwnerApprovedLoginItemRegistration() -> UnattendedOwnerActionResult {
        guard stateStore.ownerOptIn else { return .failed }
        return registerOwnerApprovedLoginItem()
    }

    func refreshLoginItemStatus() {
        loginItemState = loginItem.status
        reconcileScheduling()
        publishState()
    }

    func openLoginItemSettings() {
        loginItem.openSystemSettings()
    }

    func requestManualSync() {
        request(.manual)
    }

    func stopForQuit() {
        backgroundScheduler.invalidate()
        wakeObserver.stop()
        schedulerRunning = false
        unattendedEnabled = false
        publishState()
    }

    private func reconcileScheduling() {
        let shouldRun = stateStore.ownerOptIn
            && loginItemState == .enabled
        unattendedEnabled = shouldRun
        if shouldRun, !schedulerRunning {
            schedulerRunning = true
            backgroundScheduler.schedule(
                configuration: Self.scheduleConfiguration
            ) { [weak self] shouldDefer, completion in
                Task { @MainActor in
                    guard let self else {
                        completion(.finished)
                        return
                    }
                    self.handleBackgroundActivity(
                        shouldDefer: shouldDefer,
                        completion: completion
                    )
                }
            }
            wakeObserver.start { [weak self] in
                self?.handleWake()
            }
        } else if !shouldRun, schedulerRunning {
            backgroundScheduler.invalidate()
            wakeObserver.stop()
            schedulerRunning = false
        }
    }

    private func registerOwnerApprovedLoginItem() -> UnattendedOwnerActionResult {
        do {
            if loginItem.status == .notRegistered
                || loginItem.status == .notFound
            {
                try loginItem.register()
            }
        } catch {
            refreshLoginItemStatus()
            switch loginItemState {
            case .enabled: return .enabled
            case .requiresApproval: return .approvalRequired
            case .notRegistered, .notFound: return .failed
            }
        }
        refreshLoginItemStatus()
        switch loginItemState {
        case .enabled: return .enabled
        case .requiresApproval: return .approvalRequired
        case .notRegistered, .notFound: return .failed
        }
    }

    private func handleBackgroundActivity(
        shouldDefer: Bool,
        completion: @escaping (BridgeBackgroundActivityCompletion) -> Void
    ) {
        refreshLoginItemStatus()
        guard unattendedEnabled else {
            completion(.finished)
            return
        }
        stateStore.lastBackgroundAttempt = clock()
        if shouldDefer {
            stateStore.lastContentFreeResult = .deferred
            publishState()
            completion(.deferred)
            return
        }
        request(.scheduled) { _ in
            completion(.finished)
        }
    }

    private func handleWake() {
        refreshLoginItemStatus()
        guard unattendedEnabled else { return }
        let now = clock()
        if let lastRequest = stateStore.lastSyncRequest,
           now.timeIntervalSince(lastRequest) < Self.wakeThreshold
        {
            return
        }
        request(.wake)
    }

    private func request(
        _ trigger: BridgeSyncTrigger,
        completion: ((BridgeContentFreeResult) -> Void)? = nil
    ) {
        stateStore.lastSyncRequest = clock()
        coalescer.request(trigger) { [weak self] result in
            guard let self else { return }
            let category = BridgeContentFreeResult.classify(result)
            self.stateStore.lastContentFreeResult = category
            self.publishState()
            self.onRunFinished?(trigger, category)
            completion?(category)
        }
    }

    private func publishState() {
        onStateChange?()
    }
}
