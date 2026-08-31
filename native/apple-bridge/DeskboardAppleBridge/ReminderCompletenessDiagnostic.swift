import Foundation

enum ReminderCompletenessDiagnosticError: Error, LocalizedError {
    case unavailable

    var errorDescription: String? {
        "The selected Reminder completeness diagnostic is unavailable."
    }
}

struct ReminderCompletenessDiagnosticReport: Equatable {
    let matchedRecordCount: Int
    let retainedRecordCount: Int
    let completeCandidateEncodedByteCount: Int?
    let currentRecordCap: Int
    let currentEnvelopeLimitBytes: Int
    let completeCandidateFitsBoundedMemory: Bool
    let completeCandidateFitsEnvelopeLimit: Bool
    let completeCandidateFitsCoreLimit: Bool
    let completeCandidateFitsProxyLimit: Bool
}

final class ReminderCompletenessDiagnostic {
    private static let fixedEncodingOverheadBytes = 128 * 1024
    private static let maximumEncodingOverheadPerRecord = 1_024
    private static let maximumJSONStringExpansion = 6

    private let stateStore: BridgeStatePersisting
    private let sourceReader: AppleSourceReading
    private let clock: () -> Date

    init(
        stateStore: BridgeStatePersisting,
        sourceReader: AppleSourceReading,
        clock: @escaping () -> Date = Date.init
    ) {
        self.stateStore = stateStore
        self.sourceReader = sourceReader
        self.clock = clock
    }

    func measureBlockedSelectedReminder() async throws
        -> ReminderCompletenessDiagnosticReport
    {
        let state = try stateStore.loadOrCreate()
        let selected = Set(state.selectedReminderSourceIds)
        let blocked = state.deliveries.filter {
            $0.coordinate.entityType == .reminder
                && selected.contains($0.coordinate.sourceContainerId)
                && $0.status == .blockedTruncated
                && $0.pending != nil
        }
        guard blocked.count == 1, let delivery = blocked.first else {
            throw ReminderCompletenessDiagnosticError.unavailable
        }

        let source = try await sourceReader.readReminderSource(
            sourceContainerId: delivery.coordinate.sourceContainerId
        )
        let matchedCount = source.records.count
        let retainedCount = min(
            matchedCount,
            BridgeProductionLimits.maximumRetainedReminderRecordsPerSource
        )
        guard safelyFitsDiagnosticMemory(
            source: source,
            bridgeId: state.bridgeId
        ) else {
            return report(
                matchedCount: matchedCount,
                retainedCount: retainedCount,
                encodedByteCount: nil,
                fitsMemory: false
            )
        }

        let snapshot = try AppleSourceConverter.reminderSnapshot(
            from: source,
            bridgeId: state.bridgeId,
            capturedAt: clock(),
            maximumRecords: matchedCount
        )
        let revision = delivery.pending?.sourceRevision
            ?? delivery.acknowledgedRevision + 1
        let encoded = try AppleSourceEnvelopeCodec.encode(
            AppleSourceOperationalEnvelopeV1(
                sourceRevision: revision,
                snapshot: snapshot
            )
        )
        guard
            encoded.count
                <= BridgeProductionLimits.completenessDiagnosticMaximumEncodingBytes
        else {
            return report(
                matchedCount: matchedCount,
                retainedCount: retainedCount,
                encodedByteCount: nil,
                fitsMemory: false
            )
        }

        return report(
            matchedCount: matchedCount,
            retainedCount: retainedCount,
            encodedByteCount: encoded.count,
            fitsMemory: true
        )
    }

    private func report(
        matchedCount: Int,
        retainedCount: Int,
        encodedByteCount: Int?,
        fitsMemory: Bool
    ) -> ReminderCompletenessDiagnosticReport {
        ReminderCompletenessDiagnosticReport(
            matchedRecordCount: matchedCount,
            retainedRecordCount: retainedCount,
            completeCandidateEncodedByteCount: encodedByteCount,
            currentRecordCap:
                BridgeProductionLimits.maximumRetainedReminderRecordsPerSource,
            currentEnvelopeLimitBytes: BridgeProductionLimits.maximumEncodedEnvelopeBytes,
            completeCandidateFitsBoundedMemory: fitsMemory,
            completeCandidateFitsEnvelopeLimit: fitsMemory
                && encodedByteCount.map {
                    $0 <= BridgeProductionLimits.maximumEncodedEnvelopeBytes
                } == true,
            completeCandidateFitsCoreLimit: fitsMemory
                && encodedByteCount.map {
                    $0 <= BridgeProductionLimits.coreRequestBodyBytes
                } == true,
            completeCandidateFitsProxyLimit: fitsMemory
                && encodedByteCount.map {
                    $0 <= BridgeProductionLimits.proxySourceRequestBodyBytes
                } == true
        )
    }

    private func safelyFitsDiagnosticMemory(
        source: ReminderSourceRead,
        bridgeId: String
    ) -> Bool {
        guard
            source.records.count
                <= BridgeProductionLimits.completenessDiagnosticMaximumRecords
        else {
            return false
        }

        var admittedUTF8Bytes = 0
        guard
            addUTF8Bytes(bridgeId, to: &admittedUTF8Bytes),
            addUTF8Bytes(source.sourceContainerId, to: &admittedUTF8Bytes)
        else {
            return false
        }
        for record in source.records {
            guard
                addUTF8Bytes(record.localIdentifier, to: &admittedUTF8Bytes),
                addUTF8Bytes(record.externalIdentifier, to: &admittedUTF8Bytes),
                addUTF8Bytes(record.title, to: &admittedUTF8Bytes),
                addUTF8Bytes(
                    record.startComponents?.timeZone?.identifier,
                    to: &admittedUTF8Bytes
                ),
                addUTF8Bytes(
                    record.dueComponents?.timeZone?.identifier,
                    to: &admittedUTF8Bytes
                )
            else {
                return false
            }
        }

        let recordOverhead = source.records.count.multipliedReportingOverflow(
            by: Self.maximumEncodingOverheadPerRecord
        )
        let escapedStrings = admittedUTF8Bytes.multipliedReportingOverflow(
            by: Self.maximumJSONStringExpansion
        )
        guard !recordOverhead.overflow, !escapedStrings.overflow else {
            return false
        }
        let partial = Self.fixedEncodingOverheadBytes.addingReportingOverflow(
            recordOverhead.partialValue
        )
        let upperBound = partial.partialValue.addingReportingOverflow(
            escapedStrings.partialValue
        )
        return !partial.overflow
            && !upperBound.overflow
            && upperBound.partialValue
                <= BridgeProductionLimits.completenessDiagnosticMaximumEncodingBytes
    }

    private func addUTF8Bytes(
        _ value: String?,
        to total: inout Int
    ) -> Bool {
        guard let value else { return true }
        let addition = total.addingReportingOverflow(value.utf8.count)
        guard
            !addition.overflow,
            addition.partialValue
                <= BridgeProductionLimits.completenessDiagnosticMaximumAdmittedUTF8Bytes
        else {
            return false
        }
        total = addition.partialValue
        return true
    }
}
