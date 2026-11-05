import Foundation

// MARK: - Error Contract

public enum RenWebError: Error, Equatable, LocalizedError, CustomStringConvertible, Sendable {
    case invalidURL
    case expiredOrInvalidSession
    case networkFailure(statusCode: Int?)
    case parseFailure(reason: String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The link is not a valid HTTPS FACTS/RenWeb GetReport.cfm URL with District and SessionID parameters."
        case .expiredOrInvalidSession:
            return "This temporary FACTS/RenWeb report session has expired or is no longer valid. Request a fresh report email link."
        case .networkFailure(let statusCode):
            if let statusCode {
                return "Failed to fetch the FACTS/RenWeb report (HTTP \(statusCode))."
            }
            return "Failed to reach FACTS/RenWeb over the network."
        case .parseFailure(let reason):
            return "Could not parse the grade report HTML: \(reason)"
        }
    }

    public var description: String {
        errorDescription ?? "Unknown RenWebError"
    }
}

// MARK: - Validated Link & Redaction Boundary

public struct ValidatedRenWebLink: Equatable, Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let url: URL
    public let district: String
    public let sessionID: String

    public init(url: URL, district: String, sessionID: String) {
        self.url = url
        self.district = district
        self.sessionID = sessionID
    }

    /// Safe representation for logs, UI diagnostics, and string interpolation. Never contains the raw SessionID.
    public var redactedDescription: String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return "https://factsmgt.com/renweb/email/GetReport.cfm?District=\(district)&SessionID=REDACTED"
        }
        components.queryItems = components.queryItems?.map { item in
            if item.name.caseInsensitiveCompare("SessionID") == .orderedSame {
                return URLQueryItem(name: item.name, value: "REDACTED")
            }
            return item
        }
        let candidate = components.string ?? "https://factsmgt.com/renweb/email/GetReport.cfm?District=\(district)&SessionID=REDACTED"
        return candidate.replacingOccurrences(of: sessionID, with: "REDACTED")
    }

    public var description: String {
        redactedDescription
    }

    public var debugDescription: String {
        "ValidatedRenWebLink(\(redactedDescription))"
    }
}

// MARK: - Domain Models

public struct CategoryBreakdown: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var weight: Double?
    public var average: Double?

    public init(
        id: UUID = UUID(),
        name: String,
        weight: Double? = nil,
        average: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.weight = weight
        self.average = average
    }
}

public struct ImportedAssignment: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var category: String
    public var dueDate: String?
    public var pointsEarned: Double?
    public var pointsPossible: Double?
    public var percentage: Double?
    public var status: String?
    public var note: String?
    public var isCompleted: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        category: String = "General",
        dueDate: String? = nil,
        pointsEarned: Double? = nil,
        pointsPossible: Double? = nil,
        percentage: Double? = nil,
        status: String? = nil,
        note: String? = nil,
        isCompleted: Bool = true
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.dueDate = dueDate
        self.pointsEarned = pointsEarned
        self.pointsPossible = pointsPossible
        self.percentage = percentage
        self.status = status
        self.note = note
        self.isCompleted = isCompleted
    }

    public var name: String {
        get { title }
        set { title = newValue }
    }

    public var scoreDisplay: String {
        if let earned = pointsEarned, let max = pointsPossible {
            return "\(Self.cleanNumber(earned)) / \(Self.cleanNumber(max))"
        }
        if let pct = percentage {
            return String(format: "%.1f%%", pct)
        }
        return "Pending"
    }

    private static func cleanNumber(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }
}

public typealias AssignmentGrade = ImportedAssignment

