import AppKit
import Foundation

struct ProbeInspectionScope: Equatable {
    let calendarPermission: ProbePermissionState
    let reminderPermission: ProbePermissionState
    let selectedCalendarIdentifiers: Set<String>
    let selectedReminderIdentifiers: Set<String>
}

struct ProbeInspectionScopeTracker {
    private(set) var capturedScope: ProbeInspectionScope?

    mutating func recordInspection(for scope: ProbeInspectionScope) {
        capturedScope = scope
    }

    mutating func clear() {
        capturedScope = nil
    }

    @discardableResult
    mutating func invalidateIfChanged(to currentScope: ProbeInspectionScope) -> Bool {
        guard let capturedScope, capturedScope != currentScope else {
            return false
        }
        self.capturedScope = nil
        return true
    }
}

@MainActor
final class ProbeViewModel: ObservableObject {
    @Published private(set) var calendarPermission: ProbePermissionState
    @Published private(set) var reminderPermission: ProbePermissionState
    @Published private(set) var calendarSources: [ProbeSourceDescriptor] = []
    @Published private(set) var reminderSources: [ProbeSourceDescriptor] = []
    @Published private(set) var selectedCalendarIdentifiers: Set<String>
    @Published private(set) var selectedReminderIdentifiers: Set<String>
    @Published private(set) var inspection: ProbeInspection?
    @Published private(set) var statusMessage = "Choose permissions and sources to begin."
    @Published private(set) var isInspecting = false
    @Published var maskSourceTitles = true

    private let reader: EventKitReader
    private let selectionStore: SourceSelectionStore
    private var inspectionScopeTracker = ProbeInspectionScopeTracker()

    init(
        reader: EventKitReader = EventKitReader(),
        selectionStore: SourceSelectionStore = SourceSelectionStore()
    ) {
        self.reader = reader
        self.selectionStore = selectionStore
        calendarPermission = reader.permissionState(for: .event)
        reminderPermission = reader.permissionState(for: .reminder)
        selectedCalendarIdentifiers = selectionStore.selectedIdentifiers(for: .event)
        selectedReminderIdentifiers = selectionStore.selectedIdentifiers(for: .reminder)
        refreshAvailableSources()
    }

    func refreshAfterActivation() {
        setPermission(reader.permissionState(for: .event), for: .event)
        setPermission(reader.permissionState(for: .reminder), for: .reminder)
        refreshAvailableSources()
    }

    func requestAccess(for entityType: ProbeEntityType) async {
        setPermission(.requesting, for: entityType)
        do {
            _ = try await reader.requestAccess(for: entityType)
            setPermission(reader.permissionState(for: entityType), for: entityType)
            refreshAvailableSources(for: entityType)
            statusMessage = permissionMessage(for: entityType)
        } catch {
            setPermission(reader.permissionState(for: entityType), for: entityType)
            statusMessage = "The permission request could not be completed. No source data was read."
        }
    }

    func isSelected(_ source: ProbeSourceDescriptor) -> Bool {
        switch source.entityType {
        case .event:
            selectedCalendarIdentifiers.contains(source.id)
        case .reminder:
            selectedReminderIdentifiers.contains(source.id)
        }
    }

    func setSelected(_ selected: Bool, source: ProbeSourceDescriptor) {
        switch source.entityType {
        case .event:
            updateSelection(
                selected,
                identifier: source.id,
                identifiers: &selectedCalendarIdentifiers,
                entityType: .event
            )
        case .reminder:
            updateSelection(
                selected,
                identifier: source.id,
                identifiers: &selectedReminderIdentifiers,
                entityType: .reminder
            )
        }
    }

    func displayTitle(for source: ProbeSourceDescriptor, index: Int) -> String {
        guard maskSourceTitles else { return source.title }
        return switch source.entityType {
        case .event: "Calendar \(index + 1)"
        case .reminder: "Reminder list \(index + 1)"
        }
    }

    func inspectSelectedSources() async {
        guard !isInspecting else { return }
        isInspecting = true
        defer { isInspecting = false }
        let inspectedScope = currentInspectionScope

        let reminderBatch: ProbeReadBatch<ReminderProbeRecord>
        if reminderPermission == .granted {
            reminderBatch = await reader.readReminders(
                selectedIdentifiers: selectedReminderIdentifiers
            )
        } else {
            reminderBatch = ProbeReadBatch(records: [], matchedCount: 0)
        }

        let eventResult: (batch: ProbeReadBatch<EventProbeRecord>, window: ProbeReadWindow)
        if calendarPermission == .granted {
            eventResult = reader.readEvents(selectedIdentifiers: selectedCalendarIdentifiers)
        } else {
            eventResult = (
                ProbeReadBatch(records: [], matchedCount: 0),
                reader.emptyReadWindow()
            )
        }

        guard inspectedScope == currentInspectionScope else {
            clearInspection()
            statusMessage = "Authorization or source selection changed during inspection. Run a new inspection."
            return
        }

        let refreshedInspection = ProbeInspection(
            generatedAt: InstantFormatter.string(from: Date())!,
            calendarReadWindow: eventResult.window,
            reminderResultCount: reminderBatch.matchedCount,
            reminderResultsTruncated: reminderBatch.wasTruncated,
            eventResultCount: eventResult.batch.matchedCount,
            eventResultsTruncated: eventResult.batch.wasTruncated,
            reminders: reminderBatch.records,
            events: eventResult.batch.records
        )
        inspection = refreshedInspection
        inspectionScopeTracker.recordInspection(for: inspectedScope)
        statusMessage = "Inspection refreshed. Raw values remain private and are not shown on this screen."
    }

