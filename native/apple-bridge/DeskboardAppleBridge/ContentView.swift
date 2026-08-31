import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: BridgeViewModel

    var body: some View {
        Form {
            Section("Bridge") {
                LabeledContent("Identity", value: model.bridgeId)
                    .textSelection(.enabled)
                TextField(
                    "Loopback HTTP or private Tailscale HTTPS origin",
                    text: $model.coreOriginInput
                )
                    .textFieldStyle(.roundedBorder)
                Button("Store Core Origin") { model.saveCoreOrigin() }
                SecureField("64-character local token", text: $model.tokenInput)
                    .textFieldStyle(.roundedBorder)
                Button("Store Token in Keychain") { model.storeToken() }
            }

            permissionSection(
                title: "Calendar",
                entity: .calendar,
                permission: model.calendarPermission,
                sources: model.calendarSources,
                selected: model.selectedCalendarSourceIds
            )
            permissionSection(
                title: "Reminders",
                entity: .reminder,
                permission: model.reminderPermission,
                sources: model.reminderSources,
                selected: model.selectedReminderSourceIds
            )

            Section("Keep Board Current") {
                Toggle(
                    "Keep Board Current",
                    isOn: Binding(
                        get: { model.ownerOptedIntoUnattended },
                        set: { model.setKeepBoardCurrent($0) }
                    )
                )
                LabeledContent(
                    "Unattended",
                    value: model.unattendedEnabled ? "enabled" : "disabled"
                )
                LabeledContent(
                    "Login item",
                    value: loginItemLabel(model.loginItemState)
                )
                LabeledContent(
                    "Last background attempt",
                    value: model.lastBackgroundAttempt?.formatted()
                        ?? "none"
                )
                LabeledContent(
                    "Last content-free result",
                    value: model.lastContentFreeResult?.rawValue ?? "none"
                )
                LabeledContent(
                    "Queued behind active run",
                    value: model.isRequestQueued ? "yes" : "no"
                )
                Button("Open Login Items Settings") {
                    model.openLoginItemSettings()
                }
                if model.ownerOptedIntoUnattended
                    && (model.loginItemState == .notRegistered
                        || model.loginItemState == .notFound)
                {
                    Button("Retry Login Item Registration") {
                        model.retryLoginItemRegistration()
                    }
                }
                Text(
                    "Deskboard appears under Open at Login, not as a separate App Background Activity helper."
                )
                .foregroundStyle(.secondary)
                Text(
                    "macOS chooses the actual background time; delayed work remains honestly stale."
                )
                .foregroundStyle(.secondary)
            }

            Section("Synchronization") {
                LabeledContent("Selected calendars", value: "\(model.selectedCalendarCount)")
                LabeledContent("Selected reminder lists", value: "\(model.selectedReminderCount)")
                LabeledContent("Persisted pending deliveries", value: "\(model.pendingCount)")
                Button("Sync Now") { model.syncNow() }
                    .disabled(model.isMeasuringReminderCompleteness)
                if model.isSyncing {
                    ProgressView("Synchronization in progress")
                }
                Text(model.notice)
                    .foregroundStyle(.secondary)
            }

            Section("Selected Reminder Completeness") {
                Text("This diagnostic reports counts, finite limits, and fit results only.")
                    .foregroundStyle(.secondary)
                Button("Measure Blocked Selected Reminder") {
                    model.measureBlockedSelectedReminder()
                }
                .disabled(
                    model.isSyncing
                        || model.isMeasuringReminderCompleteness
                        || !model.hasBlockedSelectedReminder
                )
                if model.isMeasuringReminderCompleteness {
                    ProgressView("Measuring completeness")
                }
                if let report = model.reminderCompletenessReport {
                    LabeledContent(
                        "Matched record count",
                        value: "\(report.matchedRecordCount)"
                    )
                    LabeledContent(
                        "Retained record count",
                        value: "\(report.retainedRecordCount)"
                    )
                    LabeledContent(
                        "Complete candidate encoded bytes",
                        value: report.completeCandidateEncodedByteCount.map(String.init)
                            ?? "not safely measurable"
                    )
                    LabeledContent(
                        "Current record cap",
                        value: "\(report.currentRecordCap)"
                    )
                    LabeledContent(
                        "Current envelope limit",
                        value: "\(report.currentEnvelopeLimitBytes) bytes"
                    )
                    diagnosticFit(
                        "Bounded memory",
                        report.completeCandidateFitsBoundedMemory
                    )
                    diagnosticFit(
                        "Envelope",
                        report.completeCandidateFitsEnvelopeLimit
                    )
                    diagnosticFit("Core", report.completeCandidateFitsCoreLimit)
                    diagnosticFit("Private proxy", report.completeCandidateFitsProxyLimit)
                }
                if model.eligibleBlockedTruncationRecoveryCount == 1 {
                    Button("Rebuild blocked source with current limits") {
                        model.rebuildBlockedSourceWithCurrentLimits()
                    }
                    .disabled(
                        model.isSyncing
                            || model.isMeasuringReminderCompleteness
                            || model.isRebuildingBlockedTruncation
                    )
                }
                if model.isRebuildingBlockedTruncation {
                    ProgressView("Rebuilding blocked source")
                }
                if let result = model.blockedTruncationRecoveryResult {
                    LabeledContent("Recovery result", value: result.rawValue)
                    LabeledContent(
                        "Replacement persisted",
                        value: model.replacementPersisted ? "yes" : "no"
                    )
                    LabeledContent(
                        "Complete snapshot applied",
                        value: model.completeReplacementApplied ? "yes" : "no"
                    )
                    LabeledContent(
                        "Source remains blockedTruncated",
                        value: model.sourceRemainsBlockedTruncated ? "yes" : "no"
                    )
                }
            }

            if !model.statusRows.isEmpty {
                Section("Per-source results") {
                    ForEach(model.statusRows) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.label).font(.headline)
                            Text("Result: \(row.status) · revision \(row.revision)")
                            Text(row.hasPendingEnvelope
                                ? "Persisted pending envelope will be retried."
                                : "No persisted pending envelope.")
                            if let attempted = row.lastAttemptedAt {
                                Text("Last attempted: \(attempted.formatted())")
                            }
                            if let acknowledged = row.lastAcknowledgedAt {
                                Text("Last acknowledged: \(acknowledged.formatted())")
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 680, minHeight: 720)
        .padding()
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            model.applicationDidBecomeActive()
        }
    }

    private func loginItemLabel(_ state: BridgeLoginItemState) -> String {
        switch state {
        case .notRegistered: "not registered"
        case .enabled: "enabled"
        case .requiresApproval: "requires approval"
        case .notFound: "not found"
        }
    }

    private func diagnosticFit(_ label: String, _ fits: Bool) -> some View {
        LabeledContent("Fits \(label)", value: fits ? "yes" : "no")
    }

    @ViewBuilder
    private func permissionSection(
        title: String,
        entity: BridgeSourceEntity,
        permission: BridgePermissionState,
        sources: [BridgeSourceDescriptor],
        selected: Set<String>
    ) -> some View {
        Section(title) {
            LabeledContent("Permission", value: permission.rawValue)
            Button("Request \(title) Access") {
                Task {
                    await model.requestPermission(for: entity)
                }
            }
            if permission == .granted {
                if sources.isEmpty {
                    Text("No available sources.")
                } else {
                    ForEach(sources, id: \.sourceContainerId) { source in
                        Toggle(
                            source.localDisplayName,
                            isOn: Binding(
                                get: { selected.contains(source.sourceContainerId) },
                                set: {
                                    model.setSelected(
                                        $0,
                                        sourceContainerId: source.sourceContainerId,
                                        entity: entity
                                    )
                                }
                            )
                        )
                    }
                }
            }
        }
    }
}
