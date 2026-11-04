import Foundation
#if canImport(XCTest)
import XCTest
#endif
#if !STANDALONE_TEST_RUNNER
@testable import SchoolTrackerCore
#endif

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

    // MARK: - 2. HTML Report Parsing (Course-Section & ColdFusion Multi-Table) & Session Expiry Tests

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

    func testColdFusionMultiTableReportParsing() throws {
        let report = try RenWebReportParser.parse(html: AnonymizedReportFixtures.coldFusionMultiTableReportHTML)
        XCTAssertEqual(report.schoolYear, "2026-2027")
        XCTAssertEqual(report.term, "Q2")
        XCTAssertEqual(report.courses.count, 2)

        // Course 0: AP Calculus BC (with unclosed </td on row 3, Weight = categories, Category Average, and Term Grade)
        let calc = report.courses[0]
        XCTAssertEqual(calc.courseName, "AP Calculus BC")
        XCTAssertEqual(calc.courseCode, "MAT-401")
        XCTAssertEqual(calc.teacherName, "Instructor, Demo A")
        XCTAssertEqual(calc.term, "Q2")
        XCTAssertEqual(calc.numericAverage ?? 0, 94.0, accuracy: 0.01)
        XCTAssertEqual(calc.letterGrade, "A")
        XCTAssertEqual(calc.categories.count, 2)
        XCTAssertEqual(calc.categories[0].name, "Homework")
        XCTAssertEqual(calc.categories[0].weight ?? 0, 30.0, accuracy: 0.01)
        XCTAssertEqual(calc.categories[0].average ?? 0, 91.0, accuracy: 0.01)
        XCTAssertEqual(calc.categories[1].name, "Quizzes")
        XCTAssertEqual(calc.categories[1].weight ?? 0, 70.0, accuracy: 0.01)
        XCTAssertEqual(calc.categories[1].average ?? 0, 95.0, accuracy: 0.01)
        XCTAssertEqual(calc.assignments.count, 3)
        XCTAssertEqual(calc.assignments[0].title, "5.2 Day 1")
        XCTAssertEqual(calc.assignments[0].category, "Homework")
        XCTAssertTrue(calc.assignments[0].isCompleted)
        XCTAssertEqual(calc.assignments[1].title, "5.3 Practice")
        XCTAssertFalse(calc.assignments[1].isCompleted)
        XCTAssertEqual(calc.assignments[2].title, "Unit 5 Quiz")
        XCTAssertEqual(calc.assignments[2].category, "Quizzes")

        // Course 1: Honors Chemistry (Term Grade omitted; average inferred from Category Average + inferLetterGrade)
        let chem = report.courses[1]
        XCTAssertEqual(chem.courseName, "Honors Chemistry")
        XCTAssertEqual(chem.courseCode, "SCI-302")
        XCTAssertEqual(chem.numericAverage ?? 0, 88.0, accuracy: 0.01)
        XCTAssertEqual(chem.letterGrade, "B+")
        XCTAssertEqual(chem.assignments.count, 1)
        XCTAssertEqual(chem.assignments[0].title, "Titration Lab & Report")
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

    func testLetterGradeInferenceBoundaries() {
        XCTAssertEqual(RenWebReportParser.inferLetterGrade(for: 98.0), "A+")
        XCTAssertEqual(RenWebReportParser.inferLetterGrade(for: 94.0), "A")
        XCTAssertEqual(RenWebReportParser.inferLetterGrade(for: 91.0), "A-")
        XCTAssertEqual(RenWebReportParser.inferLetterGrade(for: 88.0), "B+")
        XCTAssertEqual(RenWebReportParser.inferLetterGrade(for: 85.0), "B")
        XCTAssertEqual(RenWebReportParser.inferLetterGrade(for: 81.0), "B-")
        XCTAssertEqual(RenWebReportParser.inferLetterGrade(for: 78.0), "C+")
        XCTAssertEqual(RenWebReportParser.inferLetterGrade(for: 75.0), "C")
        XCTAssertEqual(RenWebReportParser.inferLetterGrade(for: 71.0), "C-")
        XCTAssertEqual(RenWebReportParser.inferLetterGrade(for: 68.0), "D+")
        XCTAssertEqual(RenWebReportParser.inferLetterGrade(for: 65.0), "D")
        XCTAssertEqual(RenWebReportParser.inferLetterGrade(for: 61.0), "D-")
        XCTAssertEqual(RenWebReportParser.inferLetterGrade(for: 59.9), "F")
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

    // MARK: - 5. SchoolTrackerStore Round-Trip Persistence & Re-Import Merging Tests

    func testSchoolTrackerStoreRoundTripAndRedaction() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SchoolTrackerStoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let stateURL = tempDir.appendingPathComponent("state.json", isDirectory: false)
        let store = SchoolTrackerStore(stateFileURL: stateURL)

        // Initial load when file does not exist returns empty state
        let initial = try store.loadState()
        XCTAssertTrue(initial.courses.isEmpty)
        XCTAssertTrue(initial.tasks.isEmpty)

        // Apply report with validated link and verify on-disk redaction + round-trip
        let link = try RenWebLinkParser.parse(AnonymizedReportFixtures.validReportURL)
        let report = try RenWebReportParser.parse(html: AnonymizedReportFixtures.coldFusionMultiTableReportHTML)
        let syncDate = Date(timeIntervalSince1970: 1_762_300_000)

        try store.applyImportedReport(report, from: link, syncedAt: syncDate)
        let reloaded = try store.loadState()

        XCTAssertEqual(reloaded.courses.count, 2)
        XCTAssertEqual(reloaded.lastSyncedDistrict, "TEST-XX")
        XCTAssertEqual(reloaded.lastSyncedAt, syncDate)
        XCTAssertNotNil(reloaded.lastRedactedReportURL)
        XCTAssertFalse((reloaded.lastRedactedReportURL ?? "").contains(AnonymizedReportFixtures.validSessionID))
        XCTAssertTrue((reloaded.lastRedactedReportURL ?? "").contains("REDACTED"))

        // Corrupt JSON on disk throws PersistenceError.decodeFailed
        try Data("{corrupt-json".utf8).write(to: stateURL)
        XCTAssertThrowsError(try store.loadState()) { error in
            guard case .decodeFailed = error as? PersistenceError else {
                XCTFail("Expected PersistenceError.decodeFailed, got \(error)")
                return
            }
        }
    }

    func testSchoolTrackerStoreReimportPreservesCourseIDsAndAssignmentCompletion() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SchoolTrackerReimportTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let stateURL = tempDir.appendingPathComponent("state.json", isDirectory: false)
        let store = SchoolTrackerStore(stateFileURL: stateURL)

        let firstReport = try RenWebReportParser.parse(html: AnonymizedReportFixtures.coldFusionMultiTableReportHTML)
        var state = try store.applyImportedReport(firstReport)
        XCTAssertEqual(state.courses.count, 2)

        let originalCalcID = state.courses[0].id
        let originalChemID = state.courses[1].id

        // User toggles completion on two assignments and adds a tracked task
        state.courses[0].assignments[0].isCompleted = false // "5.2 Day 1" toggled to incomplete
        state.courses[0].assignments[1].isCompleted = true  // "5.3 Practice" toggled to complete
        state.tasks.append(TrackedTask(title: "Review Taylor Series", courseName: "AP Calculus BC"))
        try store.saveState(state)

        // Re-import the same courses from a fresh parse (which generates new random UUIDs and default isCompleted flags)
        let secondReport = try RenWebReportParser.parse(html: AnonymizedReportFixtures.coldFusionMultiTableReportHTML)
        let merged = try store.applyImportedReport(secondReport)

        XCTAssertEqual(merged.courses.count, 2)
        XCTAssertEqual(merged.courses[0].id, originalCalcID, "Re-import must preserve existing course UUID")
        XCTAssertEqual(merged.courses[1].id, originalChemID, "Re-import must preserve existing course UUID")
        XCTAssertFalse(
            merged.courses[0].assignments[0].isCompleted,
            "Re-import must preserve user-toggled isCompleted=false on '5.2 Day 1'"
        )
        XCTAssertTrue(
            merged.courses[0].assignments[1].isCompleted,
            "Re-import must preserve user-toggled isCompleted=true on '5.3 Practice'"
        )
        XCTAssertEqual(merged.tasks.count, 1)
    }

    func testSavedRenWebLinkExpirationStatuses() {
        let savedAt = Date(timeIntervalSince1970: 1_762_000_000)
        let expiresAt = savedAt.addingTimeInterval(SavedRenWebLink.defaultTTL)
        var savedLink = SavedRenWebLink(
            district: AnonymizedReportFixtures.validDistrict,
            redactedURL: "https://test-xx.client.factsmgt.com/renweb/email/GetReport.cfm?District=TEST-XX&SessionID=REDACTED",
            savedAt: savedAt,
            expiresAt: expiresAt,
            lastVerifiedAt: savedAt,
            isConfirmedExpired: false
        )

        // 1. Active state (> 48 hours remaining: 10 days left)
        let tenDaysLeftDate = savedAt.addingTimeInterval(4 * 86_400)
        let activeStatus = savedLink.expirationStatus(referenceDate: tenDaysLeftDate)
        if case let .active(daysRemaining, _, statusExpiresAt) = activeStatus {
            XCTAssertEqual(daysRemaining, 10)
            XCTAssertEqual(statusExpiresAt, expiresAt)
        } else {
            XCTFail("Expected .active status, got \(activeStatus)")
        }
        XCTAssertFalse(savedLink.expirationSummaryText(referenceDate: tenDaysLeftDate).isEmpty)

        // 2. Expiring soon state (<= 48 hours remaining: 36 hours left)
        let thirtySixHoursLeftDate = expiresAt.addingTimeInterval(-36 * 3_600)
        let soonStatus = savedLink.expirationStatus(referenceDate: thirtySixHoursLeftDate)
        if case let .expiringSoon(hoursRemaining, statusExpiresAt) = soonStatus {
            XCTAssertEqual(hoursRemaining, 36)
            XCTAssertEqual(statusExpiresAt, expiresAt)
        } else {
            XCTFail("Expected .expiringSoon status, got \(soonStatus)")
        }
        XCTAssertFalse(savedLink.expirationSummaryText(referenceDate: thirtySixHoursLeftDate).isEmpty)

        // 3. Expired by clock (referenceDate >= expiresAt)
        let pastExpiryDate = expiresAt.addingTimeInterval(3_600)
        let clockExpiredStatus = savedLink.expirationStatus(referenceDate: pastExpiryDate)
        XCTAssertEqual(clockExpiredStatus, .expired(expiresAt: expiresAt, confirmedByServer: false))
        XCTAssertFalse(savedLink.expirationSummaryText(referenceDate: pastExpiryDate).isEmpty)

        // 4. Expired confirmed by server (.expiredOrInvalidSession before clock expiry)
        savedLink.isConfirmedExpired = true
        let serverExpiredStatus = savedLink.expirationStatus(referenceDate: tenDaysLeftDate)
        XCTAssertEqual(serverExpiredStatus, .expired(expiresAt: expiresAt, confirmedByServer: true))
    }

    func testSavedLinkCredentialStoreRoundTripPermissionsAndClear() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SchoolTrackerSavedLinkTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let stateURL = tempDir.appendingPathComponent("state.json", isDirectory: false)
        let store = SchoolTrackerStore(stateFileURL: stateURL)

        XCTAssertNil(try store.loadSavedRenWebLink())

        let link = try RenWebLinkParser.parse(AnonymizedReportFixtures.validReportURL)
        let savedAt = Date(timeIntervalSince1970: 1_762_000_000)
        let expiresAt = savedAt.addingTimeInterval(SavedRenWebLink.defaultTTL)

        let savedMetadata = try store.saveRenWebLink(link, savedAt: savedAt, expiresAt: expiresAt)
        XCTAssertEqual(savedMetadata.district, AnonymizedReportFixtures.validDistrict)
        XCTAssertEqual(savedMetadata.savedAt, savedAt)
        XCTAssertEqual(savedMetadata.expiresAt, expiresAt)
        XCTAssertFalse(savedMetadata.redactedURL.contains(AnonymizedReportFixtures.validSessionID))
        XCTAssertTrue(savedMetadata.redactedURL.contains("REDACTED"))

        // Verify credential file exists with 0600 owner-only permissions and round-trips the ValidatedRenWebLink
        let credentialPath = store.savedLinkCredentialFileURL.path
        XCTAssertTrue(FileManager.default.fileExists(atPath: credentialPath))
        let attrs = try FileManager.default.attributesOfItem(atPath: credentialPath)
        if let perms = attrs[.posixPermissions] as? NSNumber {
            XCTAssertEqual(perms.intValue & 0o777, 0o600)
        }

        let loadedLink = try store.loadSavedRenWebLink()
        XCTAssertEqual(loadedLink, link)

        // Verify state.json never contains the raw SessionID
        let rawStateJSON = try String(contentsOf: stateURL, encoding: .utf8)
        XCTAssertFalse(rawStateJSON.contains(AnonymizedReportFixtures.validSessionID))
        XCTAssertTrue(rawStateJSON.contains("REDACTED"))

        // Re-syncing the same session via applyImportedReport preserves original savedAt and expiresAt
        let report = try RenWebReportParser.parse(html: AnonymizedReportFixtures.coldFusionMultiTableReportHTML)
        let resyncDate = savedAt.addingTimeInterval(7_200)
        let stateAfterResync = try store.applyImportedReport(report, from: link, syncedAt: resyncDate)
        XCTAssertEqual(stateAfterResync.savedLink?.savedAt, savedAt)
        XCTAssertEqual(stateAfterResync.savedLink?.expiresAt, expiresAt)
        XCTAssertEqual(stateAfterResync.savedLink?.lastVerifiedAt, resyncDate)

        // Marking the saved link expired flips isConfirmedExpired = true
        let expiredAt = resyncDate.addingTimeInterval(600)
        let expiredMeta = try store.markSavedLinkExpired(at: expiredAt)
        XCTAssertEqual(expiredMeta?.isConfirmedExpired, true)
        XCTAssertEqual(
            expiredMeta?.expirationStatus(referenceDate: expiredAt),
            .expired(expiresAt: expiresAt, confirmedByServer: true)
        )

        // Clearing the saved link removes saved-link.json and clears state.savedLink
        try store.clearSavedRenWebLink()
        XCTAssertNil(try store.loadSavedRenWebLink())
        XCTAssertFalse(FileManager.default.fileExists(atPath: credentialPath))
        XCTAssertNil(try store.loadState().savedLink)
    }

    // MARK: - 6. Working Tree Secret & PII Audit

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