public struct ImportedCourse: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var courseName: String
    public var courseCode: String?
    public var teacherName: String?
    public var term: String?
    public var numericAverage: Double?
    public var letterGrade: String?
    public var assignments: [ImportedAssignment]
    public var categories: [CategoryBreakdown]
    public var weightTier: CourseWeightTier?
    public var creditHours: Double?
    public var countsTowardGraduation: Bool
    public var countsTowardGPA: Bool

    public init(
        id: UUID = UUID(),
        courseName: String,
        courseCode: String? = nil,
        teacherName: String? = nil,
        term: String? = nil,
        numericAverage: Double? = nil,
        letterGrade: String? = nil,
        assignments: [ImportedAssignment] = [],
        categories: [CategoryBreakdown] = [],
        weightTier: CourseWeightTier? = nil,
        creditHours: Double? = nil,
        countsTowardGraduation: Bool? = nil,
        countsTowardGPA: Bool? = nil
    ) {
        self.id = id
        self.courseName = courseName
        self.courseCode = courseCode
        self.teacherName = teacherName
        self.term = term
        self.numericAverage = numericAverage
        self.letterGrade = letterGrade
        self.assignments = assignments
        self.categories = categories
        self.weightTier = weightTier
        self.creditHours = creditHours

        let isExcluded = Self.isExcludedFromHighSchool(courseName: courseName, courseCode: courseCode, term: term)
        self.countsTowardGraduation = countsTowardGraduation ?? !isExcluded
        self.countsTowardGPA = countsTowardGPA ?? !isExcluded
    }

    enum CodingKeys: String, CodingKey {
        case id, courseName, courseCode, teacherName, term, numericAverage, letterGrade, assignments, categories, weightTier
        case creditHours, countsTowardGraduation, countsTowardGPA
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.courseName = try container.decode(String.self, forKey: .courseName)
        self.courseCode = try container.decodeIfPresent(String.self, forKey: .courseCode)
        self.teacherName = try container.decodeIfPresent(String.self, forKey: .teacherName)
        self.term = try container.decodeIfPresent(String.self, forKey: .term)
        self.numericAverage = try container.decodeIfPresent(Double.self, forKey: .numericAverage)
        self.letterGrade = try container.decodeIfPresent(String.self, forKey: .letterGrade)
        self.assignments = try container.decodeIfPresent([ImportedAssignment].self, forKey: .assignments) ?? []
        self.categories = try container.decodeIfPresent([CategoryBreakdown].self, forKey: .categories) ?? []
        self.weightTier = try container.decodeIfPresent(CourseWeightTier.self, forKey: .weightTier)
        self.creditHours = try container.decodeIfPresent(Double.self, forKey: .creditHours)

        let isExcluded = Self.isExcludedFromHighSchool(courseName: courseName, courseCode: courseCode, term: term)
        self.countsTowardGraduation = try container.decodeIfPresent(Bool.self, forKey: .countsTowardGraduation) ?? !isExcluded
        self.countsTowardGPA = try container.decodeIfPresent(Bool.self, forKey: .countsTowardGPA) ?? !isExcluded
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(courseName, forKey: .courseName)
        try container.encodeIfPresent(courseCode, forKey: .courseCode)
        try container.encodeIfPresent(teacherName, forKey: .teacherName)
        try container.encodeIfPresent(term, forKey: .term)
        try container.encodeIfPresent(numericAverage, forKey: .numericAverage)
        try container.encodeIfPresent(letterGrade, forKey: .letterGrade)
        try container.encode(assignments, forKey: .assignments)
        try container.encode(categories, forKey: .categories)
        try container.encodeIfPresent(weightTier, forKey: .weightTier)
        try container.encodeIfPresent(creditHours, forKey: .creditHours)
        try container.encode(countsTowardGraduation, forKey: .countsTowardGraduation)
        try container.encode(countsTowardGPA, forKey: .countsTowardGPA)
    }

    public var effectiveWeightTier: CourseWeightTier {
        weightTier ?? CourseWeightTier.inferTier(courseName: courseName, courseCode: courseCode)
    }

    public var isRelevantForHighSchool: Bool {
        !Self.isExcludedFromHighSchool(courseName: courseName, courseCode: courseCode, term: term)
    }

    public var exclusionReason: String? {
        if !countsTowardGraduation && !countsTowardGPA {
            if Self.isElementaryOrMiddleSchool(name: courseName, code: courseCode, term: term) {
                return "Elementary / Middle School (Grades 1–8)"
            }
            if Self.isNonAcademicOrAdministrative(name: courseName, code: courseCode) {
                return "Non-Academic / Non-Credit (Advisory, Chapel, etc.)"
            }
            return "Excluded from High School Credit & GPA"
        } else if !countsTowardGraduation {
            return "Excluded from Graduation Credit"
        } else if !countsTowardGPA {
            return "Excluded from GPA"
        }
        return nil
    }

    /// Evaluates if a course is elementary or middle school coursework (Grades 1–8, Kindergarten, etc.).
    public static func isElementaryOrMiddleSchool(name: String, code: String? = nil, term: String? = nil, schoolYear: String? = nil) -> Bool {
        if let year = schoolYear?.trimmingCharacters(in: .whitespacesAndNewlines),
           year.range(of: #"^20\d{2}-20\d{2}$"#, options: .regularExpression) != nil {
            if year < "2024-2025" {
                return true
            }
        }

        let combined = "\(name) \(code ?? "") \(term ?? "") \(schoolYear ?? "")".lowercased()

        // Elementary & Middle School grades (1st through 8th)
        let gradePattern = #"\b(?:1st|2nd|3rd|[4-8]th|first|second|third|fourth|fifth|sixth|seventh|eighth)\s+grade\b"#
        if combined.range(of: gradePattern, options: .regularExpression) != nil {
            return true
        }

        // "Grade 1" through "Grade 8" or "Gr 1" through "Gr 8" or "Gr. 1" through "Gr. 8"
        let gradeNumPattern = #"\bgr(?:ade|\.|\s+)\s*[1-8]\b"#
        if combined.range(of: gradeNumPattern, options: .regularExpression) != nil {
            return true
        }

        // Kindergarten / Pre-K / Elementary keywords
        let earlyEduPattern = #"\b(?:kindergarten|pre-?k|preschool|elementary|primary\s+school)\b"#
        if combined.range(of: earlyEduPattern, options: .regularExpression) != nil {
            return true
        }

        // Middle School keywords
        let msPattern = #"\b(?:middle\s+school|jr\.?\s*high|junior\s+high)\b"#
        if combined.range(of: msPattern, options: .regularExpression) != nil {
            return true
        }

        // Check course codes specifically
        if let code = code?.uppercased().trimmingCharacters(in: .whitespacesAndNewlines) {
            let prefixes = ["MS-", "MS ", "ELEM-", "ELEM ", "KIND-", "KIND ", "GR1-", "GR2-", "GR3-", "GR4-", "GR5-", "GR6-", "GR7-", "GR8-"]
            for prefix in prefixes where code.hasPrefix(prefix) {
                return true
            }
        }

        return false
    }

    /// Evaluates if a course is non-academic or administrative (Homeroom, Advisory, Chapel, Attendance, etc.).
    public static func isNonAcademicOrAdministrative(name: String, code: String? = nil) -> Bool {
        let combined = "\(name) \(code ?? "")".lowercased()

        let nonAcademicPattern = #"\b(?:homeroom|advisory|chapel|conduct|citizenship|attendance|study\s+hall|lunch|recess|unassigned|period\s+0|detention|work\s+habits|social\s+(?:growth|development)|character\s+ratings?|aide|office\s+aide|teacher\s+aide)\b"#
        if combined.range(of: nonAcademicPattern, options: .regularExpression) != nil {
            return true
        }

        if let code = code?.uppercased().trimmingCharacters(in: .whitespacesAndNewlines) {
            let nonCreditPrefixes = ["HR-", "ADV-", "CHP-", "ATT-", "NON-", "ACT-"]
            for prefix in nonCreditPrefixes where code.hasPrefix(prefix) {
                return true
            }
        }

        return false
    }

    /// Evaluates if a course should be excluded from high school credits and GPA calculation.
    public static func isExcludedFromHighSchool(courseName: String, courseCode: String? = nil, term: String? = nil, schoolYear: String? = nil) -> Bool {
        isElementaryOrMiddleSchool(name: courseName, code: courseCode, term: term, schoolYear: schoolYear)
            || isNonAcademicOrAdministrative(name: courseName, code: courseCode)
    }

    public var name: String {
        get { courseName }
        set { courseName = newValue }
    }

    public var teacher: String? {
        get { teacherName }
        set { teacherName = newValue }
    }
}

