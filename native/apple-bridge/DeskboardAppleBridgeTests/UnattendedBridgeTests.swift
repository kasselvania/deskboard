import Foundation
import ServiceManagement
import XCTest
@testable import DeskboardAppleBridge

enum SyntheticUnattendedError: Error {
    case refused
}

@MainActor
final class SyntheticLoginItemController: MainAppLoginItemControlling {
    var status: BridgeLoginItemState
    var statusAfterRegister: BridgeLoginItemState = .enabled
    var registerError: Error?
    var unregisterError: Error?
    private(set) var registerCount = 0
    private(set) var unregisterCount = 0
    private(set) var settingsOpenCount = 0

    init(status: BridgeLoginItemState) {
        self.status = status
    }

    func register() throws {
        registerCount += 1
        if let registerError { throw registerError }
        status = statusAfterRegister
    }

    func unregister() throws {
        unregisterCount += 1
        if let unregisterError { throw unregisterError }
        status = .notRegistered
    }

    func openSystemSettings() {
        settingsOpenCount += 1
    }
}

@MainActor
final class SyntheticBackgroundScheduler: BridgeBackgroundActivityScheduling {
    private(set) var configurations: [BridgeBackgroundScheduleConfiguration] = []
    private(set) var invalidateCount = 0
    private var handler: ((
        Bool,
        @escaping (BridgeBackgroundActivityCompletion) -> Void
    ) -> Void)?

    func schedule(
        configuration: BridgeBackgroundScheduleConfiguration,
        handler: @escaping (
            Bool,
            @escaping (BridgeBackgroundActivityCompletion) -> Void
        ) -> Void
    ) {
        configurations.append(configuration)
        self.handler = handler
    }

    func invalidate() {
        invalidateCount += 1
        handler = nil
    }

    func fire(
        shouldDefer: Bool,
        completion: @escaping (BridgeBackgroundActivityCompletion) -> Void
    ) {
        handler?(shouldDefer, completion)
    }
}

@MainActor
final class SyntheticWakeObserver: BridgeWakeEventObserving {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private var handler: (() -> Void)?

    func start(handler: @escaping () -> Void) {
        startCount += 1
        self.handler = handler
    }

    func stop() {
        stopCount += 1
        handler = nil
    }

    func fire() {
        handler?()
    }
}

final class MemoryUnattendedStateStore: UnattendedStatePersisting {
    var ownerOptIn: Bool
    var lastBackgroundAttempt: Date?
    var lastSyncRequest: Date?
    var lastContentFreeResult: BridgeContentFreeResult?

    init(
        ownerOptIn: Bool = false,
        lastBackgroundAttempt: Date? = nil,
        lastSyncRequest: Date? = nil,
        lastContentFreeResult: BridgeContentFreeResult? = nil
    ) {
        self.ownerOptIn = ownerOptIn
        self.lastBackgroundAttempt = lastBackgroundAttempt
        self.lastSyncRequest = lastSyncRequest
        self.lastContentFreeResult = lastContentFreeResult
    }
}

@MainActor
private final class ControlledSyncRunner {
    private var continuations: [CheckedContinuation<BridgePersistentState, Error>] = []
    private(set) var runCount = 0
    private(set) var concurrentCount = 0
    private(set) var maximumConcurrentCount = 0

    func run() async throws -> BridgePersistentState {
        runCount += 1
        concurrentCount += 1
        maximumConcurrentCount = max(maximumConcurrentCount, concurrentCount)
        defer { concurrentCount -= 1 }
        return try await withCheckedThrowingContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func finishNext() {
        continuations.removeFirst().resume(returning: completedState())
    }
}

@MainActor
final class UnattendedBridgeTests: XCTestCase {
    func testSMAppServiceStatusMappingIsExactAndContentFree() {
        XCTAssertEqual(
            SMMainAppLoginItemController.map(.notRegistered),
            .notRegistered
        )
        XCTAssertEqual(SMMainAppLoginItemController.map(.enabled), .enabled)
        XCTAssertEqual(
            SMMainAppLoginItemController.map(.requiresApproval),
            .requiresApproval
        )
        XCTAssertEqual(SMMainAppLoginItemController.map(.notFound), .notFound)
    }

