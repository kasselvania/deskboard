import Darwin
import Foundation

enum CoreEndpointError: Error, LocalizedError {
    case invalid

    var errorDescription: String? {
        "Core must use numeric loopback HTTP or private Tailscale HTTPS."
    }
}

struct CoreIngestionEndpoint: Equatable {
    let origin: URL
    let ingestionURL: URL
    let statusURL: URL

    init(origin value: String) throws {
        guard
            !value.isEmpty,
            value == value.trimmingCharacters(in: .whitespacesAndNewlines),
            value.unicodeScalars.allSatisfy({
                !CharacterSet.controlCharacters.contains($0)
            }),
            var components = URLComponents(string: value),
            components.user == nil,
            components.password == nil,
            components.query == nil,
            components.fragment == nil,
            components.path.isEmpty || components.path == "/",
            let host = components.host
        else {
            throw CoreEndpointError.invalid
        }

        if components.scheme == "http" {
            guard
                Self.isNumericLoopback(host),
                let port = components.port,
                (1 ... 65_535).contains(port)
            else {
                throw CoreEndpointError.invalid
            }
        } else if components.scheme == "https" {
            guard
                components.port == nil || components.port == 443,
                Self.isValidTailscaleHostname(host)
            else {
                throw CoreEndpointError.invalid
            }
            components.host = host.lowercased()
            components.port = nil
        } else {
            throw CoreEndpointError.invalid
        }

        components.path = ""
        guard let origin = components.url else {
            throw CoreEndpointError.invalid
        }
        components.path = "/v1/apple-source-snapshots"
        guard let ingestionURL = components.url else {
            throw CoreEndpointError.invalid
        }
        components.path = "/v1/apple-bridge-status"
        guard let statusURL = components.url else {
            throw CoreEndpointError.invalid
        }
        self.origin = origin
        self.ingestionURL = ingestionURL
        self.statusURL = statusURL
    }

    private static func isNumericLoopback(_ host: String) -> Bool {
        let numericHost: String
        if host.hasPrefix("["), host.hasSuffix("]") {
            numericHost = String(host.dropFirst().dropLast())
        } else {
            numericHost = host
        }

        var ipv4 = in_addr()
        if inet_pton(AF_INET, numericHost, &ipv4) == 1 {
            return (UInt32(bigEndian: ipv4.s_addr) >> 24) == 127
        }

        var ipv6 = in6_addr()
        if inet_pton(AF_INET6, numericHost, &ipv6) == 1 {
            return withUnsafeBytes(of: ipv6) { bytes in
                bytes.dropLast().allSatisfy { $0 == 0 } && bytes.last == 1
            }
        }
        return false
    }

    private static func isValidTailscaleHostname(_ host: String) -> Bool {
        guard
            host.utf8.count <= 253,
            host.unicodeScalars.allSatisfy({ $0.isASCII }),
            !host.hasSuffix("."),
            !host.contains("%")
        else {
            return false
        }

        let labels = host.lowercased().split(separator: ".", omittingEmptySubsequences: false)
        guard
            labels.count >= 3,
            labels.suffix(2).elementsEqual(["ts", "net"]),
            labels.dropLast(2).allSatisfy({ !$0.hasPrefix("xn--") })
        else {
            return false
        }

        return labels.allSatisfy { label in
            guard
                !label.isEmpty,
                label.utf8.count <= 63,
                let first = label.utf8.first,
                let last = label.utf8.last,
                Self.isASCIIAlphanumeric(first),
                Self.isASCIIAlphanumeric(last)
            else {
                return false
            }
            return label.utf8.allSatisfy { byte in
                Self.isASCIIAlphanumeric(byte) || byte == 45
            }
        }
    }

    private static func isASCIIAlphanumeric(_ byte: UInt8) -> Bool {
        (48 ... 57).contains(byte)
            || (65 ... 90).contains(byte)
            || (97 ... 122).contains(byte)
    }
}

struct AppleSourceUploadRequest {
    let url: URL
    let authorizationHeader: String
    let body: Data
    let timeout: TimeInterval
}

struct AppleSourceUploadResponse {
    let statusCode: Int
    let body: Data
}

protocol AppleSourceHTTPTransport: AnyObject {
    func upload(_ request: AppleSourceUploadRequest) async throws -> AppleSourceUploadResponse
}

private final class NoRedirectSessionDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

final class URLSessionAppleSourceHTTPTransport: AppleSourceHTTPTransport {
    private let delegate = NoRedirectSessionDelegate()