#if STANDALONE_TEST_RUNNER && !canImport(XCTest)
@main
struct StandaloneTestRunner {
    static func main() async {
        let suite = SchoolTrackerCoreTests()
        let syncTests: [(String, () throws -> Void)] = [
            ("testValidRenWebLinkParsesAndRedactsSessionID", suite.testValidRenWebLinkParsesAndRedactsSessionID),
            ("testMalformedAndHostSpoofedURLsAreRejected", suite.testMalformedAndHostSpoofedURLsAreRejected),
            ("testOversizedURLBoundaryIsRejected", suite.testOversizedURLBoundaryIsRejected),
            ("testValidMultiCourseReportParsing", suite.testValidMultiCourseReportParsing),
            ("testColdFusionMultiTableReportParsing", suite.testColdFusionMultiTableReportParsing),
            ("testExpiredSessionHTMLThrowsExpiredOrInvalidSession", suite.testExpiredSessionHTMLThrowsExpiredOrInvalidSession),
            ("testEmptyAndMalformedHTMLThrowsParseFailure", suite.testEmptyAndMalformedHTMLThrowsParseFailure),
            ("testBoundaryGradesAndHTMLEntitiesParsing", suite.testBoundaryGradesAndHTMLEntitiesParsing),
            ("testLetterGradeInferenceBoundaries", suite.testLetterGradeInferenceBoundaries),
            ("testLargeReportPayloadScalesLinearly", suite.testLargeReportPayloadScalesLinearly),
            ("testSchoolTrackerStoreRoundTripAndRedaction", suite.testSchoolTrackerStoreRoundTripAndRedaction),
            ("testSchoolTrackerStoreReimportPreservesCourseIDsAndAssignmentCompletion", suite.testSchoolTrackerStoreReimportPreservesCourseIDsAndAssignmentCompletion),
            ("testSavedRenWebLinkExpirationStatuses", suite.testSavedRenWebLinkExpirationStatuses),
            ("testSavedLinkCredentialStoreRoundTripPermissionsAndClear", suite.testSavedLinkCredentialStoreRoundTripPermissionsAndClear),
            ("testRepositoryWorkingTreeContainsNoLiveTokens", suite.testRepositoryWorkingTreeContainsNoLiveTokens)
        ]
        let asyncTests: [(String, () async throws -> Void)] = [
            ("testConcurrentLinkValidationAndReportParsing", suite.testConcurrentLinkValidationAndReportParsing),
            ("testClientWithMockFetcherSuccessAndErrors", suite.testClientWithMockFetcherSuccessAndErrors)
        ]

        var passed = 0
        var failed = 0

        for (name, body) in syncTests {
            XCTestFailureTracker.failures.removeAll()
            do {
                try body()
            } catch {
                XCTFail("Unhandled error thrown: \(error)")
            }
            if XCTestFailureTracker.failures.isEmpty {
                print("[PASS] \(name)")
                passed += 1
            } else {
                print("[FAIL] \(name)")
                for failure in XCTestFailureTracker.failures {
                    print("       \(failure)")
                }
                failed += 1
            }
        }

        for (name, body) in asyncTests {
            XCTestFailureTracker.failures.removeAll()
            do {
                try await body()
            } catch {
                XCTFail("Unhandled error thrown: \(error)")
            }
            if XCTestFailureTracker.failures.isEmpty {
                print("[PASS] \(name)")
                passed += 1
            } else {
                print("[FAIL] \(name)")
                for failure in XCTestFailureTracker.failures {
                    print("       \(failure)")
                }
                failed += 1
            }
        }

        print("\nTest Summary: \(passed) passed, \(failed) failed (\(passed + failed) total)")
        if failed > 0 {
            Foundation.exit(1)
        }
    }
}
#endif
