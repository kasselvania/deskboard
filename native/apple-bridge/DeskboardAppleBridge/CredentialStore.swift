import Foundation
import Security

enum BridgeCredentialError: Error, LocalizedError {
    case unavailable
    case invalid

    var errorDescription: String? {
        switch self {
        case .unavailable: "The Bridge credential is unavailable."
        case .invalid: "The Bridge credential format is invalid."
        }
    }
}

protocol BridgeCredentialStore: AnyObject {
    func readToken() throws -> String?
    func storeToken(_ token: String) throws
}

protocol KeychainTokenBackend: AnyObject {
    func read(service: String, account: String) throws -> Data?
    func write(_ data: Data, service: String, account: String) throws
}

final class SystemKeychainTokenBackend: KeychainTokenBackend {
    func read(service: String, account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw BridgeCredentialError.unavailable
        }
        return data
    }

    func write(_ data: Data, service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw BridgeCredentialError.unavailable
        }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
            throw BridgeCredentialError.unavailable
        }
    }
}

final class KeychainBridgeCredentialStore: BridgeCredentialStore {
    static let tokenPattern = /^[0-9a-f]{64}$/

    private let service: String
    private let account: String
    private let backend: KeychainTokenBackend

    init(
        service: String = "com.kasselvania.deskboard.apple-bridge",
        account: String = "core-ingestion-bearer-token",
        backend: KeychainTokenBackend = SystemKeychainTokenBackend()
    ) {
        self.service = service
        self.account = account
        self.backend = backend
    }

    func readToken() throws -> String? {
        guard let data = try backend.read(service: service, account: account) else {
            return nil
        }
        guard
            let token = String(data: data, encoding: .utf8),
            token.wholeMatch(of: Self.tokenPattern) != nil
        else {
            throw BridgeCredentialError.invalid
        }
        return token
    }

    func storeToken(_ token: String) throws {
        guard
            token.wholeMatch(of: Self.tokenPattern) != nil,
            let data = token.data(using: .utf8)
        else {
            throw BridgeCredentialError.invalid
        }
        try backend.write(data, service: service, account: account)
    }
}
