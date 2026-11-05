import Foundation
import os

// MARK: - Telemetry & Redacted Logging

public enum TelemetryMetric: String, CaseIterable, Sendable {
    case linkValidationSuccess = "renweb.link.validation.success"
    case linkValidationFailure = "renweb.link.validation.failure"
    case networkFetchSuccess = "renweb.network.fetch.success"
    case networkFetchFailure = "renweb.network.fetch.failure"
    case reportParseSuccess = "renweb.report.parse.success"
    case reportParseExpiredSession = "renweb.report.parse.expired_session"
    case reportParseFailure = "renweb.report.parse.failure"
    case stateLoadSuccess = "persistence.state.load.success"
    case stateLoadFailure = "persistence.state.load.failure"
    case stateSaveSuccess = "persistence.state.save.success"
    case stateSaveFailure = "persistence.state.save.failure"
    case savedLinkSaveSuccess = "persistence.saved_link.save.success"
    case savedLinkSaveFailure = "persistence.saved_link.save.failure"
    case savedLinkLoadSuccess = "persistence.saved_link.load.success"
    case savedLinkLoadFailure = "persistence.saved_link.load.failure"
    case savedLinkMarkedExpired = "persistence.saved_link.marked_expired"
    case savedLinkCleared = "persistence.saved_link.cleared"
    case calendarSubscriptionUpdateSuccess = "calendar.subscription.update.success"
    case calendarSubscriptionUpdateFailure = "calendar.subscription.update.failure"
    case calendarFeedParseSuccess = "calendar.feed.parse.success"
    case calendarFeedParseFailure = "calendar.feed.parse.failure"
}

public final class SchoolTrackerTelemetry: @unchecked Sendable {
    public static let shared = SchoolTrackerTelemetry()

    private let lock = NSLock()
    private var counters: [TelemetryMetric: Int] = [:]
    private let logger = Logger(subsystem: "com.schooltracker.core", category: "ServiceBoundary")

    public init() {}

    public func increment(_ metric: TelemetryMetric, context: String? = nil) {
        lock.lock()
        counters[metric, default: 0] += 1
        let currentCount = counters[metric, default: 0]
        lock.unlock()

        let sanitizedContext = Self.redactSensitiveTokens(in: context ?? "")
        if metric.rawValue.hasSuffix(".failure") || metric == .reportParseExpiredSession {
            logger.error("[\(metric.rawValue, privacy: .public)] count=\(currentCount, privacy: .public) detail=\(sanitizedContext, privacy: .public)")
        } else {
            logger.info("[\(metric.rawValue, privacy: .public)] count=\(currentCount, privacy: .public) detail=\(sanitizedContext, privacy: .public)")
        }
    }

    public func count(for metric: TelemetryMetric) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return counters[metric, default: 0]
    }

    public func snapshot() -> [TelemetryMetric: Int] {
        lock.lock()
        defer { lock.unlock() }
        return counters
    }

    public func reset() {
        lock.lock()
        counters.removeAll()
        lock.unlock()
    }

    /// Scrubs any SessionID=<token> or calendar feed secret query parameter before emitting log messages or saving state.
    public static func redactSensitiveTokens(in text: String) -> String {
        guard !text.isEmpty else { return text }
        guard let regex = try? NSRegularExpression(
            pattern: #"((?:SessionID|token|key|auth|secret|sig)=)[^&\s\"']+"#,
            options: [.caseInsensitive]
        ) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "$1REDACTED")
    }
}
