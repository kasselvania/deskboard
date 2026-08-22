import Darwin
import Foundation

do {
    if let command = try ProbeCommandLine.parse(Array(CommandLine.arguments.dropFirst())) {
        Task { @MainActor in
            do {
                try await ProbeCommandLine.run(command)
                exit(EXIT_SUCCESS)
            } catch {
                ProbeCommandLine.writeFailure()
                exit(EXIT_FAILURE)
            }
        }
        dispatchMain()
    } else {
        AppleEventKitProbeApp.main()
    }
} catch {
    ProbeCommandLine.writeFailure()
    exit(EXIT_FAILURE)
}
