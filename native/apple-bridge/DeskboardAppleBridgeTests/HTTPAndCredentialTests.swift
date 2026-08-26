import Foundation
import XCTest
@testable import DeskboardAppleBridge

private final class MemoryCredentialStore: BridgeCredentialStore {
    var token: String?
    var readCount = 0

    init(token: String?) { self.token = token }

    func readToken() throws -> String? {
        readCount += 1
        return token
    }

    func storeToken(_ token: String) throws { self.token = token }
}

private final class CapturingHTTPTransport: AppleSourceHTTPTransport {
    var requests: [AppleSourceUploadRequest] = []
    var response: AppleSourceUploadResponse
    var error: Error?

    init(statusCode: Int = 200, body: Data) {
        response = AppleSourceUploadResponse(statusCode: statusCode, body: body)
    }

    func upload(_ request: AppleSourceUploadRequest) async throws -> AppleSourceUploadResponse {
        requests.append(request)
        if let error { throw error }
        return response
    }
}

private final class MemoryKeychainBackend: KeychainTokenBackend {
    var stored: Data?
    var reads: [(String, String)] = []
    var writes: [(String, String)] = []

    func read(service: String, account: String) throws -> Data? {
        reads.append((service, account))
        return stored
    }

    func write(_ data: Data, service: String, account: String) throws {
        stored = data
        writes.append((service, account))
    }
}

final class HTTPAndCredentialTests: XCTestCase {
    private let syntheticToken = String(repeating: "a", count: 64)

    func testCoreOriginPolicyAcceptsNumericLoopbackHTTPAndPrivateTailscaleHTTPS() throws {
        XCTAssertEqual(
            try CoreIngestionEndpoint(origin: "http://127.0.0.1:3001")
                .ingestionURL.absoluteString,
            "http://127.0.0.1:3001/v1/apple-source-snapshots"
        )
        XCTAssertEqual(
            try CoreIngestionEndpoint(origin: "http://127.0.0.1:3001")
                .statusURL.absoluteString,
            "http://127.0.0.1:3001/v1/apple-bridge-status"
        )
        XCTAssertEqual(
            try CoreIngestionEndpoint(origin: "http://[::1]:3001")
                .ingestionURL.absoluteString,
            "http://[::1]:3001/v1/apple-source-snapshots"
        )
        XCTAssertNoThrow(
            try CoreIngestionEndpoint(origin: "http://127.42.0.9:3001")
        )

        let privateOrigin = "https://synthetic-device.synthetic-tailnet.ts.net"
        let privateEndpoint = try CoreIngestionEndpoint(origin: privateOrigin)
        XCTAssertEqual(privateEndpoint.origin.absoluteString, privateOrigin)
        XCTAssertEqual(
            privateEndpoint.ingestionURL.absoluteString,
            "\(privateOrigin)/v1/apple-source-snapshots"
        )
        XCTAssertEqual(
            privateEndpoint.statusURL.absoluteString,
            "\(privateOrigin)/v1/apple-bridge-status"
        )
        XCTAssertEqual(
            try CoreIngestionEndpoint(
                origin: "https://SYNTHETIC-DEVICE.SYNTHETIC-TAILNET.TS.NET:443/"
            ).origin.absoluteString,
            privateOrigin
        )
    }

    func testCoreOriginPolicyRejectsEveryOtherDestinationShape() {
        for rejected in [
            "http://localhost:3001",
            "https://127.0.0.1:3001",
            "http://192.168.1.20:3001",
            "http://100.64.0.2:3001",
            "http://user@127.0.0.1:3001",
            "http://127.0.0.1:3001?token=synthetic",
            "http://127.0.0.1:3001/other",
            "http://127.0.0.1",
            "http://synthetic-device.synthetic-tailnet.ts.net",
            "https://localhost",
            "https://192.168.1.20",
            "https://100.64.0.2",
            "https://example.com",
            "https://synthetic-device.synthetic-tailnet.ts.net:8443",
            "https://user@synthetic-device.synthetic-tailnet.ts.net",
            "https://user:password@synthetic-device.synthetic-tailnet.ts.net",
            "https://synthetic-device.synthetic-tailnet.ts.net?token=synthetic",
            "https://synthetic-device.synthetic-tailnet.ts.net#fragment",
            "https://synthetic-device.synthetic-tailnet.ts.net/preconfigured",
            "https://synthetic-device.synthetic-tailnet.ts.net.",
            "https://synthetic-device..ts.net",
            "https://-synthetic.ts.net",
            "https://synthetic-.ts.net",
            "https://synthetic_name.ts.net",
            "https://xn--synthetic.ts.net",
            "https://ts.net",
            "https://synthetic.ts.net.example.com",
            "https://synthetic.tѕ.net",
            " https://synthetic-device.synthetic-tailnet.ts.net",
            "https://synthetic-device.synthetic-tailnet.ts.net\n",
        ] {
            XCTAssertThrowsError(try CoreIngestionEndpoint(origin: rejected))
        }
    }

