# One-Page Design Note: SchoolTracker macOS App & FACTS/RenWeb Report Boundary

## Context & Goal
Build a native macOS school tracker app (`SchoolTracker`) that tracks courses, grades, and assignments, imports grades from temporary FACTS/RenWeb email report links (`GetReport.cfm`), saves the active temporary link locally with expiration tracking for one-click re-syncs, and ships to a GitHub repository with zero sensitive data (SessionIDs, district codes, student PII, or real grade reports) in git history.

## Architecture & Technology Choices
- **Boring, testable stack:** Swift Package (`Package.swift`, macOS 14+) split into two targets:
  1. `SchoolTrackerCore` (library): URL validation/redaction, FACTS/RenWeb HTTP fetcher, HTML report parser, saved-link credential & expiration store, local persistence store, and domain models.
  2. `SchoolTrackerApp` (executable): Native SwiftUI macOS interface consuming `SchoolTrackerCore`.
- **Why:** Standard SwiftPM builds and tests cleanly from the CLI (`swift build`, `./scripts/run-tests.sh`) without brittle Xcode project files, and keeps UI decoupled from parsing and network boundaries.

## Service Boundary: FACTS/RenWeb Report Ingestion & Saved Link Expiration
- **Endpoint pattern:** `https://<subdomains>.factsmgt.com/renweb/email/GetReport.cfm?District=<DISTRICT>&SessionID=<SESSION_ID>`
- **Input contract:**
  - `RenWebLinkParser` validates HTTPS scheme, allowed FACTS/RenWeb host, and presence of `District` and `SessionID` query parameters.
  - Redaction rule: Any log, telemetry event, or `state.json` entry must mask `SessionID` (`REDACTED`) and never emit raw student HTML.
- **Saved Link & Expiration Contract:**
  - `SavedRenWebLink` stores `district`, `redactedURL`, `savedAt`, `expiresAt` (parsed from the report HTML if an explicit expiry date is present, otherwise defaulting to FACTS/RenWeb's 14-day temporary email link window from `savedAt`), `lastVerifiedAt`, and `isConfirmedExpired`.
  - The raw unredacted URL is persisted separately in `~/Library/Application Support/SchoolTracker/saved-link.json` with `0600` owner-only permissions (never in `state.json` or logs) so the user can re-sync in one click (`Sync Saved Link`) without re-pasting, and clear it at any time.
  - Expiration state (`SavedLinkExpirationStatus`): `.active(daysRemaining: Int, hoursRemaining: Int, expiresAt: Date)`, `.expiringSoon(hoursRemaining: Int, expiresAt: Date)` (<48h left), or `.expired(expiresAt: Date, confirmedByServer: Bool)` (when `now >= expiresAt` or when `RenWebClient` receives `.expiredOrInvalidSession`, which immediately flips `isConfirmedExpired = true`).
- **Response & Error contract:**
  - `RenWebClient` fetches the HTML payload with a 15s timeout and explicit `RenWebError` cases: `.invalidURL`, `.expiredOrInvalidSession`, `.networkFailure(statusCode: Int?)`, `.parseFailure(reason: String)`.
  - `RenWebReportParser` extracts courses, current averages/letter grades, assignment rows, and any explicit report expiration date from the HTML report into `ImportedGradeReport`.

## Security & Git Hygiene Boundary
- **Forbidden in git:** The user-supplied `District` (`<REDACTED_DISTRICT>`), `SessionID` (`<REDACTED_SESSION_ID>`), live HTML responses, student names, and local database/credential files must never enter the repository or test fixtures.
- **Allowed in git:** Synthetic test fixtures using `District=TEST-XX` and `SessionID=00000000-0000-0000-0000-000000000000` with anonymized HTML structure matching the live report layout.
- **Local storage:** Runtime state saves to `~/Library/Application Support/SchoolTracker/state.json` and the active link credential saves to `~/Library/Application Support/SchoolTracker/saved-link.json` (`0600`), both excluded via `.gitignore`.
