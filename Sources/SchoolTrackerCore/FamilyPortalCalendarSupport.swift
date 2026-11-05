import Foundation

// MARK: - Family Portal Calendar Errors & Validated Feed Links

public enum FamilyPortalCalendarError: Error, Equatable, LocalizedError, CustomStringConvertible, Sendable {
    case atLeastOneCategoryRequired
    case invalidFeedURL
    case networkFailure(statusCode: Int?)
    case parseFailure(reason: String)

    public var errorDescription: String? {
        switch self {
        case .atLeastOneCategoryRequired:
            return "Choose at least 1 option above."
        case .invalidFeedURL:
            return "The calendar feed link must be a valid https:// or webcal:// URL."
        case .networkFailure(let statusCode):
            if let statusCode {
                return "Failed to fetch the Family Portal calendar feed (HTTP \(statusCode))."
            }
            return "Failed to reach the Family Portal calendar feed over the network."
        case .parseFailure(let reason):
            return "Could not parse the iCalendar (.ics) feed: \(reason)"
        }
    }

    public var description: String {
        errorDescription ?? "Unknown FamilyPortalCalendarError"
    }
}

public struct ValidatedCalendarFeedLink: Equatable, Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let url: URL
    public let category: FamilyPortalCalendarCategory
    public let redactedDescription: String

    public init(url: URL, category: FamilyPortalCalendarCategory, redactedDescription: String) {
        self.url = url
        self.category = category
        self.redactedDescription = redactedDescription
    }

    public var description: String {
        redactedDescription
    }

    public var debugDescription: String {
        "ValidatedCalendarFeedLink(\(category.rawValue), \(redactedDescription))"
    }
}

public enum FamilyPortalCalendarLinkParser {
    public static let maxURLBytes = 4_096

    private static let sensitiveQueryParamNames: Set<String> = [
        "sessionid",
        "token",
        "key",
        "auth",
        "secret",
        "sig",
        "id"
    ]

    public static func parse(
        _ rawInput: String,
        for category: FamilyPortalCalendarCategory
    ) throws -> ValidatedCalendarFeedLink {
        if rawInput.utf8.count > maxURLBytes {
            SchoolTrackerTelemetry.shared.increment(
                .calendarSubscriptionUpdateFailure,
                context: "oversized_calendar_url_bytes=\(rawInput.utf8.count)"
            )
            throw FamilyPortalCalendarError.invalidFeedURL
        }

        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              var components = URLComponents(string: trimmed)
        else {
            SchoolTrackerTelemetry.shared.increment(.calendarSubscriptionUpdateFailure, context: "malformed_calendar_url")
            throw FamilyPortalCalendarError.invalidFeedURL
        }

        let rawScheme = components.scheme?.lowercased() ?? ""
        guard rawScheme == "https" || rawScheme == "webcal" else {
            SchoolTrackerTelemetry.shared.increment(.calendarSubscriptionUpdateFailure, context: "unsupported_scheme=\(rawScheme)")
            throw FamilyPortalCalendarError.invalidFeedURL
        }

        components.scheme = "https"
        guard let host = components.host, !host.isEmpty, host.contains("."),
              let normalizedURL = components.url
        else {
            SchoolTrackerTelemetry.shared.increment(.calendarSubscriptionUpdateFailure, context: "invalid_calendar_host")
            throw FamilyPortalCalendarError.invalidFeedURL
        }

        let redacted = makeRedactedURLString(from: components)
        return ValidatedCalendarFeedLink(
            url: normalizedURL,
            category: category,
            redactedDescription: redacted
        )
    }

    private static func makeRedactedURLString(from components: URLComponents) -> String {
        var copy = components
        if let items = copy.queryItems, !items.isEmpty {
            copy.queryItems = items.map { item in
                let lowerName = item.name.lowercased()
                if sensitiveQueryParamNames.contains(lowerName) || looksLikeSecretToken(item.value ?? "") {
                    return URLQueryItem(name: item.name, value: "REDACTED")
                }
                return item
            }
        }
        let rawString = copy.string ?? "https://factsmgt.com/calendar/REDACTED.ics"
        return SchoolTrackerTelemetry.redactSensitiveTokens(in: rawString)
    }