    func exportPrivateInspection() {
        guard let inspection else {
            statusMessage = "Inspect selected sources before exporting."
            return
        }
        do {
            let destination = try ProbeExporter().writePrivateInspection(inspection)
            statusMessage = "Private inspection written locally to \(destination.path). Do not commit or share it."
        } catch {
            statusMessage = "Private export failed before any file was written."
        }
    }

    func generateSanitizedCandidates() {
        guard let inspection else {
            statusMessage = "Inspect selected sources before generating candidates."
            return
        }
        do {
            let destination = try ProbeExporter().writeSanitizedCandidates(inspection)
            statusMessage = "Synthetic candidates written to \(destination.path). Review each one before committing a specimen."
        } catch {
            statusMessage = "Sanitized candidate generation failed."
        }
    }

    func openPrivacySettings(for entityType: ProbeEntityType) {
        let section = entityType == .event ? "Privacy_Calendars" : "Privacy_Reminders"
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(section)"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private func setPermission(_ state: ProbePermissionState, for entityType: ProbeEntityType) {
        switch entityType {
        case .event: calendarPermission = state
        case .reminder: reminderPermission = state
        }
        invalidateInspectionIfScopeChanged()
    }

    private func permissionMessage(for entityType: ProbeEntityType) -> String {
        let name = entityType == .event ? "Calendar" : "Reminders"
        let state = entityType == .event ? calendarPermission : reminderPermission
        switch state {
        case .granted:
            return "\(name) access granted. No source is selected automatically."
        case .denied:
            return "\(name) access denied. Use System Settings > Privacy & Security to revisit it."
        case .unavailable:
            return "\(name) access is restricted or unavailable on this Mac."
        case .notDetermined, .requesting:
            return "\(name) permission remains \(state.label.lowercased())."
        }
    }

    private func refreshAvailableSources() {
        refreshAvailableSources(for: .event)
        refreshAvailableSources(for: .reminder)
    }

    private func refreshAvailableSources(for entityType: ProbeEntityType) {
        let permission = entityType == .event ? calendarPermission : reminderPermission
        guard permission == .granted else {
            switch entityType {
            case .event: calendarSources = []
            case .reminder: reminderSources = []
            }
            return
        }

        let sources = reader.sources(for: entityType)
        let availableIdentifiers = Set(sources.map(\.id))
        switch entityType {
        case .event:
            calendarSources = sources
            selectedCalendarIdentifiers = selectionStore.reconcile(
                selectedIdentifiers: selectedCalendarIdentifiers,
                availableIdentifiers: availableIdentifiers,
                for: .event
            )
        case .reminder:
            reminderSources = sources
            selectedReminderIdentifiers = selectionStore.reconcile(
                selectedIdentifiers: selectedReminderIdentifiers,
                availableIdentifiers: availableIdentifiers,
                for: .reminder
            )
        }
        invalidateInspectionIfScopeChanged()
    }

    private func updateSelection(
        _ selected: Bool,
        identifier: String,
        identifiers: inout Set<String>,
        entityType: ProbeEntityType
    ) {
        if selected {
            identifiers.insert(identifier)
        } else {
            identifiers.remove(identifier)
        }
        selectionStore.save(identifiers, for: entityType)
        clearInspection()
        statusMessage = "Source selection changed. Run a new inspection when ready."
    }

    private var currentInspectionScope: ProbeInspectionScope {
        ProbeInspectionScope(
            calendarPermission: calendarPermission,
            reminderPermission: reminderPermission,
            selectedCalendarIdentifiers: selectedCalendarIdentifiers,
            selectedReminderIdentifiers: selectedReminderIdentifiers
        )
    }

    private func invalidateInspectionIfScopeChanged() {
        guard inspectionScopeTracker.invalidateIfChanged(to: currentInspectionScope) else {
            return
        }
        inspection = nil
        statusMessage = "Authorization or effective source selection changed. Run a new inspection."
    }

    private func clearInspection() {
        inspection = nil
        inspectionScopeTracker.clear()
    }
}
