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

    // MARK: - 6. Family Portal Calendar Subscriptions, .ics Parser & Category Space Isolation Tests

    func testFamilyPortalCalendarLinkParserNormalizesWebcalAndRedactsTokens() throws {
        let parsed = try FamilyPortalCalendarLinkParser.parse(
            AnonymizedReportFixtures.validWebcalFeedURL,
            for: .school
        )
        XCTAssertEqual(parsed.category, .school)
        XCTAssertEqual(parsed.url.scheme?.lowercased(), "https")
        XCTAssertFalse(parsed.redactedDescription.contains(AnonymizedReportFixtures.validSessionID))
        XCTAssertTrue(parsed.redactedDescription.contains("REDACTED"))

        let invalidFeeds = [
            "",
            "   ",
            "http://test-xx.client.factsmgt.com/renweb/calendar/feed.ics",
            "ftp://test-xx.client.factsmgt.com/renweb/calendar/feed.ics"
        ]
        for candidate in invalidFeeds {
            XCTAssertThrowsError(try FamilyPortalCalendarLinkParser.parse(candidate, for: .school)) { error in
                XCTAssertEqual(error as? FamilyPortalCalendarError, .invalidFeedURL)
            }
        }
    }

    func testFamilyPortalICalendarParserExtractsEventsPerCategory() throws {
        let schoolEvents = try FamilyPortalICalendarParser.parse(
            ics: AnonymizedReportFixtures.schoolCalendarICS,
            category: .school
        )
        XCTAssertEqual(schoolEvents.count, 2)
        XCTAssertEqual(schoolEvents[0].category, .school)
        XCTAssertTrue(schoolEvents[0].isAllDay)
        XCTAssertEqual(schoolEvents[0].title, "Thanksgiving Break - Campus Closed")
        XCTAssertEqual(schoolEvents[0].location, "All Campuses")

        XCTAssertEqual(schoolEvents[1].category, .school)
        XCTAssertFalse(schoolEvents[1].isAllDay)
        XCTAssertTrue(schoolEvents[1].title.contains("Fall Academic Showcase"))
        XCTAssertEqual(schoolEvents[1].location, "Main Auditorium, Building A")

        XCTAssertThrowsError(try FamilyPortalICalendarParser.parse(ics: "", category: .homework)) { error in
            guard case .parseFailure = error as? FamilyPortalCalendarError else {
                XCTFail("Expected .parseFailure, got \(error)")
                return
            }
        }
    }

    func testFamilyPortalCalendarSubscriptionsRequireAtLeastOneAndIsolateCategorySpaces() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SchoolTrackerCalendarTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let stateURL = tempDir.appendingPathComponent("state.json", isDirectory: false)
        let store = SchoolTrackerStore(stateFileURL: stateURL)

        // 1. Selecting 0 categories must throw .atLeastOneCategoryRequired ("Choose at least 1 option above.")
        XCTAssertThrowsError(
            try store.updateCalendarSubscriptions(selectedCategories: [], feedURLStrings: [:])
        ) { error in
            XCTAssertEqual(error as? FamilyPortalCalendarError, .atLeastOneCategoryRequired)
            XCTAssertTrue((error.localizedDescription).contains("Choose at least 1 option above"))
        }

        // 2. Persisting 1-3 selected categories saves 0600 credentials in saved-calendars.json and redacts state.json
        let stateAfterSub = try store.updateCalendarSubscriptions(
            selectedCategories: [.school, .classrooms, .homework],
            feedURLStrings: [.school: AnonymizedReportFixtures.validWebcalFeedURL]
        )
        XCTAssertEqual(stateAfterSub.calendarSubscriptions.filter(\.isSubscribed).count, 3)

        let credPath = store.savedCalendarsCredentialFileURL.path
        XCTAssertTrue(FileManager.default.fileExists(atPath: credPath))
        let attrs = try FileManager.default.attributesOfItem(atPath: credPath)
        if let perms = attrs[.posixPermissions] as? NSNumber {
            XCTAssertEqual(perms.intValue & 0o777, 0o600)
        }

        let rawStateJSON = try String(contentsOf: stateURL, encoding: .utf8)
        XCTAssertFalse(rawStateJSON.contains(AnonymizedReportFixtures.validSessionID))
        XCTAssertTrue(rawStateJSON.contains("REDACTED"))

        // 3. Ingesting .ics feeds per category isolates events into School, My Classrooms, and My Homework spaces
        try store.applyCalendarICS(AnonymizedReportFixtures.schoolCalendarICS, for: .school)
        try store.applyCalendarICS(AnonymizedReportFixtures.classroomsCalendarICS, for: .classrooms)
        try store.applyCalendarICS(AnonymizedReportFixtures.homeworkCalendarICS, for: .homework)

        let loadedState = try store.loadState()
        let schoolSpaceEvents = loadedState.events(for: .school)
        let classroomSpaceEvents = loadedState.events(for: .classrooms)
        let homeworkSpaceEvents = loadedState.events(for: .homework)

        XCTAssertTrue(schoolSpaceEvents.allSatisfy { $0.category == .school })
        XCTAssertTrue(schoolSpaceEvents.contains { $0.title == "Thanksgiving Break - Campus Closed" })

        XCTAssertTrue(classroomSpaceEvents.allSatisfy { $0.category == .classrooms })
        XCTAssertTrue(classroomSpaceEvents.contains { $0.title == "AP Calculus BC - Taylor Series Seminar" })

        XCTAssertTrue(homeworkSpaceEvents.allSatisfy { $0.category == .homework })
        XCTAssertTrue(homeworkSpaceEvents.contains { $0.title == "Honors Chemistry - Titration Lab Post-Lab Questions" })
    }

    // MARK: - 7. Working Tree Secret & PII Audit

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

    // MARK: - 8. FLHS GPA & Weight Tier Tests

    func testFLHSHandbookGPAScaleAndCourseWeightTiers() throws {
        // FLHS unweighted scale verification
        XCTAssertEqual(GPACalculator.unweightedPoints(for: 98.0), 4.0, accuracy: 0.001)
        XCTAssertEqual(GPACalculator.unweightedPoints(for: 94.0), 3.8, accuracy: 0.001)
        XCTAssertEqual(GPACalculator.unweightedPoints(for: 91.5), 3.6, accuracy: 0.001)
        XCTAssertEqual(GPACalculator.unweightedPoints(for: 88.0), 3.4, accuracy: 0.001)
        XCTAssertEqual(GPACalculator.unweightedPoints(for: 85.0), 3.2, accuracy: 0.001)
        XCTAssertEqual(GPACalculator.unweightedPoints(for: 81.0), 3.0, accuracy: 0.001)
        XCTAssertEqual(GPACalculator.unweightedPoints(for: 78.5), 2.8, accuracy: 0.001)
        XCTAssertEqual(GPACalculator.unweightedPoints(for: 75.0), 2.6, accuracy: 0.001)
        XCTAssertEqual(GPACalculator.unweightedPoints(for: 72.0), 2.4, accuracy: 0.001)
        XCTAssertEqual(GPACalculator.unweightedPoints(for: 70.5), 2.0, accuracy: 0.001)
        XCTAssertEqual(GPACalculator.unweightedPoints(for: 69.9), 0.0, accuracy: 0.001)
        XCTAssertEqual(GPACalculator.unweightedPoints(for: 50.0), 0.0, accuracy: 0.001)

        // Weight bonuses
        XCTAssertEqual(CourseWeightTier.regular.weightBonus, 0.0, accuracy: 0.001)
        XCTAssertEqual(CourseWeightTier.honors.weightBonus, 0.50, accuracy: 0.001)
        XCTAssertEqual(CourseWeightTier.advancedHonorsDualCredit.weightBonus, 1.00, accuracy: 0.001)

        // Weighted points calculation: score 95.0 (base 3.8)
        XCTAssertEqual(GPACalculator.weightedPoints(for: 95.0, tier: .regular), 3.8, accuracy: 0.001)
        XCTAssertEqual(GPACalculator.weightedPoints(for: 95.0, tier: .honors), 4.3, accuracy: 0.001)
        XCTAssertEqual(GPACalculator.weightedPoints(for: 95.0, tier: .advancedHonorsDualCredit), 4.8, accuracy: 0.001)

        // Failing scores (< 70) yield 0.0 weighted points regardless of tier
        XCTAssertEqual(GPACalculator.weightedPoints(for: 68.0, tier: .advancedHonorsDualCredit), 0.0, accuracy: 0.001)

        // Letter grade inference
        XCTAssertEqual(GPACalculator.letterGrade(for: 92.0), "A")
        XCTAssertEqual(GPACalculator.letterGrade(for: 84.0), "B")
        XCTAssertEqual(GPACalculator.letterGrade(for: 75.0), "C")
        XCTAssertEqual(GPACalculator.letterGrade(for: 70.5), "D")
        XCTAssertEqual(GPACalculator.letterGrade(for: 65.0), "F")

        // Overall GPA calculation for mixed courses
        let sampleCourses = [
            ImportedCourse(courseName: "Theology 11", numericAverage: 95.0, weightTier: .regular),
            ImportedCourse(courseName: "Honors Chemistry", numericAverage: 88.0, weightTier: .honors),
            ImportedCourse(courseName: "AP Calculus BC", numericAverage: 92.0, weightTier: .advancedHonorsDualCredit)
        ]
        let summary = GPACalculator.calculateGPA(for: sampleCourses)
        XCTAssertEqual(summary.unweightedGPA, 3.60, accuracy: 0.01)
        XCTAssertEqual(summary.weightedGPA, 4.10, accuracy: 0.01)
        XCTAssertEqual(summary.earnedCredits, 1.50, accuracy: 0.01)
        XCTAssertEqual(summary.totalCreditsAttempted, 1.50, accuracy: 0.01)
    }

    func testFLHSHonorRollQualificationsAndDisqualifications() throws {
        // Principal's Honor Roll: all courses >= 90 AND weighted GPA >= 4.00
        let principalsCourses = [
            ImportedCourse(courseName: "Calculus I", numericAverage: 95.0, weightTier: .advancedHonorsDualCredit),
            ImportedCourse(courseName: "Physics AH", numericAverage: 92.0, weightTier: .advancedHonorsDualCredit),
            ImportedCourse(courseName: "English III AH", numericAverage: 94.0, weightTier: .advancedHonorsDualCredit)
        ]
        let pSummary = GPACalculator.calculateGPA(for: principalsCourses)
        XCTAssertEqual(pSummary.honorRollStatus, .principalsHonorRoll)

        // Honor Roll: all courses >= 80 AND weighted GPA >= 3.75
        let honorCourses = [
            ImportedCourse(courseName: "Theology 11", numericAverage: 94.0, weightTier: .regular),
            ImportedCourse(courseName: "Chemistry H", numericAverage: 88.0, weightTier: .honors),
            ImportedCourse(courseName: "Latin III H", numericAverage: 86.0, weightTier: .honors)
        ]
        let hSummary = GPACalculator.calculateGPA(for: honorCourses)
        XCTAssertEqual(hSummary.honorRollStatus, .honorRoll)

        // Merit Roll: all courses >= 80 AND weighted GPA >= 3.25
        let meritCourses = [
            ImportedCourse(courseName: "Theology 11", numericAverage: 84.0, weightTier: .regular),
            ImportedCourse(courseName: "World History", numericAverage: 85.0, weightTier: .regular),
            ImportedCourse(courseName: "Art I", numericAverage: 88.0, weightTier: .regular)
        ]
        let mSummary = GPACalculator.calculateGPA(for: meritCourses)
        XCTAssertEqual(mSummary.honorRollStatus, .meritRoll)

        // Disqualification: failing grade (< 70) disqualifies despite high weighted GPA
        let disqualifiedCourses = [
            ImportedCourse(courseName: "Calculus I", numericAverage: 99.0, weightTier: .advancedHonorsDualCredit),
            ImportedCourse(courseName: "Physics AH", numericAverage: 99.0, weightTier: .advancedHonorsDualCredit),
            ImportedCourse(courseName: "Physical Education", numericAverage: 68.0, weightTier: .regular)
        ]
        let dSummary = GPACalculator.calculateGPA(for: disqualifiedCourses)
        XCTAssertEqual(dSummary.honorRollStatus, .none)
    }

    func testAcademicHistoryStoreMultiQuarterPersistenceAndExports() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let storeFile = tempDir.appendingPathComponent("history.json")
        let store = AcademicHistoryStore(historyFileURL: storeFile)

        let q1Courses = [
            ImportedCourse(courseName: "Christian Doctrine III", courseCode: "THEO 11", numericAverage: 94.0, weightTier: .regular),
            ImportedCourse(courseName: "Calculus I", courseCode: "MATH 184", numericAverage: 95.0, weightTier: .advancedHonorsDualCredit)
        ]
        let q2Courses = [
            ImportedCourse(courseName: "Christian Doctrine III", courseCode: "THEO 11", numericAverage: 96.0, weightTier: .regular),
            ImportedCourse(courseName: "Calculus I", courseCode: "MATH 184", numericAverage: 91.0, weightTier: .advancedHonorsDualCredit)
        ]

        // Record Q1 and Q2
        try store.recordSnapshot(courses: q1Courses, schoolYear: "2026-2027", termName: "Q1", source: "test")
        try store.recordSnapshot(courses: q2Courses, schoolYear: "2026-2027", termName: "Q2", source: "test")

        // Load and verify
        let snapshots = try store.loadHistory()
        XCTAssertEqual(snapshots.count, 2)
        XCTAssertEqual(snapshots[0].termName, "Q1")
        XCTAssertEqual(snapshots[1].termName, "Q2")

        // Verify POSIX permissions 0600
        let attrs = try FileManager.default.attributesOfItem(atPath: storeFile.path)
        if let perms = attrs[.posixPermissions] as? NSNumber {
            XCTAssertEqual(perms.intValue, 0o600)
        }

        // Export JSON
        let json = try store.exportJSON()
        XCTAssertTrue(json.contains("2026-2027"))
        XCTAssertTrue(json.contains("Q1"))
        XCTAssertTrue(json.contains("Q2"))
        XCTAssertTrue(json.contains("Christian Doctrine III"))

        // Export CSV
        let csv = store.exportCSV()
        XCTAssertTrue(csv.contains("School Year,Term,Course Name,Course Code,Teacher,Numeric Grade,Letter Grade,Weight Tier,Unweighted Points,Weighted Points,Credits Earned,Source"))
        XCTAssertTrue(csv.contains("2026-2027,Q1,Christian Doctrine III,THEO 11"))
        XCTAssertTrue(csv.contains("2026-2027,Q2,Calculus I,MATH 184"))

        // Export Markdown
        let md = store.exportMarkdownTranscript()
        XCTAssertTrue(md.contains("# Official Academic Record & Historical Transcripts"))
        XCTAssertTrue(md.contains("## 2026-2027 — Q1"))
        XCTAssertTrue(md.contains("## 2026-2027 — Q2"))
        XCTAssertTrue(md.contains("| Christian Doctrine III | THEO 11 | 94.0% |"))
    }

    func testLocalTranscriptTextParsingAndTierInference() throws {
        let (snapshot, courses) = try LocalTranscriptParser.parseTranscriptText(
            AnonymizedReportFixtures.anonymizedFLHSTranscriptText
        )

        XCTAssertEqual(courses.count, 8)
        XCTAssertEqual(snapshot.schoolYear, "2026-2027")
        XCTAssertEqual(snapshot.termName, "Semester 1")

        let eng = courses.first(where: { $0.courseCode == "ENG 102" })
        XCTAssertEqual(eng?.weightTier, .advancedHonorsDualCredit)

        let chem = courses.first(where: { $0.courseCode == "CHEM H" })
        XCTAssertEqual(chem?.weightTier, .honors)

        let theo = courses.first(where: { $0.courseCode == "THEO 11" })
        XCTAssertEqual(theo?.weightTier, .regular)

        XCTAssertEqual(snapshot.gpaSummary.earnedCredits, 4.0, accuracy: 0.01)
        XCTAssertEqual(snapshot.gpaSummary.totalCreditsAttempted, 4.0, accuracy: 0.01)
        XCTAssertEqual(snapshot.gpaSummary.weightedGPA, 4.30, accuracy: 0.05)
        XCTAssertEqual(snapshot.gpaSummary.unweightedGPA, 3.68, accuracy: 0.05)
        XCTAssertEqual(snapshot.gpaSummary.honorRollStatus, .honorRoll)
    }

    func testElementaryAndNonAcademicCoursesExcludedFromHighSchoolCreditsAndGPA() throws {
        // Test course categorization
        XCTAssertTrue(ImportedCourse.isElementaryOrMiddleSchool(name: "1st Grade Math"))
        XCTAssertTrue(ImportedCourse.isElementaryOrMiddleSchool(name: "Grade 1 Reading"))
        XCTAssertTrue(ImportedCourse.isElementaryOrMiddleSchool(name: "Kindergarten"))
        XCTAssertTrue(ImportedCourse.isElementaryOrMiddleSchool(name: "Pre-K Motor Skills"))
        XCTAssertTrue(ImportedCourse.isElementaryOrMiddleSchool(name: "5th Grade Social Studies"))
        XCTAssertTrue(ImportedCourse.isElementaryOrMiddleSchool(name: "Middle School Band"))
        XCTAssertFalse(ImportedCourse.isElementaryOrMiddleSchool(name: "Algebra 1"))
        XCTAssertFalse(ImportedCourse.isElementaryOrMiddleSchool(name: "Spanish 1"))
        XCTAssertFalse(ImportedCourse.isElementaryOrMiddleSchool(name: "English 9"))
        XCTAssertFalse(ImportedCourse.isElementaryOrMiddleSchool(name: "Theology 11"))

        XCTAssertTrue(ImportedCourse.isNonAcademicOrAdministrative(name: "Homeroom"))
        XCTAssertTrue(ImportedCourse.isNonAcademicOrAdministrative(name: "Chapel"))
        XCTAssertTrue(ImportedCourse.isNonAcademicOrAdministrative(name: "Advisory"))
        XCTAssertTrue(ImportedCourse.isNonAcademicOrAdministrative(name: "Conduct"))
        XCTAssertTrue(ImportedCourse.isNonAcademicOrAdministrative(name: "Attendance"))
        XCTAssertTrue(ImportedCourse.isNonAcademicOrAdministrative(name: "Study Hall"))
        XCTAssertFalse(ImportedCourse.isNonAcademicOrAdministrative(name: "Biology H"))

        let c1stGrade = ImportedCourse(courseName: "1st Grade Reading", numericAverage: 98.0)
        XCTAssertFalse(c1stGrade.countsTowardGraduation)
        XCTAssertFalse(c1stGrade.countsTowardGPA)

        let cHomeroom = ImportedCourse(courseName: "Homeroom", numericAverage: 100.0)
        XCTAssertFalse(cHomeroom.countsTowardGraduation)
        XCTAssertFalse(cHomeroom.countsTowardGPA)

        let hsEnglish = ImportedCourse(courseName: "English I H", numericAverage: 94.0, weightTier: .honors)
        XCTAssertTrue(hsEnglish.countsTowardGraduation)
        XCTAssertTrue(hsEnglish.countsTowardGPA)

        let hsMath = ImportedCourse(courseName: "Algebra I", numericAverage: 90.0, weightTier: .regular)
        XCTAssertTrue(hsMath.countsTowardGraduation)
        XCTAssertTrue(hsMath.countsTowardGPA)

        // GPA calculation must completely exclude 1st grade & homeroom
        let summary = GPACalculator.calculateGPA(for: [c1stGrade, cHomeroom, hsEnglish, hsMath])
        // Only hsEnglish (0.50 cr) and hsMath (0.50 cr) should earn credit = 1.0 total
        XCTAssertEqual(summary.earnedCredits, 1.0, accuracy: 0.01)
        XCTAssertEqual(summary.totalCreditsAttempted, 1.0, accuracy: 0.01)
        // GPA is average of hsEnglish (4.3 weighted) and hsMath (3.6 weighted) = (4.3 + 3.6) / 2 = 3.95
        XCTAssertEqual(summary.weightedGPA, 3.95, accuracy: 0.01)
        XCTAssertEqual(summary.unweightedGPA, 3.70, accuracy: 0.01)
    }

    func testLocalTranscriptParserExcludesElementaryCourses() throws {
        let transcriptText = """
        Faith Lutheran High School
        Academic Transcript: 2026-2027
        Term: Semester 1

        1st Grade - 2015-2016
        ELEM 101   1st Grade Phonics               98.0   0.50   Regular
        ELEM 102   1st Grade Math                  95.0   0.50   Regular

        Grade 9 - 2026-2027
        THEO 11    Christian Doctrine III          94.0   0.50   Regular
        MATH 184   Calculus I                      95.0   0.50   Dual Credit
        """

        let (snapshot, courses) = try LocalTranscriptParser.parseTranscriptText(transcriptText)
        XCTAssertEqual(courses.count, 4)

        let elemPhonics = courses.first(where: { $0.courseName.contains("Phonics") })
        XCTAssertNotNil(elemPhonics)
        XCTAssertFalse(elemPhonics!.countsTowardGraduation)
        XCTAssertFalse(elemPhonics!.countsTowardGPA)
        XCTAssertEqual(elemPhonics!.creditHours, 0.0)

        let calc = courses.first(where: { $0.courseName == "Calculus I" })
        XCTAssertNotNil(calc)
        XCTAssertTrue(calc!.countsTowardGraduation)
        XCTAssertTrue(calc!.countsTowardGPA)

        // 1st grade courses do NOT count towards graduation credits (only Theo + Calc = 1.0 credit)
        XCTAssertEqual(snapshot.gpaSummary.earnedCredits, 1.0, accuracy: 0.01)
        XCTAssertEqual(snapshot.gpaSummary.totalCreditsAttempted, 1.0, accuracy: 0.01)
    }

    func testFACTSSISTranscriptParsingAndMultiYearSnapshots() throws {
        let text = """
        Student
        Transcripts
        Year Name Course Grade Credits Earned Instructor
        2016-2017 Sem 1 Art 98 1.000 Teacher, Elementary
        2016-2017 Sem 1 Handwriting 88 1.000 Teacher, Elementary
        2024-2025 Sem 1 Algebra 1 Honors 88 0.500 Instructor, Math
        2024-2025 Sem 1 English I Ancient
        Literature
        89 0.500 Instructor, English
        2025-2026 Sem 2 Geometry Honors 84 0.500 Instructor, Math
        2025-2026 Sem 2 Choir P 0.500 Instructor, Music
        """

        let result = try LocalTranscriptParser.parseTranscriptTextFull(text)
        XCTAssertEqual(result.allSnapshots.count, 3)

        // Primary snapshot should be latest high school term (2025-2026 Semester 2)
        XCTAssertEqual(result.snapshot.schoolYear, "2025-2026")
        XCTAssertEqual(result.snapshot.termName, "Semester 2")

        // Check elementary course exclusion
        let elemSnapshot = result.allSnapshots.first(where: { $0.schoolYear == "2016-2017" })
        XCTAssertNotNil(elemSnapshot)
        for c in elemSnapshot!.courses {
            XCTAssertFalse(c.countsTowardGraduation)
            XCTAssertFalse(c.countsTowardGPA)
            XCTAssertEqual(c.creditHours, 0.0)
        }

        // Check high school course credits
        let hs2024Snapshot = result.allSnapshots.first(where: { $0.schoolYear == "2024-2025" })
        XCTAssertNotNil(hs2024Snapshot)
        let eng = hs2024Snapshot!.courses.first(where: { $0.courseName.contains("English I Ancient Literature") })
        XCTAssertNotNil(eng)
        XCTAssertEqual(eng!.numericAverage, 89.0)
        XCTAssertEqual(eng!.creditHours, 0.50)
        XCTAssertTrue(eng!.countsTowardGraduation)
    }

    func testRenWebReportCardParsingWithSplitLinesAndTeachers() throws {
        let text = """
        FAITH LUTHERAN SCHOOL
        REPORT CARD
        2026-2027 - Q2
        COURSE NAME
        SEMESTER 1 SEMESTER 2 FINAL
        1 2 EXAM GRADE 3 4 EXAM GRADE GRADE
        ALGEBRA 2 91
        MRS.
        MILDRED
        CHOIR P
        MISS ROUNDEY
        ENGLISH III CO
        RE 85
        MR.
        MERRITT
        U.S. HISTO
        RY 87
        MR.
        MERRITT
        1 2 3 4 Total
        School Days 0 0 0 0 0
        """

        let result = try LocalTranscriptParser.parseTranscriptTextFull(text)
        XCTAssertEqual(result.snapshot.schoolYear, "2026-2027")
        XCTAssertEqual(result.snapshot.termName, "Quarter 2")
        XCTAssertEqual(result.courses.count, 4)

        let alg = result.courses.first(where: { $0.courseName == "ALGEBRA 2" })
        XCTAssertNotNil(alg)
        XCTAssertEqual(alg!.numericAverage, 91.0)
        XCTAssertEqual(alg!.teacherName, "Mrs. MILDRED")

        let choir = result.courses.first(where: { $0.courseName == "CHOIR" })
        XCTAssertNotNil(choir)
        XCTAssertEqual(choir!.letterGrade, "P")

        let eng = result.courses.first(where: { $0.courseName == "ENGLISH III CORE" })
        XCTAssertNotNil(eng)
        XCTAssertEqual(eng!.numericAverage, 85.0)
        XCTAssertEqual(eng!.teacherName, "Mr. MERRITT")

        let usHist = result.courses.first(where: { $0.courseName == "U.S. HISTORY" })
        XCTAssertNotNil(usHist)
        XCTAssertEqual(usHist!.numericAverage, 87.0)
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
            ("testFamilyPortalCalendarLinkParserNormalizesWebcalAndRedactsTokens", suite.testFamilyPortalCalendarLinkParserNormalizesWebcalAndRedactsTokens),
            ("testFamilyPortalICalendarParserExtractsEventsPerCategory", suite.testFamilyPortalICalendarParserExtractsEventsPerCategory),
            ("testFamilyPortalCalendarSubscriptionsRequireAtLeastOneAndIsolateCategorySpaces", suite.testFamilyPortalCalendarSubscriptionsRequireAtLeastOneAndIsolateCategorySpaces),
            ("testRepositoryWorkingTreeContainsNoLiveTokens", suite.testRepositoryWorkingTreeContainsNoLiveTokens),
            ("testFLHSHandbookGPAScaleAndCourseWeightTiers", suite.testFLHSHandbookGPAScaleAndCourseWeightTiers),
            ("testFLHSHonorRollQualificationsAndDisqualifications", suite.testFLHSHonorRollQualificationsAndDisqualifications),
            ("testAcademicHistoryStoreMultiQuarterPersistenceAndExports", suite.testAcademicHistoryStoreMultiQuarterPersistenceAndExports),
            ("testLocalTranscriptTextParsingAndTierInference", suite.testLocalTranscriptTextParsingAndTierInference),
            ("testElementaryAndNonAcademicCoursesExcludedFromHighSchoolCreditsAndGPA", suite.testElementaryAndNonAcademicCoursesExcludedFromHighSchoolCreditsAndGPA),
            ("testLocalTranscriptParserExcludesElementaryCourses", suite.testLocalTranscriptParserExcludesElementaryCourses),
            ("testFACTSSISTranscriptParsingAndMultiYearSnapshots", suite.testFACTSSISTranscriptParsingAndMultiYearSnapshots),
            ("testRenWebReportCardParsingWithSplitLinesAndTeachers", suite.testRenWebReportCardParsingWithSplitLinesAndTeachers)
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