    func upload(_ request: AppleSourceUploadRequest) async throws -> AppleSourceUploadResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = request.body
        urlRequest.timeoutInterval = request.timeout
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(request.authorizationHeader, forHTTPHeaderField: "Authorization")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = request.timeout
        configuration.timeoutIntervalForResource = request.timeout
        let session = URLSession(
            configuration: configuration,
            delegate: delegate,
            delegateQueue: nil
        )
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BridgeDeliveryError.transportFailed
        }
        return AppleSourceUploadResponse(
            statusCode: httpResponse.statusCode,
            body: data
        )
    }
}

enum BridgeDeliveryError: Error, LocalizedError, Equatable {
    case credentialUnavailable
    case transportFailed
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .credentialUnavailable: "The Bridge credential is unavailable."
        case .transportFailed: "Core delivery is uncertain and remains pending."
        case .invalidResponse: "Core returned an invalid response; delivery remains pending."
        }
    }
}

protocol AppleSourceDelivering: AnyObject {
    func deliver(
        envelopeData: Data,
        endpoint: CoreIngestionEndpoint
    ) async throws -> AppleSourceApplyResponse
}

protocol AppleBridgeStatusDelivering: AnyObject {
    func deliverStatus(
        envelopeData: Data,
        endpoint: CoreIngestionEndpoint
    ) async throws -> AppleBridgeStatusApplyResponse
}

final class AppleSourceDeliveryClient: AppleSourceDelivering {
    private let credentialStore: BridgeCredentialStore
    private let transport: AppleSourceHTTPTransport

    init(
        credentialStore: BridgeCredentialStore,
        transport: AppleSourceHTTPTransport
    ) {
        self.credentialStore = credentialStore
        self.transport = transport
    }

    func deliver(
        envelopeData: Data,
        endpoint: CoreIngestionEndpoint
    ) async throws -> AppleSourceApplyResponse {
        let envelope: AppleSourceOperationalEnvelopeV1
        do {
            envelope = try AppleSourceEnvelopeCodec.decode(envelopeData)
        } catch {
            throw BridgeDeliveryError.invalidResponse
        }
        guard let token = try credentialStore.readToken() else {
            throw BridgeDeliveryError.credentialUnavailable
        }

        let response: AppleSourceUploadResponse
        do {
            response = try await transport.upload(
                AppleSourceUploadRequest(
                    url: endpoint.ingestionURL,
                    authorizationHeader: "Bearer \(token)",
                    body: envelopeData,
                    timeout: BridgeProductionLimits.uploadTimeout
                )
            )
        } catch {
            throw BridgeDeliveryError.transportFailed
        }

        let result: AppleSourceApplyResponse
        do {
            result = try AppleSourceApplyResponseCodec.decode(response.body)
        } catch {
            throw BridgeDeliveryError.invalidResponse
        }
        guard response.statusCode == result.expectedHTTPStatus else {
            throw BridgeDeliveryError.invalidResponse
        }
        if result.kind != .rejectedInvalid {
            guard
                result.entityType == envelope.snapshot.entityType,
                result.sourceRevision == envelope.sourceRevision
            else {
                throw BridgeDeliveryError.invalidResponse
            }
        }
        return result
    }
}

final class AppleBridgeStatusDeliveryClient: AppleBridgeStatusDelivering {
    private let credentialStore: BridgeCredentialStore
    private let transport: AppleSourceHTTPTransport

    init(
        credentialStore: BridgeCredentialStore,
        transport: AppleSourceHTTPTransport
    ) {
        self.credentialStore = credentialStore
        self.transport = transport
    }

    func deliverStatus(
        envelopeData: Data,
        endpoint: CoreIngestionEndpoint
    ) async throws -> AppleBridgeStatusApplyResponse {
        let snapshot: AppleBridgeStatusSnapshotV1
        do {
            snapshot = try AppleBridgeStatusEnvelopeCodec.decode(envelopeData)
        } catch {
            throw BridgeDeliveryError.invalidResponse
        }
        guard let token = try credentialStore.readToken() else {
            throw BridgeDeliveryError.credentialUnavailable
        }

        let response: AppleSourceUploadResponse
        do {
            response = try await transport.upload(
                AppleSourceUploadRequest(
                    url: endpoint.statusURL,
                    authorizationHeader: "Bearer \(token)",
                    body: envelopeData,
                    timeout: BridgeProductionLimits.uploadTimeout
                )
            )
        } catch {
            throw BridgeDeliveryError.transportFailed
        }

        let result: AppleBridgeStatusApplyResponse
        do {
            result = try AppleBridgeStatusApplyResponseCodec.decode(response.body)
        } catch {
            throw BridgeDeliveryError.invalidResponse
        }
        guard response.statusCode == result.expectedHTTPStatus else {
            throw BridgeDeliveryError.invalidResponse
        }
        if result.kind != .rejectedInvalid {
            guard result.statusRevision == snapshot.statusRevision else {
                throw BridgeDeliveryError.invalidResponse
            }
        }
        return result
    }
}
