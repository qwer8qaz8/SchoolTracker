import Foundation

// MARK: - RenWeb Temporary Link Validator

public enum RenWebLinkParser {
    /// Maximum accepted URL byte length (64 KB boundary guard; rejects oversized inputs).
    public static let maxURLBytes = 4_096

    private static let allowedBaseDomains = [
        "factsmgt.com",
        "renweb.com"
    ]

    private static let expectedPath = "/renweb/email/getreport.cfm"

    public static func parse(_ rawInput: String) throws -> ValidatedRenWebLink {
        if rawInput.utf8.count > maxURLBytes {
            SchoolTrackerTelemetry.shared.increment(
                .linkValidationFailure,
                context: "oversized_url_bytes=\(rawInput.utf8.count)"
            )
            throw RenWebError.invalidURL
        }

        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let components = URLComponents(string: trimmed),
              let url = components.url
        else {
            SchoolTrackerTelemetry.shared.increment(.linkValidationFailure, context: "malformed_url_components")
            throw RenWebError.invalidURL
        }

        guard components.scheme?.lowercased() == "https" else {
            SchoolTrackerTelemetry.shared.increment(.linkValidationFailure, context: "non_https_scheme")
            throw RenWebError.invalidURL
        }

        guard let host = components.host?.lowercased(), !host.isEmpty, isAllowedHost(host) else {
            SchoolTrackerTelemetry.shared.increment(.linkValidationFailure, context: "untrusted_host")
            throw RenWebError.invalidURL
        }

        guard components.path.lowercased() == expectedPath else {
            SchoolTrackerTelemetry.shared.increment(.linkValidationFailure, context: "unexpected_path=\(components.path)")
            throw RenWebError.invalidURL
        }

        guard let queryItems = components.queryItems, !queryItems.isEmpty else {
            SchoolTrackerTelemetry.shared.increment(.linkValidationFailure, context: "missing_query_items")
            throw RenWebError.invalidURL
        }

        let district = queryItems
            .first { $0.name.caseInsensitiveCompare("District") == .orderedSame }?
            .value?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let sessionID = queryItems
            .first { $0.name.caseInsensitiveCompare("SessionID") == .orderedSame }?
            .value?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !district.isEmpty, !sessionID.isEmpty else {
            SchoolTrackerTelemetry.shared.increment(.linkValidationFailure, context: "missing_district_or_session_id")
            throw RenWebError.invalidURL
        }

        let validated = ValidatedRenWebLink(url: url, district: district, sessionID: sessionID)
        SchoolTrackerTelemetry.shared.increment(.linkValidationSuccess, context: validated.redactedDescription)
        return validated
    }

    private static func isAllowedHost(_ host: String) -> Bool {
        for domain in allowedBaseDomains {
            if host == domain || host.hasSuffix("." + domain) {
                return true
            }
        }
        return false
    }
}