    func testManualScheduledAndWakeRequestsCoalesceWithoutOverlap() async {
        let runner = ControlledSyncRunner()
        let coalescer = BridgeSyncRequestCoalescer {
            try await runner.run()
        }
        var completions = 0

        coalescer.request(.manual) { _ in completions += 1 }
        await waitUntil { runner.runCount == 1 }
        coalescer.request(.scheduled) { _ in completions += 1 }
        coalescer.request(.wake) { _ in completions += 1 }
        coalescer.request(.manual) { _ in completions += 1 }

        XCTAssertEqual(
            coalescer.state,
            BridgeSyncQueueState(isActive: true, isQueued: true)
        )
        XCTAssertEqual(runner.runCount, 1)
        XCTAssertEqual(runner.maximumConcurrentCount, 1)

        runner.finishNext()
        await waitUntil { runner.runCount == 2 }
        XCTAssertEqual(runner.maximumConcurrentCount, 1)
        XCTAssertEqual(
            coalescer.state,
            BridgeSyncQueueState(isActive: true, isQueued: false)
        )

        runner.finishNext()
        await waitUntil { !coalescer.state.isActive }
        XCTAssertEqual(runner.runCount, 2)
        XCTAssertEqual(runner.maximumConcurrentCount, 1)
        XCTAssertEqual(completions, 4)
    }

    func testOwnerOptInRegistersMainAppAndOptOutStopsFutureWork() async {
        let loginItem = SyntheticLoginItemController(status: .notRegistered)
        let scheduler = SyntheticBackgroundScheduler()
        let wakeObserver = SyntheticWakeObserver()
        let stateStore = MemoryUnattendedStateStore()
        var runCount = 0
        let controller = makeController(
            loginItem: loginItem,
            scheduler: scheduler,
            wakeObserver: wakeObserver,
            stateStore: stateStore
        ) {
            runCount += 1
            return completedState()
        }

        XCTAssertFalse(controller.unattendedEnabled)
        XCTAssertEqual(loginItem.registerCount, 0)
        XCTAssertEqual(controller.setOwnerOptIn(true), .enabled)
        XCTAssertTrue(controller.unattendedEnabled)
        XCTAssertTrue(stateStore.ownerOptIn)
        XCTAssertEqual(loginItem.registerCount, 1)
        XCTAssertEqual(scheduler.configurations.count, 1)
        XCTAssertEqual(wakeObserver.startCount, 1)

        XCTAssertEqual(controller.setOwnerOptIn(false), .disabled)
        XCTAssertFalse(controller.unattendedEnabled)
        XCTAssertFalse(stateStore.ownerOptIn)
        XCTAssertEqual(loginItem.unregisterCount, 1)
        XCTAssertEqual(scheduler.invalidateCount, 1)
        XCTAssertEqual(wakeObserver.stopCount, 1)

        controller.requestManualSync()
        await waitUntil { runCount == 1 && !controller.isRunActive }
        XCTAssertEqual(controller.lastContentFreeResult, .completed)
    }

    func testRelaunchRestoresOnlyPreviouslyOwnerApprovedRegistration() {
        let loginItem = SyntheticLoginItemController(status: .notRegistered)
        let scheduler = SyntheticBackgroundScheduler()
        let wakeObserver = SyntheticWakeObserver()
        let stateStore = MemoryUnattendedStateStore(ownerOptIn: true)

        let controller = makeController(
            loginItem: loginItem,
            scheduler: scheduler,
            wakeObserver: wakeObserver,
            stateStore: stateStore
        ) { completedState() }

        XCTAssertTrue(controller.ownerOptIn)
        XCTAssertEqual(loginItem.registerCount, 1)
        XCTAssertEqual(controller.loginItemState, .enabled)
        XCTAssertTrue(controller.unattendedEnabled)
        XCTAssertEqual(scheduler.configurations.count, 1)
        XCTAssertEqual(wakeObserver.startCount, 1)
    }

