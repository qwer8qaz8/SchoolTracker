import Foundation

// MARK: - Network Boundary Protocol & Client

public protocol RenWebFetching: Sendable {
    func fetchReportHTML(from link: ValidatedRenWebLink) async throws -> String
}

public struct URLSessionRenWebFetcher: RenWebFetching {
    public let timeoutSeconds: TimeInterval

    public init(timeoutSeconds: TimeInterval = 15.0) {
        self.timeoutSeconds = timeoutSeconds
    }

    public func fetchReportHTML(from link: ValidatedRenWebLink) async throws -> String {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeoutSeconds
        config.timeoutIntervalForResource = timeoutSeconds
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }

        var request = URLRequest(
            url: link.url,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: timeoutSeconds
        )
        request.httpShouldHandleCookies = false
        request.setValue(
            "SchoolTracker/1.0 (macOS; +https://github.com)",
            forHTTPHeaderField: "User-Agent"
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            SchoolTrackerTelemetry.shared.increment(
                .networkFetchFailure,
                context: "transport_error link=\(link.redactedDescription)"
            )
            throw RenWebError.networkFailure(statusCode: nil)
        }

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode)
        {
            SchoolTrackerTelemetry.shared.increment(
                .networkFetchFailure,
                context: "http_status=\(httpResponse.statusCode) link=\(link.redactedDescription)"
            )
            throw RenWebError.networkFailure(statusCode: httpResponse.statusCode)
        }

        let html = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""

        SchoolTrackerTelemetry.shared.increment(
            .networkFetchSuccess,
            context: "bytes=\(data.count) link=\(link.redactedDescription)"
        )
        return html
    }
}

public struct RenWebClient: Sendable {
    private let fetcher: any RenWebFetching

    public init(fetcher: any RenWebFetching = URLSessionRenWebFetcher()) {
        self.fetcher = fetcher
    }

    public func importReport(from rawURLString: String) async throws -> ImportedGradeReport {
        let link = try RenWebLinkParser.parse(rawURLString)
        return try await importReport(from: link)
    }

    public func importReport(from link: ValidatedRenWebLink) async throws -> ImportedGradeReport {
        let html = try await fetcher.fetchReportHTML(from: link)
        return try RenWebReportParser.parse(html: html)
    }
}