public typealias CourseGrade = ImportedCourse

public struct ImportedGradeReport: Codable, Equatable, Hashable, Sendable {
    public var term: String?
    public var schoolYear: String?
    public var fetchedAt: Date
    public var expiresAt: Date?
    public var courses: [ImportedCourse]

    public init(
        term: String? = nil,
        schoolYear: String? = nil,
        fetchedAt: Date = Date(),
        expiresAt: Date? = nil,
        courses: [ImportedCourse]
    ) {
        self.term = term
        self.schoolYear = schoolYear
        self.fetchedAt = fetchedAt
        self.expiresAt = expiresAt
        self.courses = courses
    }

    public var overallNumericAverage: Double? {
        let validAverages = courses.compactMap(\.numericAverage)
        guard !validAverages.isEmpty else { return nil }
        return validAverages.reduce(0, +) / Double(validAverages.count)
    }
}

// MARK: - Saved Temporary Link & Expiration Tracking

public enum SavedLinkExpirationStatus: Equatable, Hashable, Sendable {
    case active(daysRemaining: Int, hoursRemaining: Int, expiresAt: Date)
    case expiringSoon(hoursRemaining: Int, expiresAt: Date)
    case expired(expiresAt: Date, confirmedByServer: Bool)

    public var isExpired: Bool {
        if case .expired = self { return true }
        return false
    }
}

