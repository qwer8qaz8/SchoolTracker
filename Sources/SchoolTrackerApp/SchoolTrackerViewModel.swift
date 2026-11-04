import Foundation
import SwiftUI
import SchoolTrackerCore

public enum SidebarSection: Hashable, Identifiable {
    case overview
    case tasks
    case course(UUID)

    public var id: String {
        switch self {
        case .overview:
            return "overview"
        case .tasks:
            return "tasks"
        case .course(let uuid):
            return "course-\(uuid.uuidString)"
        }
    }
}

public enum TaskFilter: String, CaseIterable, Identifiable {
    case pending = "Pending"
    case completed = "Completed"
    case all = "All"

    public var id: String { rawValue }
}

public enum ViewLoadState: Equatable {
    case loading
    case empty
    case loaded
    case error(String)
}

public enum ImportSheetState: Equatable {
    case idle
    case validating
    case fetching(redactedURL: String, district: String)
    case success(courseCount: Int, assignmentCount: Int, district: String)
    case failure(String)

    public var isBusy: Bool {
        switch self {
        case .validating, .fetching:
            return true
        case .idle, .success, .failure:
            return false
        }
    }
}

@MainActor
public final class SchoolTrackerViewModel: ObservableObject {
    @Published public private(set) var state = SchoolTrackerState()
    @Published public private(set) var loadState: ViewLoadState = .loading
    @Published public var selectedSection: SidebarSection? = .overview
    @Published public var searchQuery: String = ""
    @Published public var taskFilter: TaskFilter = .pending

    @Published public var isPresentingImportSheet: Bool = false
    @Published public var isPresentingNewTaskSheet: Bool = false
    @Published public var importURLInput: String = ""
    @Published public private(set) var importState: ImportSheetState = .idle
    @Published public var persistenceBannerError: String?

    // Course Detail filter state
    @Published public var courseAssignmentFilter: String = ""
    @Published public var courseSelectedCategory: String = "All"

    // New Task Sheet draft state
    @Published public var draftTaskTitle: String = ""
    @Published public var draftTaskCourseName: String = "General"
    @Published public var draftTaskIncludeDueDate: Bool = false
    @Published public var draftTaskDueDate: Date = Date().addingTimeInterval(86_400)
    @Published public var draftTaskNotes: String = ""
    @Published public var draftTaskValidationError: String?

    private let store: SchoolTrackerStore
    private let client: RenWebClient

    public init(
        store: SchoolTrackerStore = SchoolTrackerStore(),
        client: RenWebClient = RenWebClient()
    ) {
        self.store = store
        self.client = client
    }

    // MARK: - Computed Summaries

    public var overallAverageText: String {
        guard let avg = state.overallAverage else { return "—" }
        return String(format: "%.1f%%", avg)
    }

    public var overallLetterGrade: String {
        guard let avg = state.overallAverage else { return "No Grade" }
        return Self.letterGrade(for: avg)
    }

    public var totalAssignmentsCount: Int {
        state.courses.reduce(0) { $0 + $1.assignments.count }
    }

    public var pendingTasksCount: Int {
        state.tasks.filter { !$0.isCompleted }.count
    }

