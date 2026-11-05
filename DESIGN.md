# One-Page Design Note: SchoolTracker macOS App, FLHS GPA, Academic History & Apple Intelligence Boundaries

## Context & Goal
Extend `SchoolTracker` with Faith Lutheran High School (FLHS) handbook GPA calculations (weighted/unweighted, Honors +0.50, Advanced Honors/Dual Credit +1.00, Merit/Honor/Principal's Honor Roll), on-device Apple Intelligence/Vision/PDFKit transcript and report card ingestion, persistent multi-term history (`history.json`) that survives RenWeb link expiration and quarter rollovers, data export (JSON/CSV/Printable Markdown), App Intents/Siri, CoreSpotlight search, and macOS Liquid Glass visual design.

## Architecture & Technology Choices
- **Boring, testable stack:** Swift Package (`Package.swift`, macOS 14+) split into two targets:
  1. `SchoolTrackerCore` (library): URL validation/redaction, FACTS/RenWeb fetcher & parser, iCalendar parser, FLHS GPA engine, multi-term history store & exporter, and local OCR/document extraction protocol.
  2. `SchoolTrackerApp` (executable): Native macOS SwiftUI interface with Liquid Glass materials (`.ultraThinMaterial`), App Intents (`AppIntents`), Spotlight indexing (`CoreSpotlight`), transcript/report-card import sheet, GPA breakdown views, and history archives.

## Service Boundary 1: FLHS Handbook GPA & Honor Roll Calculation
- **Scale (Handbook p. 6):**
  - Tiers: Regular (+0.0), Honors (+0.50), Advanced Honors / Dual Credit (+1.00).
  - Scale: `97-100`: 4.0/4.5/5.0; `93-96`: 3.8/4.3/4.8; `90-92`: 3.6/4.1/4.6; `87-89`: 3.4/3.9/4.4; `83-86`: 3.2/3.7/4.2; `80-82`: 3.0/3.5/4.0; `77-79`: 2.8/3.3/3.8; `73-76`: 2.6/3.1/3.6; `71-72`: 2.4/2.9/3.4; `70`: 2.0/2.5/3.0; `<70` or Incomplete: 0.0.
  - Passing score: `>= 70`. Semester grade: average of two quarters.
- **Honor Roll Recognition (Handbook p. 8):**
  - Merit Roll: All grades A or B, all passing (`>= 70`), weighted GPA `>= 3.25`.
  - Honor Roll: All grades A or B, all passing (`>= 70`), weighted GPA `>= 3.75`.
  - Principal's Honor Roll: All grades A (`>= 90`), all passing (`>= 70`), weighted GPA `>= 4.00`.
- **Course Tier Classification:**
  - Auto-detected via course code and title suffixes (`H` -> Honors, `AH` or college prefix `MATH 151`, `ENG 102`, `ECON 2301`, etc. -> Advanced Honors/Dual Credit).
  - Fully customizable by the user per course or historical entry.

## Service Boundary 2: Multi-Term History Archival & Export
- **Problem:** When a FACTS/RenWeb link expires or the school moves to a new quarter with a fresh link, past grades must not disappear.
- **Persistence:** `~/Library/Application Support/SchoolTracker/history.json` stores immutable `TermSnapshot` entries (`id`, `schoolYear`, `termName`, `syncedAt`, `gpaSummary`, `courses`, `honorRollStatus`).
- **Sync Behavior:** Whenever a report or transcript is imported, `SchoolTrackerStore` automatically snapshots the term into history, deduping by `schoolYear` and `termName`.
- **Export Contract:** One-click export to JSON (`school-tracker-history.json`), CSV (`grades-history.csv`), and formatted Markdown (`transcript-summary.md`).

## Service Boundary 3: Local Apple Intelligence / Vision Document Ingestion
- **Local Ingestion:** `TranscriptDocumentParser` processes PDF and image transcripts/report cards entirely on-device using PDFKit text streams with fallback to Apple Vision (`VNRecognizeTextRequest`).
- **Extraction Contract:** Extracts student school year, term, course name, course code, grade, and credits into `ImportedTranscriptReport`. No external AI APIs or network calls are used.

## Service Boundary 4: macOS System Integration & Liquid Glass Design
- **App Intents & Siri:** Exposes `GetGradeSummaryIntent`, `GetGPAIntent`, and `SyncSchoolTrackerIntent` via the `AppIntents` framework.
- **CoreSpotlight:** Indexes active courses, teachers, and historical terms into macOS Spotlight.
- **Liquid Glass Design:** Adopts macOS window translucency, `.ultraThinMaterial` sidebars and card backgrounds, system blur effects, and native controls.

## Security & Git Hygiene Boundary
- Forbidden in git: Real student names, session IDs, district codes, live PDF/HTML transcripts, or `history.json`/`state.json`.
- Allowed in git: Synthetic test fixtures and anonymized sample transcripts (`Student: Student A`, `District: TEST-XX`).
