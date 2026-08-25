import Darwin
import Foundation

enum BridgeProvisioningError: Error, LocalizedError {
    case invalid
    case unavailable

    var errorDescription: String? {
        switch self {
        case .invalid:
            "Bridge provisioning request is invalid."
        case .unavailable:
            "Bridge provisioning is unavailable."
        }
    }
}

enum BridgeProvisioningImportResult: String, Codable, Equatable {
    case applied
    case rejectedInvalid
    case unavailable
}

protocol BridgeProvisioningImporting: AnyObject {
    func importRequestIfPresent() -> BridgeProvisioningImportResult?
}

struct BridgeProvisioningRequestV1: Decodable, Equatable {
    let schemaVersion: Int
    let coreOrigin: String
    let bearerToken: String
}

private struct BridgeProvisioningReceiptV1: Encodable {
    let schemaVersion = 1
    let result: BridgeProvisioningImportResult
}

final class BridgeProvisioningInbox: BridgeProvisioningImporting {
    static let requestFileName = "bootstrap-provisioning-request-v1.json"
    static let receiptFileName = "bootstrap-provisioning-receipt-v1.json"
    static let maximumRequestBytes = 4_096

    let requestURL: URL
    let receiptURL: URL

    private let stateStore: BridgeStatePersisting
    private let credentialStore: BridgeCredentialStore
    private let fileManager: FileManager

    init(
        stateStore: BridgeStatePersisting,
        credentialStore: BridgeCredentialStore,
        directoryURL: URL = AtomicBridgeStateFileStore.defaultSupportDirectoryURL(),
        fileManager: FileManager = .default
    ) {
        self.stateStore = stateStore
        self.credentialStore = credentialStore
        self.fileManager = fileManager
        requestURL = directoryURL.appendingPathComponent(Self.requestFileName)
        receiptURL = directoryURL.appendingPathComponent(Self.receiptFileName)
    }

    func importRequestIfPresent() -> BridgeProvisioningImportResult? {
        do {
            guard let data = try readOwnerOnlyRequest() else { return nil }
            let request = try decodeStrictRequest(data)
            let endpoint: CoreIngestionEndpoint
            do {
                endpoint = try CoreIngestionEndpoint(origin: request.coreOrigin)
            } catch {
                throw BridgeProvisioningError.invalid
            }
            guard
                request.schemaVersion == 1,
                request.bearerToken.wholeMatch(
                    of: KeychainBridgeCredentialStore.tokenPattern
                ) != nil
            else {
                throw BridgeProvisioningError.invalid
            }

            let original = try stateStore.loadOrCreate()
            var updated = original
            updated.coreOrigin = endpoint.origin.absoluteString
            try stateStore.save(updated)
            do {
                try credentialStore.storeToken(request.bearerToken)
            } catch {
                try? stateStore.save(original)
                throw BridgeProvisioningError.unavailable
            }

            do {
                try fileManager.removeItem(at: requestURL)
                try writeReceipt(.applied)
            } catch {
                throw BridgeProvisioningError.unavailable
            }
            return .applied
        } catch BridgeProvisioningError.invalid {
            try? writeReceipt(.rejectedInvalid)
            return .rejectedInvalid
        } catch {
            try? writeReceipt(.unavailable)
            return .unavailable
        }
    }

    private func readOwnerOnlyRequest() throws -> Data? {
        let descriptor = Darwin.open(
            requestURL.path,
            O_RDONLY | O_CLOEXEC | O_NOFOLLOW
        )
        if descriptor < 0 {
            if errno == ENOENT { return nil }
            throw BridgeProvisioningError.unavailable
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)

        var information = stat()
        guard Darwin.fstat(descriptor, &information) == 0 else {
            throw BridgeProvisioningError.unavailable
        }
        guard
            (information.st_mode & S_IFMT) == S_IFREG,
            information.st_uid == geteuid(),
            (information.st_mode & 0o777) == 0o600,
            information.st_nlink == 1,
            information.st_size > 0,
            information.st_size <= Self.maximumRequestBytes
        else {
            throw BridgeProvisioningError.invalid
        }
        try validateOwnerOnlyDirectory()

        guard let data = try handle.readToEnd(), data.count == information.st_size else {
            throw BridgeProvisioningError.unavailable
        }
        return data
    }

    private func validateOwnerOnlyDirectory() throws {
        let attributes = try fileManager.attributesOfItem(
            atPath: requestURL.deletingLastPathComponent().path
        )
        guard
            attributes[.type] as? FileAttributeType == .typeDirectory,
            (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == geteuid(),
            (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700
        else {
            throw BridgeProvisioningError.invalid
        }
    }

    private func decodeStrictRequest(_ data: Data) throws -> BridgeProvisioningRequestV1 {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw BridgeProvisioningError.invalid
        }
        guard
            let dictionary = object as? [String: Any],
            Set(dictionary.keys) == ["schemaVersion", "coreOrigin", "bearerToken"]
        else {
            throw BridgeProvisioningError.invalid
        }
        do {
            return try JSONDecoder().decode(BridgeProvisioningRequestV1.self, from: data)
        } catch {
            throw BridgeProvisioningError.invalid
        }
    }

    private func writeReceipt(_ result: BridgeProvisioningImportResult) throws {
        let directory = receiptURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(BridgeProvisioningReceiptV1(result: result))
        let temporaryURL = directory.appendingPathComponent(
            ".bootstrap-provisioning-receipt-\(UUID().uuidString).tmp"
        )
        guard fileManager.createFile(
            atPath: temporaryURL.path,
            contents: data,
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw BridgeProvisioningError.unavailable
        }
        defer { try? fileManager.removeItem(at: temporaryURL) }
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: temporaryURL.path
        )
        guard Darwin.rename(temporaryURL.path, receiptURL.path) == 0 else {
            throw BridgeProvisioningError.unavailable
        }
    }
}

final class NoopBridgeProvisioningInbox: BridgeProvisioningImporting {
    func importRequestIfPresent() -> BridgeProvisioningImportResult? { nil }
}
