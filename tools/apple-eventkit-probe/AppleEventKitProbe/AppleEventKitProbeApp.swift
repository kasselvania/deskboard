import SwiftUI

@main
struct AppleEventKitProbeApp: App {
    @StateObject private var model = ProbeViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 760, minHeight: 700)
        }
        .windowResizability(.contentMinSize)
    }
}