public struct SavedRenWebLink: Codable, Equatable, Hashable, Sendable {
    /// Default FACTS/RenWeb temporary email report link lifetime (14 days).
    public static let defaultTTL: TimeInterval = 14 * 86_400
    public static let expiringSoonThreshold: TimeInterval = 48 * 3_600

    public var district: String
    public var redactedURL: String
    public var savedAt: Date
    public var expiresAt: Date
    public var lastVerifiedAt: Date?
    public var isConfirmedExpired: Bool

    public init(
        district: String,
        redactedURL: String,
        savedAt: Date = Date(),
        expiresAt: Date? = nil,
        lastVerifiedAt: Date? = nil,
        isConfirmedExpired: Bool = false
    ) {
        self.district = district
        self.redactedURL = SchoolTrackerTelemetry.redactSensitiveTokens(in: redactedURL)
        self.savedAt = savedAt
        self.expiresAt = expiresAt ?? savedAt.addingTimeInterval(Self.defaultTTL)
        self.lastVerifiedAt = lastVerifiedAt ?? savedAt
        self.isConfirmedExpired = isConfirmedExpired
    }

    public func expirationStatus(referenceDate: Date = Date()) -> SavedLinkExpirationStatus {
        if isConfirmedExpired {
            return .expired(expiresAt: expiresAt, confirmedByServer: true)
        }
        let remaining = expiresAt.timeIntervalSince(referenceDate)
        guard remaining > 0 else {
            return .expired(expiresAt: expiresAt, confirmedByServer: false)
        }
        let totalHours = max(1, Int(ceil(remaining / 3_600.0)))
        if remaining <= Self.expiringSoonThreshold {
            return .expiringSoon(hoursRemaining: totalHours, expiresAt: expiresAt)
        }
        let days = Int(floor(remaining / 86_400.0))
        let leftoverHours = Int(floor((remaining - Double(days) * 86_400.0) / 3_600.0))
        return .active(daysRemaining: days, hoursRemaining: leftoverHours, expiresAt: expiresAt)
    }

    public func expirationSummaryText(referenceDate: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let formattedDate = formatter.string(from: expiresAt)

        switch expirationStatus(referenceDate: referenceDate) {
        case .active(let daysRemaining, let hoursRemaining, _):
            if daysRemaining >= 1 {
                let dayUnit = daysRemaining == 1 ? "day" : "days"
                if hoursRemaining > 0 {
                    return "Active (\(daysRemaining) \(dayUnit), \(hoursRemaining)h left, expires \(formattedDate))"
                }
                return "Active (\(daysRemaining) \(dayUnit) left, expires \(formattedDate))"
            }
            return "Active (\(max(1, hoursRemaining))h left, expires \(formattedDate))"
        case .expiringSoon(let hoursRemaining, _):
            let hourUnit = hoursRemaining == 1 ? "hour" : "hours"
            return "Expiring soon (\(hoursRemaining) \(hourUnit) left, expires \(formattedDate))"
        case .expired(_, let confirmedByServer):
            if confirmedByServer {
                return "Expired (confirmed by FACTS/RenWeb server)"
            }
            return "Expired on \(formattedDate)"
        }
    }
}

public struct TrackedTask: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var courseName: String
    public var dueDate: Date?
    public var isCompleted: Bool
    public var notes: String?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        courseName: String,
        dueDate: Date? = nil,
        isCompleted: Bool = false,
        notes: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.courseName = courseName
        self.dueDate = dueDate
        self.isCompleted = isCompleted
        self.notes = notes
        self.createdAt = createdAt
    }
}

