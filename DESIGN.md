# One-Page Design Note: SchoolTracker macOS App & FACTS/RenWeb Report & Calendar Boundaries

## Context & Goal
Build a native macOS school tracker app (`SchoolTracker`, with a custom macOS `.icns` icon) that tracks courses, grades, assignments, and Family Portal calendars (`School`, `My Classrooms`, `My Homework` in dedicated spaces), imports grades from temporary FACTS/RenWeb email report links (`GetReport.cfm`), saves the active temporary link and calendar subscription URLs locally, and ships to GitHub with zero sensitive data (SessionIDs, calendar tokens, district codes, student PII, or real grade/calendar payloads) in git history.

## Architecture & Technology Choices
- **Boring, testable stack:** Swift Package (`Package.swift`, macOS 14+) split into two targets:
  1. `SchoolTrackerCore` (library): URL validation/redaction, FACTS/RenWeb HTTP fetcher, HTML report parser, iCalendar (`.ics`) feed parser & fetcher, saved-link & calendar credential store, local persistence store, and domain models.
  2. `SchoolTrackerApp` (executable): Native SwiftUI macOS interface consuming `SchoolTrackerCore`, packaged with a custom `AppIcon.icns`.
- **Why:** Standard SwiftPM builds and tests cleanly from the CLI (`swift build`, `./scripts/run-tests.sh`) without brittle Xcode project files, and keeps UI decoupled from parsing and network boundaries.

## Service Boundary 1: FACTS/RenWeb Report Ingestion & Saved Link Expiration
- **Endpoint pattern:** `https://<subdomains>.factsmgt.com/renweb/email/GetReport.cfm?District=<DISTRICT>&SessionID=<SESSION_ID>`
- **Input contract:** `RenWebLinkParser` validates HTTPS scheme, allowed FACTS/RenWeb host, and presence of `District` and `SessionID` query parameters, masking `SessionID=REDACTED` in logs and `state.json`.
- **Saved Link & Expiration Contract:** `SavedRenWebLink` stores `district`, `redactedURL`, `savedAt`, `expiresAt` (parsed from HTML or defaulting to 14 days from `savedAt`), `lastVerifiedAt`, and `isConfirmedExpired`. The raw URL is stored in `~/Library/Application Support/SchoolTracker/saved-link.json` (`0600`).
- **Response & Error contract:** `RenWebClient` fetches the HTML payload (15s timeout) and `RenWebReportParser` extracts courses, averages/letter grades, assignments, and explicit expiry into `ImportedGradeReport`.

## Service Boundary 2: Family Portal Calendar Subscriptions (`School`, `My Classrooms`, `My Homework`)
- **Categories & Dedicated Spaces:** `FamilyPortalCalendarCategory` defines three separate calendar spaces matching FACTS Family Portal subscriptions: `.school` ("School"), `.classrooms` ("My Classrooms"), and `.homework` ("My Homework"). Each category has its own dedicated sidebar navigation space (`SidebarSection.calendar(FamilyPortalCalendarCategory)`) plus a subscription chooser sheet enforcing at least 1 selected category (`Choose which Family Portal calendars you would like to subscribe to`, `Choose at least 1 option above`).
- **Input & Redaction Contract:**
  - `FamilyPortalCalendarLinkParser` accepts `https://` or `webcal://` (normalized to `https://`) calendar feed URLs, validates scheme/host/length (<= 4 KB), and masks query/path tokens (`token`, `key`, `auth`, `sessionid`, `id`, or long hex/UUID segments) as `REDACTED` in `state.json` and logs.
  - Raw calendar feed URLs are stored in `~/Library/Application Support/SchoolTracker/saved-calendars.json` (`0600` owner-only permissions), while `state.json` stores `FamilyPortalCalendarSubscription` (`category`, `isEnabled`, `redactedFeedURL`, `lastSyncedAt`) and `calendars: [FamilyPortalCalendarCategory: [CalendarEvent]]`.
- **Feed & Local Synthesis Contract:**
  - `FamilyPortalICalendarParser` parses RFC 5545 `VEVENT` blocks (`UID`, `SUMMARY`, `DTSTART`, `DTEND`, `DESCRIPTION`, `LOCATION`, `CATEGORIES`, folded lines, and escaped text) into `CalendarEvent`.
  - When a category is subscribed without an external `.ics` URL (or alongside one), `SchoolTrackerStore` also projects imported course assignments (`.homework`), course sessions/exams (`.classrooms`), and tracked school-wide dates (`.school`) into their respective category space so each space is immediately useful.

## Security & Git Hygiene Boundary
- **Forbidden in git:** Live `District`, `SessionID`, calendar feed tokens, live HTML/ICS responses, student names, and local database/credential files (`state.json`, `saved-link.json`, `saved-calendars.json`).
- **Allowed in git:** Synthetic test fixtures using `District=TEST-XX`, `SessionID=00000000-0000-0000-0000-000000000000`, and anonymized `.ics` feeds.
