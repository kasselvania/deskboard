import Foundation

enum BridgeProductionLimits {
    static let calendarDaysBehind = 7
    static let calendarDaysAhead = 45
    static let maximumRetainedRecordsPerSource = 1_000
    static let maximumEncodedEnvelopeBytes = 768 * 1024
    static let maximumEncodedStatusEnvelopeBytes = 256 * 1024
    static let coreRequestBodyBytes = 1024 * 1024
    static let proxySourceRequestBodyBytes = 1024 * 1024
    static let maximumResponseBytes = 4 * 1024
    static let uploadTimeout: TimeInterval = 15
    static let maximumSafeSourceRevision = 9_007_199_254_740_991

    // The owner-invoked completeness diagnostic refuses to form a complete
    // candidate outside these finite input and encoding budgets.
    static let completenessDiagnosticMaximumRecords = 4_096
    static let completenessDiagnosticMaximumAdmittedUTF8Bytes = 512 * 1024
    static let completenessDiagnosticMaximumEncodingBytes = 8 * 1024 * 1024
}
