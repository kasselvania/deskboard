import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: ProbeViewModel
    @State private var confirmPrivateExport = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                permissionSection
                sourceSection
                inspectionSection
                exportSection
            }
            .padding(28)
            .frame(maxWidth: 920, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshAfterActivation()
        }
        .confirmationDialog(
            "Export private EventKit values?",
            isPresented: $confirmPrivateExport,
            titleVisibility: .visible
        ) {
            Button("Export private inspection", role: .destructive) {
                model.exportPrivateInspection()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The file may contain private titles, notes, identifiers, URLs, and locations. It stays under the ignored private-fixtures/eventkit-probe directory. Never commit, share, screenshot, or paste it into logs.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Apple EventKit Discovery Probe")
                .font(.largeTitle.weight(.semibold))
            Text("A contained, read-only inspector for selected Calendar calendars and Reminder lists. It does not contact Deskboard Core or any network service.")
                .font(.title3)
                .foregroundStyle(.secondary)
            Label(
                "Private source names are masked by default. Inspection results show structure, not content.",
                systemImage: "hand.raised.fill"
            )
            .foregroundStyle(.secondary)
        }
    }

    private var permissionSection: some View {
        GroupBox("Permissions") {
            VStack(spacing: 16) {
                PermissionRow(
                    title: "Calendar",
                    explanation: "Calendar access is needed only to read the selected calendars inside the bounded discovery window.",
                    state: model.calendarPermission,
                    request: { Task { await model.requestAccess(for: .event) } },
                    settings: { model.openPrivacySettings(for: .event) }
                )
                Divider()
                PermissionRow(
                    title: "Reminders",
                    explanation: "Reminders access is needed only to read the selected lists and inspect supported fields.",
                    state: model.reminderPermission,
                    request: { Task { await model.requestAccess(for: .reminder) } },
                    settings: { model.openPrivacySettings(for: .reminder) }
                )
            }
            .padding(.vertical, 8)
        }
    }

    private var sourceSection: some View {
        GroupBox("Source selection") {
            VStack(alignment: .leading, spacing: 18) {
                Toggle("Mask private source titles", isOn: $model.maskSourceTitles)
                Text("No source is selected by default. Calendar and Reminder selections are stored separately; item contents are never stored in preferences.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                SourceList(
                    heading: "Calendar calendars",
                    permission: model.calendarPermission,
                    sources: model.calendarSources,
                    displayTitle: model.displayTitle,
                    isSelected: model.isSelected,
                    setSelected: model.setSelected
                )
                SourceList(
                    heading: "Reminder lists",
                    permission: model.reminderPermission,
                    sources: model.reminderSources,
                    displayTitle: model.displayTitle,
                    isSelected: model.isSelected,
                    setSelected: model.setSelected
                )
            }
            .padding(.vertical, 8)
        }
    }

    private var inspectionSection: some View {
        GroupBox("Bounded inspection") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Calendar: \(ProbeReadBounds.calendarDaysBefore) days before through \(ProbeReadBounds.calendarDaysAfter) days after now. Results are capped at \(ProbeReadBounds.maximumRecordsPerEntity) records per entity. Reminders are read only from selected lists.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button(model.isInspecting ? "Inspecting…" : "Inspect selected sources") {
                    Task { await model.inspectSelectedSources() }
                }
                .disabled(model.isInspecting)

                if let inspection = model.inspection {
                    InspectionSummary(inspection: inspection)
                }

                Text(model.statusMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .padding(.vertical, 8)
        }
    }

    private var exportSection: some View {
        GroupBox("Local exports") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Private exports require confirmation and stay under the ignored private-fixtures/eventkit-probe directory. Synthetic candidates destructively replace content and still require human review before any specimen is committed.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Export private inspection") {
                        confirmPrivateExport = true
                    }
                    .disabled(model.inspection == nil)
                    Button("Generate sanitized candidates") {
                        model.generateSanitizedCandidates()
                    }
                    .disabled(model.inspection == nil)
                }
            }
            .padding(.vertical, 8)
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let explanation: String
    let state: ProbePermissionState
    let request: () -> Void
    let settings: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                Text(explanation).foregroundStyle(.secondary)
                Text("Status: \(state.label)")
                    .font(.callout.weight(.medium))
            }
            Spacer()
            if state == .notDetermined {
                Button("Request access", action: request)
            } else if state == .denied {
                Button("Open Privacy Settings", action: settings)
            } else if state == .requesting {
                ProgressView().controlSize(.small)
            }
        }
    }
}

private struct SourceList: View {
    let heading: String
    let permission: ProbePermissionState
    let sources: [ProbeSourceDescriptor]
    let displayTitle: (ProbeSourceDescriptor, Int) -> String
    let isSelected: (ProbeSourceDescriptor) -> Bool
    let setSelected: (Bool, ProbeSourceDescriptor) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(heading).font(.headline)
            if permission != .granted {
                Text("Grant this source permission to enumerate its containers.")
                    .foregroundStyle(.secondary)
            } else if sources.isEmpty {
                Text("No supported sources are currently available.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(sources.enumerated()), id: \.element.id) { index, source in
                    Toggle(
                        isOn: Binding(
                            get: { isSelected(source) },
                            set: { setSelected($0, source) }
                        )
                    ) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(displayTitle(source, index))
                            Text(sourceDescription(source))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func sourceDescription(_ source: ProbeSourceDescriptor) -> String {
        let mutability = source.allowsContentModifications ? "modifiable by source app" : "read-only"
        let subscription = source.isSubscribed ? " · subscribed" : ""
        return "\(source.sourceType) · \(source.calendarType) · \(mutability)\(subscription)"
    }
}

private struct InspectionSummary: View {
    let inspection: ProbeInspection

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Observed structure").font(.headline)
            Text("\(inspection.reminders.count) Reminder records retained\(inspection.reminderResultsTruncated ? " (capped)" : "") · \(inspection.events.count) Calendar records retained\(inspection.eventResultsTruncated ? " (capped)" : "")")
            ForEach(Array(inspection.reminders.prefix(20).enumerated()), id: \.element.id) { index, item in
                Text(reminderSummary(item, index: index))
                    .font(.caption.monospaced())
            }
            ForEach(Array(inspection.events.prefix(20).enumerated()), id: \.element.id) { index, item in
                Text(eventSummary(item, index: index))
                    .font(.caption.monospaced())
            }
            if inspection.reminders.count > 20 || inspection.events.count > 20 {
                Text("Additional records are omitted from the screen; exports retain the bounded result.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 4)
    }

    private func reminderSummary(_ item: ReminderProbeRecord, index: Int) -> String {
        let start = item.start?.kind.rawValue ?? "absent"
        let due = item.due?.kind.rawValue ?? "absent"
        return "Reminder \(index + 1): start=\(start), due=\(due), completed=\(item.isCompleted), notes=\(item.notes != nil), priority=\(item.priority), recurrence=\(item.recurrences != nil)"
    }

    private func eventSummary(_ item: EventProbeRecord, index: Int) -> String {
        let boundaries = if item.temporal.kind == .allDayRange {
            "startDate=\(item.temporal.startDate != nil), endDate=\(item.temporal.endDate != nil)"
        } else {
            "start=\(item.temporal.startLocalDateTime != nil), end=\(item.temporal.endLocalDateTime != nil), timezone=\(item.temporal.timeZone != nil)"
        }
        return "Event \(index + 1): temporal=\(item.temporal.kind.rawValue), \(boundaries), status=\(item.status), recurrence=\(item.recurrences != nil), detached=\(item.isDetached), location=\(item.location != nil)"
    }
}
