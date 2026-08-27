import AppKit
import SwiftUI

@main
struct DeskboardAppleBridgeApp: App {
    @StateObject private var model = BridgeViewModel()

    var body: some Scene {
        MenuBarExtra("Deskboard Bridge", systemImage: "rectangle.3.group") {
            BridgeMenu(model: model)
        }

        Settings {
            ContentView(model: model)
        }
    }
}

private struct BridgeMenu: View {
    @Environment(\.openSettings) private var openSettings
    @ObservedObject var model: BridgeViewModel

    var body: some View {
        Toggle(
            "Keep Board Current",
            isOn: Binding(
                get: { model.ownerOptedIntoUnattended },
                set: { model.setKeepBoardCurrent($0) }
            )
        )
        Text(model.unattendedEnabled ? "Unattended: enabled" : "Unattended: disabled")
        Text("Login item: \(model.loginItemState.rawValue)")
        if model.isRequestQueued {
            Text("One request is queued")
        }
        Divider()
        Button("Sync Now") { model.syncNow() }
            .disabled(model.isMeasuringReminderCompleteness)
        Button("Open Bridge Settings") {
            openSettings()
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
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
        Divider()
        Button("Quit Deskboard Bridge") {
            model.prepareToQuit()
            NSApplication.shared.terminate(nil)
        }
        .onAppear {
            model.applicationDidBecomeActive()
        }
    }
}