    func testHTTPClientUsesAuthorizationHeaderAndKeepsTokenOutOfURLAndBody() async throws {
        let body = try envelopeData()
        let response = Data(
            #"{"entityType":"reminder","kind":"applied","sourceRevision":1}"#.utf8
        )
        let credentials = MemoryCredentialStore(token: syntheticToken)
        let transport = CapturingHTTPTransport(body: response)
        let client = AppleSourceDeliveryClient(
            credentialStore: credentials,
            transport: transport
        )

        let result = try await client.deliver(
            envelopeData: body,
            endpoint: try CoreIngestionEndpoint(origin: "http://127.0.0.1:3001")
        )

        XCTAssertEqual(result.kind, .applied)
        XCTAssertEqual(credentials.readCount, 1)
        XCTAssertEqual(transport.requests.count, 1)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertTrue(
            request.authorizationHeader == "Bearer \(syntheticToken)",
            "Authorization did not use the stored synthetic credential."
        )
        XCTAssertNil(URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.query)
        XCTAssertFalse(request.url.absoluteString.contains(syntheticToken))
        XCTAssertFalse(String(decoding: request.body, as: UTF8.self).contains(syntheticToken))
        XCTAssertEqual(request.timeout, 15)
    }

    func testKeychainCredentialAdapterUsesInjectedBackendWithoutSharingOrPackages() throws {
        let backend = MemoryKeychainBackend()
        let store = KeychainBridgeCredentialStore(
            service: "synthetic-service",
            account: "synthetic-account",
            backend: backend
        )

        XCTAssertNil(try store.readToken())
        try store.storeToken(syntheticToken)
        XCTAssertTrue(
            try store.readToken() == syntheticToken,
            "The injected Keychain adapter did not return the stored credential."
        )
        XCTAssertEqual(backend.writes.count, 1)
        XCTAssertEqual(backend.reads.count, 2)
        XCTAssertThrowsError(try store.storeToken("invalid"))
    }

