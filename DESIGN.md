# One-Page Design Note: SchoolTracker macOS App & FACTS/RenWeb Report Boundary

## Context & Goal
Build a native macOS school tracker app (`SchoolTracker`) that tracks courses, grades, and assignments, imports grades from temporary FACTS/RenWeb email report links (`GetReport.cfm`), and ships to a GitHub repository with zero sensitive data (SessionIDs, district codes, student PII, or real grade reports) in git history.

## Architecture & Technology Choices
- **Boring, testable stack:** Swift Package (`Package.swift`, macOS 14+) split into two targets:
  1. `SchoolTrackerCore` (library): URL validation/redaction, FACTS/RenWeb HTTP fetcher, HTML report parser, local persistence store, and domain models. Fully covered by `swift test`.
  2. `SchoolTrackerApp` (executable): Native SwiftUI macOS interface consuming `SchoolTrackerCore`.
- **Why:** Standard SwiftPM builds and tests cleanly from the CLI (`swift build`, `swift test`) without brittle Xcode project files, and keeps UI decoupled from parsing and network boundaries.

## Service Boundary: FACTS/RenWeb Report Ingestion
- **Endpoint pattern:** `https://<subdomains>.factsmgt.com/renweb/email/GetReport.cfm?District=<DISTRICT>&SessionID=<SESSION_ID>`
- **Input contract:**
  - `RenWebLinkParser` validates HTTPS scheme, allowed FACTS/RenWeb host, and presence of `District` and `SessionID` query parameters.
  - Redaction rule: Any log or error output must mask `SessionID` (e.g., `REDACTED`) and never emit raw student HTML.
- **Response & Error contract:**
  - `RenWebClient` fetches the HTML payload with a 15s timeout and explicit `RenWebError` cases: `.invalidURL`, `.expiredOrInvalidSession`, `.networkFailure(statusCode: Int?)`, `.parseFailure(reason: String)`.
  - `RenWebReportParser` extracts courses, current averages/letter grades, and assignment rows from the HTML report into `ImportedGradeReport`.
- **Reversibility:** The parser accepts a `RenWebFetching` protocol so live HTTP calls can be swapped with synthetic HTML fixtures in tests or offline mode.

## Security & Git Hygiene Boundary
- **Forbidden in git:** The user-supplied `District` (`<REDACTED_DISTRICT>`), `SessionID` (`<REDACTED_SESSION_ID>`), live HTML responses, student names, and local database files must never enter the repository or test fixtures.
- **Allowed in git:** Synthetic test fixtures using `District=TEST-XX` and `SessionID=00000000-0000-0000-0000-000000000000` with anonymized HTML structure matching the live report layout.
- **Local storage:** Runtime state saves to `~/Library/Application Support/SchoolTracker/state.json` (excluded via `.gitignore`).