// MARK: - Family Portal Calendar Categories, Subscriptions & Events

public enum FamilyPortalCalendarCategory: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case school = "School"
    case classrooms = "My Classrooms"
    case homework = "My Homework"

    public var id: String { rawValue }

    public var displayName: String { rawValue }

    public var subtitle: String {
        switch self {
        case .school:
            return "Campus-wide events, holidays, athletics, and assemblies"
        case .classrooms:
            return "Class sessions, seminars, labs, exams, and room schedules"
        case .homework:
            return "Course assignments, due dates, and study deliverables"
        }
    }

    public var systemImage: String {
        switch self {
        case .school:
            return "building.columns.fill"
        case .classrooms:
            return "person.3.sequence.fill"
        case .homework:
            return "checklist.checked"
        }
    }
}

public struct FamilyPortalCalendarSubscription: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var category: FamilyPortalCalendarCategory
    public var isSubscribed: Bool
    public var redactedFeedURL: String?
    public var lastSyncedAt: Date?

    public var id: String { category.rawValue }

    public var isEnabled: Bool {
        get { isSubscribed }
        set { isSubscribed = newValue }
    }

    public init(
        category: FamilyPortalCalendarCategory,
        isSubscribed: Bool = false,
        redactedFeedURL: String? = nil,
        lastSyncedAt: Date? = nil
    ) {
        self.category = category
        self.isSubscribed = isSubscribed
        self.redactedFeedURL = redactedFeedURL.map(SchoolTrackerTelemetry.redactSensitiveTokens)
        self.lastSyncedAt = lastSyncedAt
    }

    public static func defaultSubscriptions() -> [FamilyPortalCalendarSubscription] {
        FamilyPortalCalendarCategory.allCases.map { category in
            FamilyPortalCalendarSubscription(category: category, isSubscribed: true)
        }
    }
}

public enum CalendarEventSource: String, Codable, Equatable, Hashable, Sendable {
    case icalFeed
    case importedReport
    case manual
}

public struct CalendarEvent: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var uid: String?
    public var category: FamilyPortalCalendarCategory
    public var title: String
    public var courseName: String?
    public var startDate: Date
    public var endDate: Date?
    public var isAllDay: Bool
    public var location: String?
    public var notes: String?
    public var source: CalendarEventSource
    public var isCompleted: Bool

    public init(
        id: UUID = UUID(),
        uid: String? = nil,
        category: FamilyPortalCalendarCategory,
        title: String,
        courseName: String? = nil,
        startDate: Date,
        endDate: Date? = nil,
        isAllDay: Bool = false,
        location: String? = nil,
        notes: String? = nil,
        source: CalendarEventSource = .manual,
        isCompleted: Bool = false
    ) {
        self.id = id
        self.uid = uid
        self.category = category
        self.title = title
        self.courseName = courseName
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.location = location
        self.notes = notes
        self.source = source
        self.isCompleted = isCompleted
    }
}

// MARK: - Academic Weighting, GPA & Term History Models (FLHS Handbook)

