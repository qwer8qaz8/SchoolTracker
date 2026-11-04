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

    public init(
        id: UUID = UUID(),
        courseName: String,
        courseCode: String? = nil,
        teacherName: String? = nil,
        term: String? = nil,
        numericAverage: Double? = nil,
        letterGrade: String? = nil,
        assignments: [ImportedAssignment] = [],
        categories: [CategoryBreakdown] = []
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
    public var courses: [ImportedCourse]

    public init(
        term: String? = nil,
        schoolYear: String? = nil,
        fetchedAt: Date = Date(),
        courses: [ImportedCourse]
    ) {
        self.term = term
        self.schoolYear = schoolYear
        self.fetchedAt = fetchedAt
        self.courses = courses
    }

    public var overallNumericAverage: Double? {
        let validAverages = courses.compactMap(\.numericAverage)
        guard !validAverages.isEmpty else { return nil }
        return validAverages.reduce(0, +) / Double(validAverages.count)
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

public struct SchoolTrackerState: Codable, Equatable, Sendable {
    public var courses: [ImportedCourse]
    public var tasks: [TrackedTask]
    public var lastSyncedAt: Date?
    public var lastSyncedDistrict: String?
    public var lastRedactedReportURL: String?

    public init(
        courses: [ImportedCourse] = [],
        tasks: [TrackedTask] = [],
        lastSyncedAt: Date? = nil,
        lastSyncedDistrict: String? = nil,
        lastRedactedReportURL: String? = nil
    ) {
        self.courses = courses
        self.tasks = tasks
        self.lastSyncedAt = lastSyncedAt
        self.lastSyncedDistrict = lastSyncedDistrict
        self.lastRedactedReportURL = lastRedactedReportURL
    }

    public var overallAverage: Double? {
        let grades = courses.compactMap(\.numericAverage)
        guard !grades.isEmpty else { return nil }
        return grades.reduce(0, +) / Double(grades.count)
    }
}