    private static func looksLikeSecretToken(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 16 else { return false }
        let allowed = CharacterSet(charactersIn: "0123456789abcdefABCDEF-")
        return trimmed.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}

// MARK: - RFC 5545 iCalendar (.ics) Parser

public enum FamilyPortalICalendarParser {
    public static func parse(
        ics: String,
        category: FamilyPortalCalendarCategory
    ) throws -> [CalendarEvent] {
        let trimmed = ics.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.uppercased().contains("BEGIN:VCALENDAR") else {
            SchoolTrackerTelemetry.shared.increment(.calendarFeedParseFailure, context: "missing_vcalendar")
            throw FamilyPortalCalendarError.parseFailure(reason: "Payload is not a valid VCALENDAR document.")
        }

        let unfoldedLines = unfoldICalendarLines(in: trimmed)
        var events: [CalendarEvent] = []
        var inEvent = false
        var currentFields: [(name: String, params: String, value: String)] = []

        for line in unfoldedLines {
            let upper = line.uppercased()
            if upper == "BEGIN:VEVENT" {
                inEvent = true
                currentFields.removeAll(keepingCapacity: true)
                continue
            }
            if upper == "END:VEVENT" {
                if inEvent, let event = buildCalendarEvent(from: currentFields, category: category) {
                    events.append(event)
                }
                inEvent = false
                currentFields.removeAll(keepingCapacity: true)
                continue
            }
            guard inEvent, let colonIndex = line.firstIndex(of: ":") else {
                continue
            }

            let left = String(line[..<colonIndex])
            let value = String(line[line.index(after: colonIndex)...])
            let parts = left.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
            let propName = parts.first.map { String($0).uppercased() } ?? ""
            let propParams = parts.count > 1 ? String(parts[1]).uppercased() : ""
            currentFields.append((name: propName, params: propParams, value: value))
        }

        guard !events.isEmpty else {
            SchoolTrackerTelemetry.shared.increment(.calendarFeedParseFailure, context: "no_vevents_parsed")
            throw FamilyPortalCalendarError.parseFailure(reason: "No valid VEVENT entries found in iCalendar feed.")
        }

        SchoolTrackerTelemetry.shared.increment(
            .calendarFeedParseSuccess,
            context: "category=\(category.rawValue) events=\(events.count)"
        )
        return events
    }

    private static func unfoldICalendarLines(in raw: String) -> [String] {
        let normalized = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let rawLines = normalized.components(separatedBy: "\n")

        var unfolded: [String] = []
        unfolded.reserveCapacity(rawLines.count)

        for line in rawLines {
            if (line.hasPrefix(" ") || line.hasPrefix("\t")), !unfolded.isEmpty {
                let continuation = String(line.dropFirst())
                unfolded[unfolded.count - 1] += continuation
            } else {
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedLine.isEmpty {
                    unfolded.append(trimmedLine)
                }
            }
        }
        return unfolded
    }

    private static func buildCalendarEvent(
        from fields: [(name: String, params: String, value: String)],
        category: FamilyPortalCalendarCategory
    ) -> CalendarEvent? {
        var uid: String?
        var summary: String?
        var description: String?
        var location: String?
        var startDate: Date?
        var endDate: Date?
        var isAllDay = false

        for field in fields {
            switch field.name {
            case "UID":
                uid = unescapeICalendarText(field.value)
            case "SUMMARY":
                summary = unescapeICalendarText(field.value)
            case "DESCRIPTION":
                description = unescapeICalendarText(field.value)
            case "LOCATION":
                location = unescapeICalendarText(field.value)
            case "DTSTART":
                if let parsed = parseICalendarDate(value: field.value, params: field.params) {
                    startDate = parsed.date
                    isAllDay = parsed.isAllDay
                }
            case "DTEND":
                if let parsed = parseICalendarDate(value: field.value, params: field.params) {
                    endDate = parsed.date
                }
            default:
                break
            }
        }

        guard let title = summary?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty,
              let resolvedStart = startDate
        else {
            return nil
        }

        return CalendarEvent(
            uid: uid,
            category: category,
            title: title,
            courseName: inferCourseName(from: title),
            startDate: resolvedStart,
            endDate: endDate,
            isAllDay: isAllDay,
            location: location?.isEmpty == false ? location : nil,
            notes: description?.isEmpty == false ? description : nil,
            source: .icalFeed,
            isCompleted: false
        )
    }

    private static func parseICalendarDate(value: String, params: String) -> (date: Date, isAllDay: Bool)? {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        // All-day date: YYYYMMDD
        if params.contains("VALUE=DATE") || cleaned.count == 8 {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyyMMdd"
            if let date = formatter.date(from: String(cleaned.prefix(8))) {
                return (date, true)
            }
        }

        // UTC or floating timestamp: YYYYMMDDTHHMMSSZ or YYYYMMDDTHHMMSS
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        if cleaned.hasSuffix("Z") {
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            if let date = formatter.date(from: cleaned) {
                return (date, false)
            }
        } else {
            formatter.timeZone = TimeZone.current
            formatter.dateFormat = "yyyyMMdd'T'HHmmss"
            if let date = formatter.date(from: String(cleaned.prefix(15))) {
                return (date, false)
            }
        }

        return nil
    }

