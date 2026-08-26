import Foundation
import XCTest
@testable import DeskboardAppleBridge

private final class DiagnosticStateStore: BridgeStatePersisting {
    let state: BridgePersistentState

    init(state: BridgePersistentState) {
        self.state = state
    }

    func loadOrCreate() throws -> BridgePersistentState { state }
    func save(_ state: BridgePersistentState) throws {}
    func reset() throws -> BridgePersistentState { .fresh() }
}

private final class DiagnosticSourceReader: AppleSourceReading {
    let source: ReminderSourceRead
    private(set) var reminderReadCount = 0

    init(source: ReminderSourceRead) {
        self.source = source
    }

    func permissionState(for entity: BridgeSourceEntity) -> BridgePermissionState {
        .granted
    }

    func requestPermission(
        for entity: BridgeSourceEntity
    ) async -> BridgePermissionRequestResult {
        .completed(
            entity: entity,
            stateBefore: .granted,
            returnedGranted: true,
            stateAfter: .granted
        )
    }

    func availableSources(for entity: BridgeSourceEntity) -> [BridgeSourceDescriptor] {
        []
    }

    func readReminderSource(sourceContainerId: String) async throws -> ReminderSourceRead {
        reminderReadCount += 1
        guard sourceContainerId == source.sourceContainerId else {
            throw EventKitBridgeReaderError.sourceUnavailable
        }
        return source
    }

    func readCalendarSource(
        sourceContainerId: String,
        now: Date,
        windowTimeZone: TimeZone
    ) throws -> CalendarSourceRead {
        throw EventKitBridgeReaderError.sourceUnavailable
    }
}

@MainActor
final class ReminderCompletenessDiagnosticTests: XCTestCase {
    func testMeasuresCompleteCandidateWithoutExposingSourceValues() async throws {
        let source = reminderSource(recordCount: 945)
        let reader = DiagnosticSourceReader(source: source)
        let diagnostic = ReminderCompletenessDiagnostic(
            stateStore: DiagnosticStateStore(state: blockedState()),
            sourceReader: reader,
            clock: { self.date("2026-08-26T12:00:00Z") }
        )

        let report = try await diagnostic.measureBlockedSelectedReminder()

        XCTAssertEqual(report.matchedRecordCount, 945)
        XCTAssertEqual(report.retainedRecordCount, 945)
        XCTAssertNotNil(report.completeCandidateEncodedByteCount)
        XCTAssertEqual(report.currentRecordCap, 1_000)
        XCTAssertEqual(report.currentEnvelopeLimitBytes, 768 * 1024)
        XCTAssertTrue(report.completeCandidateFitsBoundedMemory)
        XCTAssertTrue(report.completeCandidateFitsEnvelopeLimit)
        XCTAssertTrue(report.completeCandidateFitsCoreLimit)
        XCTAssertTrue(report.completeCandidateFitsProxyLimit)
        XCTAssertEqual(reader.reminderReadCount, 1)
        XCTAssertFalse(String(describing: report).contains("synthetic-blocked-source"))
        XCTAssertFalse(String(describing: report).contains("Synthetic private-shaped title"))
    }

    func testRefusesCompleteEncodingOutsideTheFiniteRecordBudget() async throws {
        let source = reminderSource(
            recordCount: BridgeProductionLimits.completenessDiagnosticMaximumRecords + 1
        )
        let diagnostic = ReminderCompletenessDiagnostic(
            stateStore: DiagnosticStateStore(state: blockedState()),
            sourceReader: DiagnosticSourceReader(source: source)
        )

        let report = try await diagnostic.measureBlockedSelectedReminder()

        XCTAssertEqual(
            report.matchedRecordCount,
            BridgeProductionLimits.completenessDiagnosticMaximumRecords + 1
        )
        XCTAssertEqual(report.retainedRecordCount, 1_000)
        XCTAssertNil(report.completeCandidateEncodedByteCount)
        XCTAssertFalse(report.completeCandidateFitsBoundedMemory)
        XCTAssertFalse(report.completeCandidateFitsEnvelopeLimit)
        XCTAssertFalse(report.completeCandidateFitsCoreLimit)
        XCTAssertFalse(report.completeCandidateFitsProxyLimit)
    }

    func testRequiresExactlyOneSelectedBlockedReminderWithPendingState() async {
        let diagnostic = ReminderCompletenessDiagnostic(
            stateStore: DiagnosticStateStore(state: .fresh(bridgeId: "synthetic-bridge")),
            sourceReader: DiagnosticSourceReader(source: reminderSource(recordCount: 1))
        )

        do {
            _ = try await diagnostic.measureBlockedSelectedReminder()
            XCTFail("Expected content-free diagnostic failure")
        } catch let error as ReminderCompletenessDiagnosticError {
            XCTAssertEqual(
                error.localizedDescription,
                "The selected Reminder completeness diagnostic is unavailable."
            )
        } catch {
            XCTFail("Expected ReminderCompletenessDiagnosticError")
        }
    }

    private func blockedState() -> BridgePersistentState {
        BridgePersistentState(
            version: BridgePersistentState.schemaVersion,
            bridgeId: "synthetic-bridge",
            selectedCalendarSourceIds: [],
            selectedReminderSourceIds: ["synthetic-blocked-source"],
            coreOrigin: "http://127.0.0.1:3001",
            deliveries: [
                BridgeSourceDeliveryState(
                    coordinate: BridgeSourceCoordinate(
                        entityType: .reminder,
                        sourceContainerId: "synthetic-blocked-source"
                    ),
                    acknowledgedRevision: 0,
                    pending: BridgePendingEnvelope(
                        sourceRevision: 1,
                        encodedEnvelope: Data([0])
                    ),
                    status: .blockedTruncated,
                    lastAttemptedAt: date("2026-08-26T11:55:00Z"),
                    lastAcknowledgedAt: nil
                ),
            ]
        )
    }

    private func reminderSource(recordCount: Int) -> ReminderSourceRead {
        ReminderSourceRead(
            sourceContainerId: "synthetic-blocked-source",
            allowsContentModifications: true,
            records: (0 ..< recordCount).map { index in
                ReminderRecordRead(
                    localIdentifier: String(format: "synthetic-%05d", index),
                    externalIdentifier: nil,
                    title: "Synthetic private-shaped title",
                    startComponents: nil,
                    dueComponents: nil,
                    isCompleted: index.isMultiple(of: 2),
                    completionDate: index.isMultiple(of: 2)
                        ? date("2026-08-25T12:00:00Z")
                        : nil
                )
            }
        )
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