    func testStatusClientReusesCredentialAndPostsExactBytesToStatusRoute() async throws {
        let body = try statusEnvelopeData()
        let response = Data(
            #"{"kind":"applied","statusRevision":1}"#.utf8
        )
        let credentials = MemoryCredentialStore(token: syntheticToken)
        let transport = CapturingHTTPTransport(body: response)
        let client = AppleBridgeStatusDeliveryClient(
            credentialStore: credentials,
            transport: transport
        )

        let result = try await client.deliverStatus(
            envelopeData: body,
            endpoint: try CoreIngestionEndpoint(origin: "http://127.0.0.1:3001")
        )

        XCTAssertEqual(result.kind, .applied)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url.absoluteString, "http://127.0.0.1:3001/v1/apple-bridge-status")
        XCTAssertEqual(request.body, body)
        XCTAssertEqual(request.authorizationHeader, "Bearer \(syntheticToken)")
        XCTAssertFalse(String(decoding: request.body, as: UTF8.self).contains(syntheticToken))
    }

    func testStatusClientRejectsMalformedMismatchedAndUnexpectedResponses() async throws {
        let body = try statusEnvelopeData()
        let endpoint = try CoreIngestionEndpoint(origin: "http://127.0.0.1:3001")
        let cases: [(Int, Data)] = [
            (200, Data("not-json".utf8)),
            (200, Data(#"{"kind":"applied","statusRevision":2}"#.utf8)),
            (201, Data(#"{"kind":"applied","statusRevision":1}"#.utf8)),
            (302, Data(#"{"kind":"applied","statusRevision":1}"#.utf8)),
            (200, Data(#"{"kind":"applied","statusRevision":1,"extra":true}"#.utf8)),
        ]

        for (status, response) in cases {
            let client = AppleBridgeStatusDeliveryClient(
                credentialStore: MemoryCredentialStore(token: syntheticToken),
                transport: CapturingHTTPTransport(statusCode: status, body: response)
            )
            do {
                _ = try await client.deliverStatus(
                    envelopeData: body,
                    endpoint: endpoint
                )
                XCTFail("Expected strict status response rejection")
            } catch let error as BridgeDeliveryError {
                XCTAssertEqual(error, .invalidResponse)
            }
        }
    }

    func testStrictResponseParsingRejectsMalformedNonJSONAndUnexpectedStatus() async throws {
        let body = try envelopeData()
        let credentials = MemoryCredentialStore(token: syntheticToken)
        let endpoint = try CoreIngestionEndpoint(origin: "http://127.0.0.1:3001")
        let cases: [(Int, Data)] = [
            (200, Data("not-json".utf8)),
            (200, Data(#"{"kind":"applied","sourceRevision":1}"#.utf8)),
            (
                201,
                Data(
                    #"{"entityType":"reminder","kind":"applied","sourceRevision":1}"#.utf8
                )
            ),
            (
                302,
                Data(
                    #"{"entityType":"reminder","kind":"applied","sourceRevision":1}"#.utf8
                )
            ),
            (
                200,
                Data(
                    #"{"entityType":"reminder","kind":"applied","sourceRevision":2}"#.utf8
                )
            ),
            (
                200,
                Data(
                    #"{"entityType":"reminder","kind":"applied","sourceRevision":1,"unexpected":true}"#.utf8
                )
            ),
        ]

        for (status, response) in cases {
            let transport = CapturingHTTPTransport(statusCode: status, body: response)
            let client = AppleSourceDeliveryClient(
                credentialStore: credentials,
                transport: transport
            )
            do {
                _ = try await client.deliver(envelopeData: body, endpoint: endpoint)
                XCTFail("Expected content-free response rejection")
            } catch let error as BridgeDeliveryError {
                XCTAssertEqual(error.localizedDescription, BridgeDeliveryError.invalidResponse.localizedDescription)
                XCTAssertFalse(error.localizedDescription.contains(syntheticToken))
            }
        }
    }

    func testTransportFailureAndTimeoutRemainContentFree() async throws {
        struct SyntheticTimeout: Error {}
        let transport = CapturingHTTPTransport(body: Data())
        transport.error = SyntheticTimeout()
        let client = AppleSourceDeliveryClient(
            credentialStore: MemoryCredentialStore(token: syntheticToken),
            transport: transport
        )

        do {
            _ = try await client.deliver(
                envelopeData: envelopeData(),
                endpoint: try CoreIngestionEndpoint(origin: "http://127.0.0.1:3001")
            )
            XCTFail("Expected uncertain transport failure")
        } catch let error as BridgeDeliveryError {
            XCTAssertEqual(error, .transportFailed)
            XCTAssertFalse(error.localizedDescription.contains(syntheticToken))
        }
    }

    func testSourceAndResponseLimitsRemainCoherentWithCoreBodyLimit() {
        XCTAssertLessThan(
            BridgeProductionLimits.maximumEncodedEnvelopeBytes,
            BridgeProductionLimits.coreRequestBodyBytes
        )
        XCTAssertEqual(
            BridgeProductionLimits.coreRequestBodyBytes,
            BridgeProductionLimits.proxySourceRequestBodyBytes
        )
        XCTAssertEqual(BridgeProductionLimits.maximumRetainedRecordsPerSource, 1_000)
        XCTAssertEqual(BridgeProductionLimits.maximumResponseBytes, 4 * 1024)
    }

    private func envelopeData() throws -> Data {
        let snapshot = try AppleSourceConverter.reminderSnapshot(
            from: ReminderSourceRead(
                sourceContainerId: "synthetic-source",
                allowsContentModifications: true,
                records: []
            ),
            bridgeId: "synthetic-bridge",
            capturedAt: ISO8601DateFormatter().date(from: "2026-08-23T18:00:00Z")!
        )
        return try AppleSourceEnvelopeCodec.encodeWithinProductionLimit(
            sourceRevision: 1,
            snapshot: snapshot
        )
    }

    private func statusEnvelopeData() throws -> Data {
        try AppleBridgeStatusEnvelopeCodec.encode(
            AppleBridgeStatusSnapshotV1(
                schemaVersion: 1,
                bridgeId: "synthetic-bridge",
                statusRevision: 1,
                capturedAt: "2026-08-23T18:00:00.000Z",
                permissions: AppleBridgeStatusPermissionsV1(
                    calendar: .granted,
                    reminders: .granted
                ),
                selectedSources: []
            )
        )
    }
}