    func testRelaunchRepairsOwnerApprovedNotFoundRegistration() {
        let loginItem = SyntheticLoginItemController(status: .notFound)
        let scheduler = SyntheticBackgroundScheduler()
        let stateStore = MemoryUnattendedStateStore(ownerOptIn: true)

        let controller = makeController(
            loginItem: loginItem,
            scheduler: scheduler,
            wakeObserver: SyntheticWakeObserver(),
            stateStore: stateStore
        ) { completedState() }

        XCTAssertEqual(loginItem.registerCount, 1)
        XCTAssertEqual(controller.loginItemState, .enabled)
        XCTAssertTrue(controller.unattendedEnabled)
        XCTAssertEqual(scheduler.configurations.count, 1)
    }

    func testOwnerCanRetryMissingRegistrationWithoutDroppingApproval() {
        let loginItem = SyntheticLoginItemController(status: .notRegistered)
        loginItem.registerError = SyntheticUnattendedError.refused
        let scheduler = SyntheticBackgroundScheduler()
        let stateStore = MemoryUnattendedStateStore(ownerOptIn: true)
        let controller = makeController(
            loginItem: loginItem,
            scheduler: scheduler,
            wakeObserver: SyntheticWakeObserver(),
            stateStore: stateStore
        ) { completedState() }

        XCTAssertTrue(controller.ownerOptIn)
        XCTAssertEqual(loginItem.registerCount, 1)
        XCTAssertEqual(controller.loginItemState, .notRegistered)
        XCTAssertFalse(controller.unattendedEnabled)
        XCTAssertTrue(scheduler.configurations.isEmpty)

        loginItem.registerError = nil
        XCTAssertEqual(
            controller.retryOwnerApprovedLoginItemRegistration(),
            .enabled
        )
        XCTAssertEqual(loginItem.registerCount, 2)
        XCTAssertTrue(controller.ownerOptIn)
        XCTAssertTrue(controller.unattendedEnabled)
        XCTAssertEqual(scheduler.configurations.count, 1)
    }

    func testOwnerApprovalAndSystemSettingsDisableControlOnlyUnattendedWork() async {
        let loginItem = SyntheticLoginItemController(status: .notRegistered)
        loginItem.statusAfterRegister = .requiresApproval
        let scheduler = SyntheticBackgroundScheduler()
        let wakeObserver = SyntheticWakeObserver()
        let stateStore = MemoryUnattendedStateStore()
        var runCount = 0
        let controller = makeController(
            loginItem: loginItem,
            scheduler: scheduler,
            wakeObserver: wakeObserver,
            stateStore: stateStore
        ) {
            runCount += 1
            return completedState()
        }

        XCTAssertEqual(controller.setOwnerOptIn(true), .approvalRequired)
        XCTAssertTrue(controller.ownerOptIn)
        XCTAssertFalse(controller.unattendedEnabled)
        XCTAssertTrue(scheduler.configurations.isEmpty)
        controller.openLoginItemSettings()
        XCTAssertEqual(loginItem.settingsOpenCount, 1)

        loginItem.status = .enabled
        controller.refreshLoginItemStatus()
        XCTAssertTrue(controller.unattendedEnabled)
        XCTAssertEqual(scheduler.configurations.count, 1)
        XCTAssertEqual(wakeObserver.startCount, 1)

        loginItem.status = .notRegistered
        controller.refreshLoginItemStatus()
        XCTAssertFalse(controller.unattendedEnabled)
        XCTAssertEqual(scheduler.invalidateCount, 1)
        XCTAssertEqual(wakeObserver.stopCount, 1)
        XCTAssertTrue(controller.ownerOptIn)

        controller.requestManualSync()
        await waitUntil { runCount == 1 && !controller.isRunActive }
        XCTAssertEqual(controller.lastContentFreeResult, .completed)
    }