    private static func unescapeICalendarText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\N", with: "\n")
            .replacingOccurrences(of: "\\\\", with: "\\")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func inferCourseName(from summary: String) -> String? {
        guard let separatorRange = summary.range(of: " - ") else { return nil }
        let prefix = summary[..<separatorRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return prefix.isEmpty ? nil : prefix
    }
}

// MARK: - Local Event Synthesis per Category Space

public enum FamilyPortalCalendarEventSynthesizer {
    public static func synthesizeEvents(
        for category: FamilyPortalCalendarCategory,
        courses: [ImportedCourse],
        tasks: [TrackedTask],
        defaultYear: Int = 2026
    ) -> [CalendarEvent] {
        switch category {
        case .homework:
            var homeworkEvents: [CalendarEvent] = []
            for course in courses {
                for assignment in course.assignments {
                    guard let dateStr = assignment.dueDate,
                          let dueDate = parseReportDueDate(dateStr, defaultYear: defaultYear)
                    else { continue }
                    let uid = "synth-hw-\(course.courseName)-\(assignment.title)-\(dateStr)"
                    homeworkEvents.append(
                        CalendarEvent(
                            id: assignment.id,
                            uid: uid,
                            category: .homework,
                            title: "\(course.courseName) - \(assignment.title)",
                            courseName: course.courseName,
                            startDate: dueDate,
                            endDate: nil,
                            isAllDay: true,
                            location: assignment.category,
                            notes: "Score: \(assignment.scoreDisplay)",
                            source: .importedReport,
                            isCompleted: assignment.isCompleted
                        )
                    )
                }
            }
            for task in tasks where task.courseName.caseInsensitiveCompare("School") != .orderedSame {
                if let due = task.dueDate {
                    homeworkEvents.append(
                        CalendarEvent(
                            id: task.id,
                            uid: "synth-task-\(task.id.uuidString)",
                            category: .homework,
                            title: task.title,
                            courseName: task.courseName,
                            startDate: due,
                            endDate: nil,
                            isAllDay: false,
                            location: nil,
                            notes: task.notes,
                            source: .importedReport,
                            isCompleted: task.isCompleted
                        )
                    )
                }
            }
            return homeworkEvents

        case .classrooms:
            var classroomEvents: [CalendarEvent] = []
            for course in courses {
                for assignment in course.assignments {
                    let lowerCat = assignment.category.lowercased()
                    let lowerTitle = assignment.title.lowercased()
                    let isClassroomAssessment = lowerCat.contains("test")
                        || lowerCat.contains("quiz")
                        || lowerCat.contains("lab")
                        || lowerCat.contains("speech")
                        || lowerCat.contains("exam")
                        || lowerTitle.contains("test")
                        || lowerTitle.contains("quiz")
                        || lowerTitle.contains("exam")
                        || lowerTitle.contains("lab")

                    guard isClassroomAssessment,
                          let dateStr = assignment.dueDate,
                          let sessionDate = parseReportDueDate(dateStr, defaultYear: defaultYear)
                    else { continue }

                    let uid = "synth-classroom-\(course.courseName)-\(assignment.title)-\(dateStr)"
                    classroomEvents.append(
                        CalendarEvent(
                            id: assignment.id,
                            uid: uid,
                            category: .classrooms,
                            title: "\(course.courseName): \(assignment.title)",
                            courseName: course.courseName,
                            startDate: sessionDate,
                            endDate: nil,
                            isAllDay: true,
                            location: course.teacherName.map { "Instructor: \($0)" } ?? assignment.category,
                            notes: "Category: \(assignment.category) (\(assignment.scoreDisplay))",
                            source: .importedReport,
                            isCompleted: assignment.isCompleted
                        )
                    )
                }
            }
            return classroomEvents

        case .school:
            return tasks
                .filter { $0.courseName.caseInsensitiveCompare("School") == .orderedSame || $0.courseName.caseInsensitiveCompare("General") == .orderedSame }
                .compactMap { task in
                    guard let due = task.dueDate else { return nil }
                    return CalendarEvent(
                        id: task.id,
                        uid: "synth-school-\(task.id.uuidString)",
                        category: .school,
                        title: task.title,
                        courseName: "School",
                        startDate: due,
                        endDate: nil,
                        isAllDay: true,
                        location: "Campus",
                        notes: task.notes,
                        source: .importedReport,
                        isCompleted: task.isCompleted
                    )
                }
        }
    }

    private static func parseReportDueDate(_ text: String, defaultYear: Int) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let parts = trimmed.split(separator: "/")
        guard parts.count >= 2,
              let month = Int(parts[0]),
              let day = Int(parts[1])
        else { return nil }

        let year: Int
        if parts.count >= 3, let explicitYear = Int(parts[2]) {
            year = explicitYear < 100 ? (2000 + explicitYear) : explicitYear
        } else {
            year = defaultYear
        }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 9
        components.minute = 0
        return Calendar.current.date(from: components)
    }
}
