import Foundation

protocol PreferenceStore: AnyObject {
    func stringArray(forKey defaultName: String) -> [String]?
    func set(_ value: Any?, forKey defaultName: String)
}

extension UserDefaults: PreferenceStore {}

struct SourceSelectionStore {
    static let calendarKey = "selected-calendar-identifiers-v1"
    static let reminderKey = "selected-reminder-list-identifiers-v1"

    private let preferences: PreferenceStore

    init(preferences: PreferenceStore = UserDefaults.standard) {
        self.preferences = preferences
    }

    func selectedIdentifiers(for entityType: ProbeEntityType) -> Set<String> {
        Set(preferences.stringArray(forKey: key(for: entityType)) ?? [])
    }

    func save(_ identifiers: Set<String>, for entityType: ProbeEntityType) {
        preferences.set(identifiers.sorted(), forKey: key(for: entityType))
    }

    @discardableResult
    func reconcile(
        selectedIdentifiers: Set<String>,
        availableIdentifiers: Set<String>,
        for entityType: ProbeEntityType
    ) -> Set<String> {
        let reconciled = selectedIdentifiers.intersection(availableIdentifiers)
        if reconciled != selectedIdentifiers {
            save(reconciled, for: entityType)
        }
        return reconciled
    }

    private func key(for entityType: ProbeEntityType) -> String {
        switch entityType {
        case .event: Self.calendarKey
        case .reminder: Self.reminderKey
        }
    }
}
