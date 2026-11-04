import Foundation
import XCTest
@testable import SchoolTrackerCore

final class SchoolTrackerCoreTests: XCTestCase {

    // MARK: - 1. URL Validation & Redaction Tests

    func testValidRenWebLinkParsesAndRedactsSessionID() throws {
        let link = try RenWebLinkParser.parse(AnonymizedReportFixtures.validReportURL)
        XCTAssertEqual(link.district, AnonymizedReportFixtures.validDistrict)
        XCTAssertEqual(link.sessionID, AnonymizedReportFixtures.validSessionID)
        XCTAssertEqual(link.url.scheme?.lowercased(), "https")

        // Redaction contract: string descriptions must mask SessionID and never emit the raw token.
        let redacted = link.redactedDescription
        XCTAssertFalse(redacted.contains(AnonymizedReportFixtures.validSessionID))
        XCTAssertTrue(redacted.contains("REDACTED"))
        XCTAssertFalse(String(describing: link).contains(AnonymizedReportFixtures.validSessionID))
    }

    func testMalformedAndHostSpoofedURLsAreRejected() {
        let invalidInputs: [String] = [
            "",
            "   \n\t  ",
            // Downgraded HTTP scheme
            "http://test-xx.client.factsmgt.com/renweb/email/GetReport.cfm?District=TEST-XX&SessionID=00000000-0000-0000-0000-000000000000",
            // Spoofed or untrusted hosts
            "https://evil.example.com/renweb/email/GetReport.cfm?District=TEST-XX&SessionID=00000000-0000-0000-0000-000000000000",
            "https://factsmgt.com.evil.example.com/renweb/email/GetReport.cfm?District=TEST-XX&SessionID=00000000-0000-0000-0000-000000000000",
            // Missing or empty District / SessionID
            "https://test-xx.client.factsmgt.com/renweb/email/GetReport.cfm?District=TEST-XX",
            "https://test-xx.client.factsmgt.com/renweb/email/GetReport.cfm?SessionID=00000000-0000-0000-0000-000000000000",
            "https://test-xx.client.factsmgt.com/renweb/email/GetReport.cfm?District=&SessionID=00000000-0000-0000-0000-000000000000",
            "https://test-xx.client.factsmgt.com/renweb/email/GetReport.cfm?District=TEST-XX&SessionID=",
            // Wrong endpoint path
            "https://test-xx.client.factsmgt.com/renweb/login.cfm?District=TEST-XX&SessionID=00000000-0000-0000-0000-000000000000"
        ]

        for candidate in invalidInputs {
            XCTAssertThrowsError(try RenWebLinkParser.parse(candidate), "Expected invalidURL for input: \(candidate)") { error in
                XCTAssertEqual(error as? RenWebError, .invalidURL)
            }
        }
    }

    func testOversizedURLBoundaryIsRejected() {
        let hugePadding = String(repeating: "A", count: 65_536)
        let oversizedURL = AnonymizedReportFixtures.validReportURL + "&extra=" + hugePadding
        XCTAssertThrowsError(try RenWebLinkParser.parse(oversizedURL)) { error in
            XCTAssertEqual(error as? RenWebError, .invalidURL)
        }
    }

    // MARK: - 2. HTML Report Parsing & Session Expiry Tests

    func testValidMultiCourseReportParsing() throws {
        let report = try RenWebReportParser.parse(html: AnonymizedReportFixtures.validMultiCourseReportHTML)
        XCTAssertEqual(report.courses.count, 2)

        let calc = report.courses[0]
        XCTAssertEqual(calc.courseName, "AP Calculus BC")
        XCTAssertEqual(calc.numericAverage ?? 0, 94.5, accuracy: 0.01)
        XCTAssertEqual(calc.letterGrade, "A")
        XCTAssertEqual(calc.assignments.count, 2)
        XCTAssertEqual(calc.assignments[0].title, "Series Convergence Set 1")

        let chem = report.courses[1]
        XCTAssertEqual(chem.courseName, "Honors Chemistry")
        XCTAssertEqual(chem.numericAverage ?? 0, 88.0, accuracy: 0.01)
        XCTAssertEqual(chem.letterGrade, "B+")
        XCTAssertEqual(chem.assignments.count, 1)
    }

    func testExpiredSessionHTMLThrowsExpiredOrInvalidSession() {
        XCTAssertThrowsError(try RenWebReportParser.parse(html: AnonymizedReportFixtures.expiredSessionHTML)) { error in
            XCTAssertEqual(error as? RenWebError, .expiredOrInvalidSession)
        }
    }

    func testEmptyAndMalformedHTMLThrowsParseFailure() {
        let malformedInputs = [
            "",
            "   \n\t  ",
            "<html><body><div>No courses or tables present</div></body></html>",
            "<html><body><table><tr><td>Truncated"
        ]

        for html in malformedInputs {
            XCTAssertThrowsError(try RenWebReportParser.parse(html: html)) { error in
                guard case .parseFailure(let reason) = error as? RenWebError else {
                    XCTFail("Expected .parseFailure, got \(error)")
                    return
                }
                XCTAssertFalse(reason.isEmpty)
            }
        }
    }