public enum CourseWeightTier: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case regular = "Regular"
    case honors = "Honors"
    case advancedHonorsDualCredit = "Advanced Honors / Dual Credit"

    public var id: String { rawValue }
    public var displayName: String { rawValue }

    public var weightBonus: Double {
        switch self {
        case .regular:
            return 0.0
        case .honors:
            return 0.50
        case .advancedHonorsDualCredit:
            return 1.00
        }
    }

    public static func inferTier(courseName: String, courseCode: String? = nil) -> CourseWeightTier {
        let name = courseName.trimmingCharacters(in: .whitespacesAndNewlines)
        let code = courseCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let combined = "\(code) \(name)".uppercased()

        // 1. Check Advanced Honors / Dual Credit first (to avoid "AH" matching "H")
        let ahKeywords = [
            "ADVANCED HONORS", "ADV. HONORS", "ADV HONORS", "DUAL CREDIT",
            "SENIOR THESIS AH", "LATIN IV AH", "PHYSICS AH", "ADVANCED STATISTICS AH",
            "AMERICAN HISTORY AH", "U.S. GOVERNMENT/ECONOMICS AH", "ENGLISH III AH", "ENGLISH IV AH",
            "ALGEBRA II AH", "GREEK I AH", "GREEK II AH", "GREEK III AH"
        ]
        for kw in ahKeywords {
            if combined.contains(kw) {
                return .advancedHonorsDualCredit
            }
        }

        // Check dual credit college prefixes & course codes from handbook
        let collegeCourseCodes = [
            "MATH 122", "MATH 151", "MATH 175", "MATH 184", "MATH 186", "MATH 333",
            "HHP 100", "ENG 102", "ENG 201", "CTA 211", "MUS 103", "BUS 260",
            "ECON 2301", "ECON 2302"
        ]
        for cCode in collegeCourseCodes {
            if combined.contains(cCode) {
                return .advancedHonorsDualCredit
            }
        }

        if name.hasSuffix(" AH") || name.hasSuffix("(AH)") || code.hasSuffix(" AH") || code.hasSuffix("(AH)") {
            return .advancedHonorsDualCredit
        }

        // 2. Check Honors
        let honorsKeywords = [
            "HONORS", "ALGEBRA I H", "GEOMETRY H", "BIOLOGY H", "CHEMISTRY H",
            "ASTRONOMY H", "ENGLISH I H", "ENGLISH II H", "WORLD HISTORY I H",
            "WORLD HISTORY II H", "LATIN I H", "LATIN II H", "LATIN III H"
        ]
        for kw in honorsKeywords {
            if combined.contains(kw) {
                return .honors
            }
        }

        if name.hasSuffix(" H") || name.hasSuffix("(H)") || code.hasSuffix(" H") || code.hasSuffix("(H)") {
            return .honors
        }

        return .regular
    }
}

public enum HonorRollStatus: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case none = "None"
    case meritRoll = "Merit Roll"
    case honorRoll = "Honor Roll"
    case principalsHonorRoll = "Principal's Honor Roll"

    public var id: String { rawValue }
    public var displayName: String { rawValue }

    public var badgeDescription: String {
        switch self {
        case .none:
            return "No Honors"
        case .meritRoll:
            return "Merit Roll (All A/B, GPA ≥ 3.25)"
        case .honorRoll:
            return "Honor Roll (All A/B, GPA ≥ 3.75)"
        case .principalsHonorRoll:
            return "Principal's Honor Roll (All A's, GPA ≥ 4.00)"
        }
    }
}

public struct GPASummary: Codable, Equatable, Hashable, Sendable {
    public var unweightedGPA: Double
    public var weightedGPA: Double
    public var earnedCredits: Double
    public var totalCreditsAttempted: Double
    public var honorRollStatus: HonorRollStatus

    public init(
        unweightedGPA: Double = 0.0,
        weightedGPA: Double = 0.0,
        earnedCredits: Double = 0.0,
        totalCreditsAttempted: Double = 0.0,
        honorRollStatus: HonorRollStatus = .none
    ) {
        self.unweightedGPA = unweightedGPA
        self.weightedGPA = weightedGPA
        self.earnedCredits = earnedCredits
        self.totalCreditsAttempted = totalCreditsAttempted
        self.honorRollStatus = honorRollStatus
    }
}

public struct TermSnapshot: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var schoolYear: String
    public var termName: String
    public var syncedAt: Date
    public var gpaSummary: GPASummary
    public var courses: [ImportedCourse]
    public var source: String

    public init(
        id: UUID = UUID(),
        schoolYear: String,
        termName: String,
        syncedAt: Date = Date(),
        gpaSummary: GPASummary,
        courses: [ImportedCourse],
        source: String = "renweb"
    ) {
        self.id = id
        self.schoolYear = schoolYear
        self.termName = termName
        self.syncedAt = syncedAt
        self.gpaSummary = gpaSummary
        self.courses = courses
        self.source = source
    }
}

public struct SchoolTrackerState: Codable, Equatable, Sendable {
    public var courses: [ImportedCourse]
    public var tasks: [TrackedTask]
    public var lastSyncedAt: Date?
    public var lastSyncedDistrict: String?
    public var lastRedactedReportURL: String?
    public var savedLink: SavedRenWebLink?
    public var calendarSubscriptions: [FamilyPortalCalendarSubscription]
    public var calendarEvents: [CalendarEvent]
    public var academicHistory: [TermSnapshot]