    public var filteredTasks: [TrackedTask] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return state.tasks
            .filter { task in
                switch taskFilter {
                case .pending:
                    if task.isCompleted { return false }
                case .completed:
                    if !task.isCompleted { return false }
                case .all:
                    break
                }
                guard !query.isEmpty else { return true }
                return task.title.lowercased().contains(query)
                    || task.courseName.lowercased().contains(query)
                    || (task.notes?.lowercased().contains(query) ?? false)
            }
            .sorted { lhs, rhs in
                if lhs.isCompleted != rhs.isCompleted {
                    return !lhs.isCompleted
                }
                switch (lhs.dueDate, rhs.dueDate) {
                case let (l?, r?):
                    return l < r
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return lhs.createdAt > rhs.createdAt
                }
            }
    }

    public var liveLinkPreview: Result<ValidatedRenWebLink, RenWebError>? {
        let trimmed = importURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        do {
            return .success(try RenWebLinkParser.parse(trimmed))
        } catch let error as RenWebError {
            return .failure(error)
        } catch {
            return .failure(.invalidURL)
        }
    }

    public func course(for id: UUID) -> ImportedCourse? {
        state.courses.first { $0.id == id }
    }

    // MARK: - Lifecycle & Persistence

    public func loadInitialState() {
        loadState = .loading
        persistenceBannerError = nil
        do {
            let loaded = try store.loadState()
            state = loaded
            refreshLoadState()
        } catch {
            loadState = .error(error.localizedDescription)
        }
    }

    private func refreshLoadState() {
        if state.courses.isEmpty && state.tasks.isEmpty {
            loadState = .empty
        } else {
            loadState = .loaded
        }
    }

    private func persistCurrentState() {
        do {
            try store.saveState(state)
            persistenceBannerError = nil
            refreshLoadState()
        } catch {
            persistenceBannerError = error.localizedDescription
        }
    }

    // MARK: - RenWeb Temporary Email Link Import

    public func openImportSheet() {
        if case .success = importState {
            importState = .idle
            importURLInput = ""
        }
        isPresentingImportSheet = true
    }

    public func resetImportSheet() {
        importURLInput = ""
        importState = .idle
    }

    public func importFromRenWebLink() async {
        let raw = importURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            importState = .failure(RenWebError.invalidURL.localizedDescription)
            return
        }

        importState = .validating
        let validatedLink: ValidatedRenWebLink
        do {
            validatedLink = try RenWebLinkParser.parse(raw)
        } catch let error as RenWebError {
            importState = .failure(error.localizedDescription)
            return
        } catch {
            importState = .failure(RenWebError.invalidURL.localizedDescription)
            return
        }

        importState = .fetching(
            redactedURL: validatedLink.redactedDescription,
            district: validatedLink.district
        )

        do {
            let report = try await client.importReport(from: validatedLink)
            let updatedState = try store.applyImportedReport(report, from: validatedLink)
            state = updatedState
            refreshLoadState()
            let assignmentCount = report.courses.reduce(0) { $0 + $1.assignments.count }
            importState = .success(
                courseCount: report.courses.count,
                assignmentCount: assignmentCount,
                district: validatedLink.district
            )
            if selectedSection == nil || state.courses.isEmpty == false {
                selectedSection = .overview
            }
        } catch let error as RenWebError {
            importState = .failure(error.localizedDescription)
        } catch {
            importState = .failure(error.localizedDescription)
        }
    }

    // MARK: - Tasks & Assignment Mutations

    public func addTask(title: String, courseName: String, dueDate: Date?, notes: String?) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }
        let cleanCourse = courseName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)

        let task = TrackedTask(
            title: cleanTitle,
            courseName: cleanCourse.isEmpty ? "General" : cleanCourse,
            dueDate: dueDate,
            isCompleted: false,
            notes: (cleanNotes?.isEmpty == false) ? cleanNotes : nil
        )
        state.tasks.insert(task, at: 0)
        persistCurrentState()
    }

    public func toggleTaskCompletion(_ taskID: UUID) {
        guard let idx = state.tasks.firstIndex(where: { $0.id == taskID }) else { return }
        state.tasks[idx].isCompleted.toggle()
        persistCurrentState()
    }

    public func deleteTask(_ taskID: UUID) {
        state.tasks.removeAll { $0.id == taskID }
        persistCurrentState()
    }

    public func toggleAssignmentCompletion(courseID: UUID, assignmentID: UUID) {
        guard let cIdx = state.courses.firstIndex(where: { $0.id == courseID }),
              let aIdx = state.courses[cIdx].assignments.firstIndex(where: { $0.id == assignmentID })
        else { return }
        state.courses[cIdx].assignments[aIdx].isCompleted.toggle()
        persistCurrentState()
    }

    public func createFollowUpTask(from assignment: ImportedAssignment, courseName: String) {
        let task = TrackedTask(
            title: "Review: \(assignment.title)",
            courseName: courseName,
            dueDate: nil,
            isCompleted: false,
            notes: "Score: \(assignment.scoreDisplay) (\(assignment.category))"
        )
        state.tasks.insert(task, at: 0)
        persistCurrentState()
    }

    // MARK: - Formatting Helpers

    public static func letterGrade(for average: Double) -> String {
        switch average {
        case 97...: return "A+"
        case 93..<97: return "A"
        case 90..<93: return "A-"
        case 87..<90: return "B+"
        case 83..<87: return "B"
        case 80..<83: return "B-"
        case 77..<80: return "C+"
        case 73..<77: return "C"
        case 70..<73: return "C-"
        case 60..<70: return "D"
        default: return "F"
        }
    }

    public static func gradeColor(for average: Double?) -> Color {
        guard let average else { return .secondary }
        switch average {
        case 90...: return .green
        case 80..<90: return .blue
        case 70..<80: return .orange
        default: return .red
        }
    }
}