    func testSchedulerConfigurationDeferralAndEligibleRun() async {
        let now = date("2026-08-26T12:00:00Z")
        let scheduler = SyntheticBackgroundScheduler()
        let stateStore = MemoryUnattendedStateStore(ownerOptIn: true)
        var runCount = 0
        let controller = makeController(
            loginItem: SyntheticLoginItemController(status: .enabled),
            scheduler: scheduler,
            wakeObserver: SyntheticWakeObserver(),
            stateStore: stateStore,
            clock: { now }
        ) {
            runCount += 1
            return completedState()
        }

        XCTAssertTrue(controller.unattendedEnabled)
        XCTAssertEqual(
            scheduler.configurations,
            [
                BridgeBackgroundScheduleConfiguration(
                    identifier: "com.kasselvania.deskboard.AppleBridge.sync",
                    interval: 600,
                    tolerance: 120,
                    repeats: true,
                    qualityOfService: .background
                ),
            ]
        )

        var completions: [BridgeBackgroundActivityCompletion] = []
        scheduler.fire(shouldDefer: true) { completions.append($0) }
        await waitUntil { completions == [.deferred] }
        XCTAssertEqual(runCount, 0)
        XCTAssertEqual(controller.lastBackgroundAttempt, now)
        XCTAssertEqual(controller.lastContentFreeResult, .deferred)

        scheduler.fire(shouldDefer: false) { completions.append($0) }
        await waitUntil { completions == [.deferred, .finished] }
        XCTAssertEqual(runCount, 1)
        XCTAssertEqual(controller.lastContentFreeResult, .completed)
    }

    func testWakeRequestsAtMostOneOpportunityWhenSufficientlyOld() async {
        let base = date("2026-08-26T12:00:00Z")
        var now = base.addingTimeInterval(599)
        let wakeObserver = SyntheticWakeObserver()
        let stateStore = MemoryUnattendedStateStore(
            ownerOptIn: true,
            lastSyncRequest: base
        )
        var runCount = 0
        let controller = makeController(
            loginItem: SyntheticLoginItemController(status: .enabled),
            scheduler: SyntheticBackgroundScheduler(),
            wakeObserver: wakeObserver,
            stateStore: stateStore,
            clock: { now }
        ) {
            runCount += 1
            return completedState()
        }

        wakeObserver.fire()
        await Task.yield()
        XCTAssertEqual(runCount, 0)

        now = base.addingTimeInterval(600)
        wakeObserver.fire()
        wakeObserver.fire()
        await waitUntil { runCount == 1 && !controller.isRunActive }
        XCTAssertEqual(runCount, 1)
        XCTAssertEqual(stateStore.lastSyncRequest, now)
    }

    func testSystemSettingsDisableAndRelaunchPreserveManualOperation() async {
        let stateStore = MemoryUnattendedStateStore(ownerOptIn: true)
        let loginItem = SyntheticLoginItemController(status: .enabled)
        let firstScheduler = SyntheticBackgroundScheduler()
        var runCount = 0
        let first = makeController(
            loginItem: loginItem,
            scheduler: firstScheduler,
            wakeObserver: SyntheticWakeObserver(),
            stateStore: stateStore
        ) {
            runCount += 1
            return completedState()
        }
        XCTAssertTrue(first.unattendedEnabled)

        loginItem.status = .requiresApproval
        first.refreshLoginItemStatus()
        XCTAssertFalse(first.unattendedEnabled)
        XCTAssertEqual(firstScheduler.invalidateCount, 1)
        first.requestManualSync()
        await waitUntil { runCount == 1 && !first.isRunActive }

        let secondScheduler = SyntheticBackgroundScheduler()
        let relaunched = makeController(
            loginItem: loginItem,
            scheduler: secondScheduler,
            wakeObserver: SyntheticWakeObserver(),
            stateStore: stateStore
        ) { completedState() }
        XCTAssertFalse(relaunched.unattendedEnabled)
        XCTAssertTrue(secondScheduler.configurations.isEmpty)

        let optedOutScheduler = SyntheticBackgroundScheduler()
        stateStore.ownerOptIn = false
        let optedOut = makeController(
            loginItem: SyntheticLoginItemController(status: .enabled),
            scheduler: optedOutScheduler,
            wakeObserver: SyntheticWakeObserver(),
            stateStore: stateStore
        ) { completedState() }
        XCTAssertFalse(optedOut.unattendedEnabled)
        XCTAssertTrue(optedOutScheduler.configurations.isEmpty)
    }

