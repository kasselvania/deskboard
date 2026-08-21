import Foundation

enum ProbeExportError: Error, LocalizedError {
    case repositoryRootUnavailable

    var errorDescription: String? {
        switch self {
        case .repositoryRootUnavailable:
            "Set DESKBOARD_REPOSITORY_ROOT or launch the probe from the repository root."
        }
    }
}

struct ProbeExportLocations {
    let privateRoot: URL

    static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        currentDirectory: String = FileManager.default.currentDirectoryPath,
        fileManager: FileManager = .default
    ) throws -> Self {
        let rootPath = environment["DESKBOARD_REPOSITORY_ROOT"] ?? currentDirectory
        guard !rootPath.isEmpty else {
            throw ProbeExportError.repositoryRootUnavailable
        }
        let root = URL(fileURLWithPath: rootPath, isDirectory: true)
        let ignoreFile = root.appendingPathComponent(".gitignore", isDirectory: false)
        guard
            fileManager.fileExists(atPath: ignoreFile.path),
            let ignoreContents = try? String(contentsOf: ignoreFile, encoding: .utf8),
            ignoreContents.split(whereSeparator: \.isNewline).contains(where: {
                $0.trimmingCharacters(in: .whitespaces) == "private-fixtures/"
            })
        else {
            throw ProbeExportError.repositoryRootUnavailable
        }
        return Self(
            privateRoot: root
                .appendingPathComponent("private-fixtures", isDirectory: true)
                .appendingPathComponent("eventkit-probe", isDirectory: true)
        )
    }
}

struct ProbeExporter {
    private let fileManager: FileManager
    private let locations: ProbeExportLocations

    init(
        fileManager: FileManager = .default,
        locations: ProbeExportLocations? = nil
    ) throws {
        self.fileManager = fileManager
        self.locations = try locations ?? .resolve()
    }

    func writePrivateInspection(_ inspection: ProbeInspection) throws -> URL {
        try fileManager.createDirectory(
            at: locations.privateRoot,
            withIntermediateDirectories: true
        )
        let destination = locations.privateRoot
            .appendingPathComponent("private-inspection-latest.json", isDirectory: false)
        try encoded(inspection).write(to: destination, options: .atomic)
        return destination
    }

    func writeSanitizedCandidates(_ inspection: ProbeInspection) throws -> URL {
        let directory = locations.privateRoot
            .appendingPathComponent("sanitized-candidates", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let sanitized = ProbeSanitizer.sanitize(inspection)

        for (index, reminder) in sanitized.reminders.enumerated() {
            let destination = directory.appendingPathComponent(
                String(format: "reminder-candidate-%03d.json", index + 1)
            )
            try encoded(reminder).write(to: destination, options: .atomic)
        }
        for (index, event) in sanitized.events.enumerated() {
            let destination = directory.appendingPathComponent(
                String(format: "event-candidate-%03d.json", index + 1)
            )
            try encoded(event).write(to: destination, options: .atomic)
        }
        return directory
    }

    private func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
}