    public init(
        courses: [ImportedCourse] = [],
        tasks: [TrackedTask] = [],
        lastSyncedAt: Date? = nil,
        lastSyncedDistrict: String? = nil,
        lastRedactedReportURL: String? = nil,
        savedLink: SavedRenWebLink? = nil,
        calendarSubscriptions: [FamilyPortalCalendarSubscription] = FamilyPortalCalendarSubscription.defaultSubscriptions(),
        calendarEvents: [CalendarEvent] = [],
        academicHistory: [TermSnapshot] = []
    ) {
        self.courses = courses
        self.tasks = tasks
        self.lastSyncedAt = lastSyncedAt
        self.lastSyncedDistrict = lastSyncedDistrict
        self.lastRedactedReportURL = lastRedactedReportURL
        self.savedLink = savedLink
        self.calendarSubscriptions = calendarSubscriptions.isEmpty
            ? FamilyPortalCalendarSubscription.defaultSubscriptions()
            : calendarSubscriptions
        self.calendarEvents = calendarEvents
        self.academicHistory = academicHistory
    }

    private enum CodingKeys: String, CodingKey {
        case courses
        case tasks
        case lastSyncedAt
        case lastSyncedDistrict
        case lastRedactedReportURL
        case savedLink
        case calendarSubscriptions
        case calendarEvents
        case academicHistory
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.courses = try container.decodeIfPresent([ImportedCourse].self, forKey: .courses) ?? []
        self.tasks = try container.decodeIfPresent([TrackedTask].self, forKey: .tasks) ?? []
        self.lastSyncedAt = try container.decodeIfPresent(Date.self, forKey: .lastSyncedAt)
        self.lastSyncedDistrict = try container.decodeIfPresent(String.self, forKey: .lastSyncedDistrict)
        self.lastRedactedReportURL = try container.decodeIfPresent(String.self, forKey: .lastRedactedReportURL)
        self.savedLink = try container.decodeIfPresent(SavedRenWebLink.self, forKey: .savedLink)
        let decodedSubs = try container.decodeIfPresent([FamilyPortalCalendarSubscription].self, forKey: .calendarSubscriptions)
        self.calendarSubscriptions = (decodedSubs?.isEmpty == false)
            ? decodedSubs!
            : FamilyPortalCalendarSubscription.defaultSubscriptions()
        self.calendarEvents = try container.decodeIfPresent([CalendarEvent].self, forKey: .calendarEvents) ?? []
        self.academicHistory = try container.decodeIfPresent([TermSnapshot].self, forKey: .academicHistory) ?? []
    }

    public var overallAverage: Double? {
        let grades = courses.compactMap(\.numericAverage)
        guard !grades.isEmpty else { return nil }
        return grades.reduce(0, +) / Double(grades.count)
    }

    public var subscribedCategories: [FamilyPortalCalendarCategory] {
        FamilyPortalCalendarCategory.allCases.filter { isSubscribed(to: $0) }
    }

    public func isSubscribed(to category: FamilyPortalCalendarCategory) -> Bool {
        calendarSubscriptions.first(where: { $0.category == category })?.isSubscribed ?? false
    }

    public func subscription(for category: FamilyPortalCalendarCategory) -> FamilyPortalCalendarSubscription {
        calendarSubscriptions.first(where: { $0.category == category })
            ?? FamilyPortalCalendarSubscription(category: category, isSubscribed: false)
    }

    /// Returns all events isolated to the requested Family Portal calendar space (`School`, `My Classrooms`, or `My Homework`).
    public func events(for category: FamilyPortalCalendarCategory) -> [CalendarEvent] {
        let directEvents = calendarEvents.filter { $0.category == category }
        let synthesized = FamilyPortalCalendarEventSynthesizer.synthesizeEvents(
            for: category,
            courses: courses,
            tasks: tasks
        )
        var combined = directEvents
        for candidate in synthesized {
            let duplicateExists = combined.contains { existing in
                if let u1 = existing.uid, let u2 = candidate.uid, u1 == u2 {
                    return true
                }
                return existing.title.caseInsensitiveCompare(candidate.title) == .orderedSame
                    && Calendar.current.isDate(existing.startDate, inSameDayAs: candidate.startDate)
            }
            if !duplicateExists {
                combined.append(candidate)
            }
        }
        return combined.sorted { lhs, rhs in
            if lhs.startDate != rhs.startDate {
                return lhs.startDate < rhs.startDate
            }
            return lhs.title < rhs.title
        }
    }
}