    // MARK: - 3. Boundary Inputs (Extra Credit, Zeroes, Pending Rows, Large Payloads, Concurrency)

    func testBoundaryGradesAndHTMLEntitiesParsing() throws {
        let report = try RenWebReportParser.parse(html: AnonymizedReportFixtures.boundaryGradesReportHTML)
        XCTAssertEqual(report.courses.count, 1)

        let physics = report.courses[0]
        XCTAssertTrue(physics.courseName.contains("Physics"))
        XCTAssertEqual(physics.numericAverage ?? 0, 102.5, accuracy: 0.01)
        XCTAssertEqual(physics.letterGrade, "A+")
        XCTAssertEqual(physics.assignments.count, 3)
    }

    func testLargeReportPayloadScalesLinearly() throws {
        let largeHTML = AnonymizedReportFixtures.makeLargeReportHTML(courseCount: 25, assignmentsPerCourse: 40)
        let report = try RenWebReportParser.parse(html: largeHTML)
        XCTAssertEqual(report.courses.count, 25)
        XCTAssertEqual(report.courses.first?.assignments.count, 40)
    }

    func testConcurrentLinkValidationAndReportParsing() async throws {
        try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    let link = try RenWebLinkParser.parse(AnonymizedReportFixtures.validReportURL)
                    XCTAssertEqual(link.district, "TEST-XX")
                    let report = try RenWebReportParser.parse(html: AnonymizedReportFixtures.validMultiCourseReportHTML)
                    return report.courses.count
                }
            }
            for try await courseCount in group {
                XCTAssertEqual(courseCount, 2)
            }
        }
    }

    // MARK: - 4. Client & Mock Fetcher Boundary Tests

    private struct StubRenWebFetcher: RenWebFetching {
        let result: Result<String, RenWebError>

        func fetchReportHTML(from link: ValidatedRenWebLink) async throws -> String {
            try result.get()
        }
    }

    func testClientWithMockFetcherSuccessAndErrors() async throws {
        let okClient = RenWebClient(
            fetcher: StubRenWebFetcher(result: .success(AnonymizedReportFixtures.validMultiCourseReportHTML))
        )
        let report = try await okClient.importReport(from: AnonymizedReportFixtures.validReportURL)
        XCTAssertEqual(report.courses.count, 2)

        let expiredClient = RenWebClient(
            fetcher: StubRenWebFetcher(result: .success(AnonymizedReportFixtures.expiredSessionHTML))
        )
        do {
            _ = try await expiredClient.importReport(from: AnonymizedReportFixtures.validReportURL)
            XCTFail("Expected expiredOrInvalidSession")
        } catch let error as RenWebError {
            XCTAssertEqual(error, .expiredOrInvalidSession)
        }

        let failingClient = RenWebClient(
            fetcher: StubRenWebFetcher(result: .failure(.networkFailure(statusCode: 503)))
        )
        do {
            _ = try await failingClient.importReport(from: AnonymizedReportFixtures.validReportURL)
            XCTFail("Expected networkFailure(503)")
        } catch let error as RenWebError {
            XCTAssertEqual(error, .networkFailure(statusCode: 503))
        }
    }

    // MARK: - 5. Working Tree Secret & PII Audit

    func testRepositoryWorkingTreeContainsNoLiveTokens() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let repoRootURL = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let enumerator = FileManager.default.enumerator(
            at: repoRootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        // Match any non-placeholder District=<CODE> or hex SessionID prefix in tracked files.
        let districtPattern = try NSRegularExpression(pattern: #"District=([A-Za-z0-9\-]+)"#, options: [.caseInsensitive])
        let sessionPattern = try NSRegularExpression(pattern: #"SessionID=([A-Fa-f0-9\-]{8,})"#, options: [.caseInsensitive])
        var violations = [String]()

        while let fileURL = enumerator?.nextObject() as? URL {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let range = NSRange(content.startIndex..<content.endIndex, in: content)

            for match in districtPattern.matches(in: content, range: range) {
                if let valueRange = Range(match.range(at: 1), in: content) {
                    let district = String(content[valueRange])
                    if district != AnonymizedReportFixtures.validDistrict {
                        violations.append("\(fileURL.lastPathComponent) contains non-anonymized District '\(district)'")
                    }
                }
            }

            for match in sessionPattern.matches(in: content, range: range) {
                if let valueRange = Range(match.range(at: 1), in: content) {
                    let session = String(content[valueRange])
                    if session != AnonymizedReportFixtures.validSessionID {
                        violations.append("\(fileURL.lastPathComponent) contains non-anonymized SessionID")
                    }
                }
            }
        }

        XCTAssertTrue(violations.isEmpty, "Secret audit violations found: \(violations.joined(separator: "; "))")
    }
}