    func testQuitInvalidatesSchedulingWithoutChangingOwnerApproval() {
        let stateStore = MemoryUnattendedStateStore(ownerOptIn: true)
        let scheduler = SyntheticBackgroundScheduler()
        let wakeObserver = SyntheticWakeObserver()
        let controller = makeController(
            loginItem: SyntheticLoginItemController(status: .enabled),
            scheduler: scheduler,
            wakeObserver: wakeObserver,
            stateStore: stateStore
        ) { completedState() }

        controller.stopForQuit()

        XCTAssertFalse(controller.unattendedEnabled)
        XCTAssertTrue(stateStore.ownerOptIn)
        XCTAssertEqual(scheduler.invalidateCount, 1)
        XCTAssertEqual(wakeObserver.stopCount, 1)
    }

    func testContentFreeLocalStatePersistsAcrossRelaunch() throws {
        let suiteName = "synthetic-unattended-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let attemptedAt = date("2026-08-26T12:00:00Z")
        let first = UserDefaultsUnattendedStateStore(defaults: defaults)
        first.ownerOptIn = true
        first.lastBackgroundAttempt = attemptedAt
        first.lastSyncRequest = attemptedAt
        first.lastContentFreeResult = .pendingOrBlocked

        let relaunched = UserDefaultsUnattendedStateStore(defaults: defaults)
        XCTAssertTrue(relaunched.ownerOptIn)
        XCTAssertEqual(relaunched.lastBackgroundAttempt, attemptedAt)
        XCTAssertEqual(relaunched.lastSyncRequest, attemptedAt)
        XCTAssertEqual(relaunched.lastContentFreeResult, .pendingOrBlocked)
    }

    func testOwnerActionFailuresRemainFixedCategories() {
        let loginItem = SyntheticLoginItemController(status: .notRegistered)
        loginItem.registerError = SyntheticUnattendedError.refused
        let stateStore = MemoryUnattendedStateStore()
        let controller = makeController(
            loginItem: loginItem,
            scheduler: SyntheticBackgroundScheduler(),
            wakeObserver: SyntheticWakeObserver(),
            stateStore: stateStore
        ) { throw SyntheticUnattendedError.refused }

        XCTAssertEqual(controller.setOwnerOptIn(true), .failed)
        XCTAssertFalse(controller.unattendedEnabled)
        XCTAssertEqual(controller.loginItemState, .notRegistered)
        XCTAssertTrue(stateStore.ownerOptIn)
    }

    private func makeController(
        loginItem: MainAppLoginItemControlling,
        scheduler: BridgeBackgroundActivityScheduling,
        wakeObserver: BridgeWakeEventObserving,
        stateStore: UnattendedStatePersisting,
        clock: @escaping () -> Date = Date.init,
        syncRunner: @escaping BridgeSyncRequestCoalescer.Runner
    ) -> UnattendedBridgeController {
        UnattendedBridgeController(
            loginItem: loginItem,
            backgroundScheduler: scheduler,
            wakeObserver: wakeObserver,
            stateStore: stateStore,
            clock: clock,
            syncRunner: syncRunner
        )
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0 ..< 200 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for synthetic unattended state")
    }
}

private func completedState() -> BridgePersistentState {
    BridgePersistentState.fresh(bridgeId: "synthetic-bridge")
}

private func date(_ value: String) -> Date {
    ISO8601DateFormatter().date(from: value)!
}
