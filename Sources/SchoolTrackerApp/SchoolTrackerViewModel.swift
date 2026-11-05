import Foundation
import SwiftUI
import SchoolTrackerCore

public enum SidebarSection: Hashable, Identifiable {
    case overview
    case gpa
    case history
    case tasks
    case calendar(FamilyPortalCalendarCategory)
    case course(UUID)

    public var id: String {
        switch self {
        case .overview:
            return "overview"
        case .gpa:
            return "gpa"
        case .history:
            return "history"
        case .tasks:
            return "tasks"
        case .calendar(let category):
            return "calendar-\(category.rawValue)"
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

public enum CalendarTimeFilter: String, CaseIterable, Identifiable {
    case upcoming = "Upcoming"
    case all = "All Events"
    case past = "Past"

    public var id: String { rawValue }
}

public enum CalendarDisplayMode: String, CaseIterable, Identifiable {
    case split = "Month & Agenda"
    case agenda = "Agenda List"

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
    @Published public var isPresentingCalendarSubscriptionSheet: Bool = false
    @Published public var isPresentingNewCalendarEventSheet: Bool = false
    @Published public var isPresentingTranscriptImportSheet: Bool = false
    @Published public var importURLInput: String = ""
    @Published public private(set) var importState: ImportSheetState = .idle
    @Published public private(set) var isSyncingSavedLink: Bool = false
    @Published public var persistenceBannerError: String?

    // Course Detail filter state
    @Published public var courseAssignmentFilter: String = ""
    @Published public var courseSelectedCategory: String = "All"

    // FLHS GPA Dashboard state
    @Published public var isShowingHandbookScale: Bool = false
    @Published public var isShowingSnapshotConfirmation: Bool = false
    @Published public var snapshotSuccessMessage: String?

    // Academic History view state
    @Published public var selectedHistorySnapshotID: UUID?
    @Published public var historySearchText: String = ""
    @Published public var historySelectedYearFilter: String = "All"
    @Published public var isShowingHistoryDeleteAlert: Bool = false
    @Published public var historySnapshotToDelete: TermSnapshot?
    @Published public var historyExportNotificationMessage: String?
    @Published public var isShowingHistoryExportNotification: Bool = false

    // Transcript Import Sheet state
    @Published public var transcriptImportState: TranscriptImportSheetState = .idle
    @Published public var isTargetedForTranscriptDrop: Bool = false
    @Published public var draftTranscriptSchoolYear: String = "2026-2027"
    @Published public var draftTranscriptTermName: String = "Semester 1"
    @Published public var draftTranscriptMergeCourses: Bool = true
    @Published public var draftTranscriptFilterNonHighSchool: Bool = false
    @Published public var draftTranscriptAdditionalSnapshots: [TermSnapshot] = []

    // New Task Sheet draft state
    @Published public var draftTaskTitle: String = ""
    @Published public var draftTaskCourseName: String = "General"
    @Published public var draftTaskIncludeDueDate: Bool = false
    @Published public var draftTaskDueDate: Date = Date().addingTimeInterval(86_400)
    @Published public var draftTaskNotes: String = ""
    @Published public var draftTaskValidationError: String?

    // Family Portal Calendar Subscription Sheet state
    @Published public var draftSelectedCalendars: Set<FamilyPortalCalendarCategory> = Set(FamilyPortalCalendarCategory.allCases)
    @Published public var draftCalendarFeedURLs: [FamilyPortalCalendarCategory: String] = [:]
    @Published public var calendarSubscriptionValidationError: String?
    @Published public private(set) var isSyncingCalendars: Bool = false
    @Published public var calendarSyncStatusMessage: String?

    // Family Portal Calendar Space state
    @Published public var calendarTimeFilter: CalendarTimeFilter = .all
    @Published public var calendarDisplayMode: CalendarDisplayMode = .split
    @Published public var calendarDisplayedMonth: Date = Date()
    @Published public var calendarSelectedDay: Date?
    @Published public var calendarSearchQuery: String = ""

    // New Calendar Event draft state
    @Published public var activeCalendarEventCategory: FamilyPortalCalendarCategory = .school
    @Published public var draftEventTitle: String = ""
    @Published public var draftEventCourseName: String = ""
    @Published public var draftEventStartDate: Date = Date()
    @Published public var draftEventIsAllDay: Bool = true
    @Published public var draftEventLocation: String = ""
    @Published public var draftEventNotes: String = ""
    @Published public var draftEventValidationError: String?

    private let store: SchoolTrackerStore
    private let client: RenWebClient

    public init(
        store: SchoolTrackerStore = SchoolTrackerStore(),
        client: RenWebClient = RenWebClient()
    ) {
        self.store = store
        self.client = client
    }

    // MARK: - Computed Summaries & Saved Link Expiration

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

    public var hasSavedLink: Bool {
        state.savedLink != nil
    }

    public var savedLinkExpirationStatus: SavedLinkExpirationStatus? {
        state.savedLink?.expirationStatus()
    }

    public var savedLinkExpirationSummary: String? {
        state.savedLink?.expirationSummaryText()
    }

    public var subscribedCalendarCategories: [FamilyPortalCalendarCategory] {
        state.subscribedCategories
    }

    public var totalSubscribedCalendarEventsCount: Int {
        subscribedCalendarCategories.reduce(0) { $0 + state.events(for: $1).count }
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
            draftSelectedCalendars = Set(loaded.subscribedCategories)
            refreshLoadState()
        } catch {
            loadState = .error(error.localizedDescription)
        }
    }

    private func refreshLoadState() {
        if state.courses.isEmpty && state.tasks.isEmpty && state.savedLink == nil && state.calendarEvents.isEmpty {
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
            SpotlightIndexManager.indexState(state)
        } catch {
            persistenceBannerError = error.localizedDescription
        }
    }

    // MARK: - FLHS GPA, Weight Tiers & Academic History

    public var gpaSummary: GPASummary {
        GPACalculator.calculateGPA(for: state.courses)
    }

    public func setCourseWeightTier(courseID: UUID, tier: CourseWeightTier?) {
        guard let idx = state.courses.firstIndex(where: { $0.id == courseID }) else { return }
        state.courses[idx].weightTier = tier
        persistCurrentState()
    }

    public func setCourseCountsTowardGraduation(courseID: UUID, counts: Bool) {
        guard let idx = state.courses.firstIndex(where: { $0.id == courseID }) else { return }
        state.courses[idx].countsTowardGraduation = counts
        persistCurrentState()
    }

    public func setCourseCountsTowardGPA(courseID: UUID, counts: Bool) {
        guard let idx = state.courses.firstIndex(where: { $0.id == courseID }) else { return }
        state.courses[idx].countsTowardGPA = counts
        persistCurrentState()
    }

    public func openTranscriptImportSheet() {
        isPresentingTranscriptImportSheet = true
    }

    @discardableResult
    public func snapshotCurrentTerm(termName: String? = nil, schoolYear: String? = nil) -> TermSnapshot {
        do {
            let snapshot = try store.snapshotCurrentTerm(termName: termName, schoolYear: schoolYear)
            state = try store.loadState()
            SpotlightIndexManager.indexState(state)
            return snapshot
        } catch {
            let fallbackSummary = GPACalculator.calculateGPA(for: state.courses)
            let fallbackSnapshot = TermSnapshot(
                schoolYear: schoolYear ?? "2026-2027",
                termName: termName ?? state.courses.compactMap(\.term).first ?? "Current Term",
                gpaSummary: fallbackSummary,
                courses: state.courses,
                source: "manual"
            )
            state.academicHistory.append(fallbackSnapshot)
            persistCurrentState()
            return fallbackSnapshot
        }
    }

    public func commitTranscriptSnapshot(_ snapshot: TermSnapshot, mergeIntoCurrentCourses: Bool) {
        do {
            for additional in draftTranscriptAdditionalSnapshots {
                if additional.schoolYear != snapshot.schoolYear || additional.termName != snapshot.termName {
                    _ = try store.applyTranscriptSnapshot(additional, mergeIntoCurrentCourses: false)
                }
            }
            state = try store.applyTranscriptSnapshot(snapshot, mergeIntoCurrentCourses: mergeIntoCurrentCourses)
            draftTranscriptAdditionalSnapshots = []
            refreshLoadState()
            SpotlightIndexManager.indexState(state)
        } catch {
            persistenceBannerError = "Failed to save transcript: \(error.localizedDescription)"
        }
    }

    public func deleteHistorySnapshot(id: UUID) {
        do {
            state = try store.deleteHistorySnapshot(id: id)
            SpotlightIndexManager.indexState(state)
        } catch {
            persistenceBannerError = "Failed to delete snapshot: \(error.localizedDescription)"
        }
    }

    public func exportHistoryJSON() -> String {
        (try? store.historyStore.exportJSON(snapshots: state.academicHistory))
            ?? (try? AcademicHistoryStore().exportJSON(snapshots: state.academicHistory))
            ?? "[]"
    }

    public func exportHistoryCSV() -> String {
        store.historyStore.exportCSV(snapshots: state.academicHistory)
    }

    public func exportHistoryMarkdown() -> String {
        store.historyStore.exportMarkdownTranscript(snapshots: state.academicHistory)
    }

    // MARK: - RenWeb Temporary Email Link Import & Saved Link Sync

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

        await performReportSync(using: validatedLink, updateSheetState: true)
    }

    public func syncSavedLink() async {
        guard !isSyncingSavedLink else { return }

        let savedCredential: ValidatedRenWebLink?
        do {
            savedCredential = try store.loadSavedRenWebLink()
        } catch {
            persistenceBannerError = error.localizedDescription
            if isPresentingImportSheet {
                importState = .failure(error.localizedDescription)
            }
            return
        }

        guard let validatedLink = savedCredential else {
            let message = "No saved RenWeb link is available. Paste a temporary report link to save it."
            persistenceBannerError = message
            if isPresentingImportSheet {
                importState = .failure(message)
            }
            return
        }

        isSyncingSavedLink = true
        defer { isSyncingSavedLink = false }

        await performReportSync(using: validatedLink, updateSheetState: isPresentingImportSheet)
    }

    public func clearSavedLink() {
        do {
            try store.clearSavedRenWebLink()
            state = try store.loadState()
            persistenceBannerError = nil
            if case .failure = importState {
                importState = .idle
            }
            refreshLoadState()
        } catch {
            persistenceBannerError = error.localizedDescription
        }
    }

    private func performReportSync(using validatedLink: ValidatedRenWebLink, updateSheetState: Bool) async {
        persistenceBannerError = nil
        if updateSheetState {
            importState = .fetching(
                redactedURL: validatedLink.redactedDescription,
                district: validatedLink.district
            )
        }

        do {
            let report = try await client.importReport(from: validatedLink)
            let updatedState = try store.applyImportedReport(report, from: validatedLink)
            state = updatedState
            refreshLoadState()
            let assignmentCount = report.courses.reduce(0) { $0 + $1.assignments.count }
            if updateSheetState {
                importState = .success(
                    courseCount: report.courses.count,
                    assignmentCount: assignmentCount,
                    district: validatedLink.district
                )
            }
            if selectedSection == nil {
                selectedSection = .overview
            } else if case .course(let selectedID) = selectedSection,
                      !state.courses.contains(where: { $0.id == selectedID }) {
                selectedSection = .overview
            }
        } catch let error as RenWebError {
            if error == .expiredOrInvalidSession {
                if let currentSaved = try? store.loadSavedRenWebLink(),
                   currentSaved.sessionID == validatedLink.sessionID {
                    if let updatedSaved = try? store.markSavedLinkExpired() {
                        state.savedLink = updatedSaved
                    }
                } else if state.savedLink != nil && !updateSheetState {
                    if let updatedSaved = try? store.markSavedLinkExpired() {
                        state.savedLink = updatedSaved
                    }
                }
            }
            if updateSheetState {
                importState = .failure(error.localizedDescription)
            } else {
                persistenceBannerError = error.localizedDescription
            }
        } catch {
            if updateSheetState {
                importState = .failure(error.localizedDescription)
            } else {
                persistenceBannerError = error.localizedDescription
            }
        }
    }

    // MARK: - Family Portal Calendar Subscriptions & Space Management

    public func openCalendarSubscriptionSheet() {
        let currentSubscribed = Set(state.subscribedCategories)
        draftSelectedCalendars = currentSubscribed.isEmpty
            ? Set(FamilyPortalCalendarCategory.allCases)
            : currentSubscribed
        draftCalendarFeedURLs = [:]
        calendarSubscriptionValidationError = nil
        calendarSyncStatusMessage = nil
        isPresentingCalendarSubscriptionSheet = true
    }

    public func isDraftCategorySelected(_ category: FamilyPortalCalendarCategory) -> Bool {
        draftSelectedCalendars.contains(category)
    }

    public func setDraftCategory(_ category: FamilyPortalCalendarCategory, isSelected: Bool) {
        if isSelected {
            draftSelectedCalendars.insert(category)
        } else {
            draftSelectedCalendars.remove(category)
        }
        if draftSelectedCalendars.isEmpty {
            calendarSubscriptionValidationError = FamilyPortalCalendarError.atLeastOneCategoryRequired.localizedDescription
        } else {
            calendarSubscriptionValidationError = nil
        }
    }

    public func draftFeedBinding(for category: FamilyPortalCalendarCategory) -> Binding<String> {
        Binding(
            get: { self.draftCalendarFeedURLs[category] ?? "" },
            set: { newValue in
                self.draftCalendarFeedURLs[category] = newValue
                if self.calendarSubscriptionValidationError != nil && !self.draftSelectedCalendars.isEmpty {
                    self.calendarSubscriptionValidationError = nil
                }
            }
        )
    }

    public func clearSavedCalendarFeed(for category: FamilyPortalCalendarCategory) {
        do {
            let currentCategories = Set(state.subscribedCategories.isEmpty ? [category] : state.subscribedCategories)
            state = try store.updateCalendarSubscriptions(
                selectedCategories: currentCategories,
                feedURLStrings: [category: ""]
            )
            draftCalendarFeedURLs[category] = ""
            calendarSubscriptionValidationError = nil
        } catch {
            calendarSubscriptionValidationError = error.localizedDescription
        }
    }

    @discardableResult
    public func saveCalendarSubscriptions(syncFeedsAfterSave: Bool = false) async -> Bool {
        guard !draftSelectedCalendars.isEmpty else {
            calendarSubscriptionValidationError = FamilyPortalCalendarError.atLeastOneCategoryRequired.localizedDescription
            return false
        }

        var nonEmptyFeedChanges: [FamilyPortalCalendarCategory: String] = [:]
        for (category, rawURL) in draftCalendarFeedURLs {
            let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                nonEmptyFeedChanges[category] = trimmed
            }
        }

        do {
            let updated = try store.updateCalendarSubscriptions(
                selectedCategories: draftSelectedCalendars,
                feedURLStrings: nonEmptyFeedChanges
            )
            state = updated
            calendarSubscriptionValidationError = nil
            refreshLoadState()

            if case .calendar(let activeCat) = selectedSection, !state.isSubscribed(to: activeCat) {
                if let firstSubscribed = state.subscribedCategories.first {
                    selectedSection = .calendar(firstSubscribed)
                } else {
                    selectedSection = .overview
                }
            }

            if syncFeedsAfterSave {
                await syncCalendarFeeds(for: nil)
            }
            return true
        } catch let error as FamilyPortalCalendarError {
            calendarSubscriptionValidationError = error.localizedDescription
            return false
        } catch {
            calendarSubscriptionValidationError = error.localizedDescription
            return false
        }
    }

    public func syncCalendarFeeds(for specificCategory: FamilyPortalCalendarCategory? = nil) async {
        guard !isSyncingCalendars else { return }
        let savedFeeds = (try? store.loadSavedCalendarFeedLinks()) ?? [:]
        let targetCategories: [FamilyPortalCalendarCategory]
        if let specificCategory {
            targetCategories = [specificCategory]
        } else {
            targetCategories = state.subscribedCategories
        }

        let categoriesWithFeeds = targetCategories.filter { savedFeeds[$0] != nil }
        guard !categoriesWithFeeds.isEmpty else {
            calendarSyncStatusMessage = "Subscribed spaces updated with local course and task events."
            return
        }

        isSyncingCalendars = true
        defer { isSyncingCalendars = false }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 15
        config.urlCache = nil
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }

        var syncedEventsTotal = 0
        for category in categoriesWithFeeds {
            guard let feedLink = savedFeeds[category] else { continue }
            do {
                let (data, response) = try await session.data(from: feedLink.url)
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    throw FamilyPortalCalendarError.networkFailure(statusCode: http.statusCode)
                }
                let ics = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1)
                    ?? ""
                let updated = try store.applyCalendarICS(ics, for: category)
                state = updated
                syncedEventsTotal += state.events(for: category).count
            } catch {
                persistenceBannerError = error.localizedDescription
                return
            }
        }

        refreshLoadState()
        calendarSyncStatusMessage = "Synced \(categoriesWithFeeds.count) calendar feed(s) (\(syncedEventsTotal) total events)."
    }

    public func openNewCalendarEventSheet(for category: FamilyPortalCalendarCategory) {
        activeCalendarEventCategory = category
        draftEventTitle = ""
        draftEventCourseName = category == .school ? "School" : (state.courses.first?.courseName ?? "")
        draftEventStartDate = calendarSelectedDay ?? Date()
        draftEventIsAllDay = true
        draftEventLocation = ""
        draftEventNotes = ""
        draftEventValidationError = nil
        isPresentingNewCalendarEventSheet = true
    }

    @discardableResult
    public func saveDraftCalendarEvent() -> Bool {
        let cleanTitle = draftEventTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else {
            draftEventValidationError = "Enter an event title."
            return false
        }
        let cleanCourse = draftEventCourseName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanLocation = draftEventLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNotes = draftEventNotes.trimmingCharacters(in: .whitespacesAndNewlines)

        let event = CalendarEvent(
            category: activeCalendarEventCategory,
            title: cleanTitle,
            courseName: cleanCourse.isEmpty ? nil : cleanCourse,
            startDate: draftEventStartDate,
            endDate: nil,
            isAllDay: draftEventIsAllDay,
            location: cleanLocation.isEmpty ? nil : cleanLocation,
            notes: cleanNotes.isEmpty ? nil : cleanNotes,
            source: .manual,
            isCompleted: false
        )

        do {
            state = try store.addCalendarEvent(event)
            draftEventValidationError = nil
            refreshLoadState()
            return true
        } catch {
            draftEventValidationError = error.localizedDescription
            return false
        }
    }

    public func toggleCalendarEventCompletion(_ event: CalendarEvent) {
        if state.calendarEvents.contains(where: { $0.id == event.id }) {
            do {
                state = try store.toggleCalendarEventCompletion(event.id)
                refreshLoadState()
            } catch {
                persistenceBannerError = error.localizedDescription
            }
            return
        }

        if state.tasks.contains(where: { $0.id == event.id }) {
            toggleTaskCompletion(event.id)
            return
        }

        for course in state.courses {
            if course.assignments.contains(where: { $0.id == event.id }) {
                toggleAssignmentCompletion(courseID: course.id, assignmentID: event.id)
                return
            }
        }
    }

    public func deleteCalendarEvent(_ event: CalendarEvent) {
        guard state.calendarEvents.contains(where: { $0.id == event.id }) else { return }
        do {
            state = try store.deleteCalendarEvent(event.id)
            refreshLoadState()
        } catch {
            persistenceBannerError = error.localizedDescription
        }
    }

    public func shiftDisplayedMonth(by offset: Int) {
        if let shifted = Calendar.current.date(byAdding: .month, value: offset, to: calendarDisplayedMonth) {
            calendarDisplayedMonth = shifted
            calendarSelectedDay = nil
        }
    }

    public func jumpToCurrentMonth() {
        calendarDisplayedMonth = Date()
        calendarSelectedDay = nil
    }

    public func filteredEvents(for category: FamilyPortalCalendarCategory) -> [CalendarEvent] {
        let allEvents = state.events(for: category)
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let query = calendarSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return allEvents.filter { event in
            if let selectedDay = calendarSelectedDay {
                if !Calendar.current.isDate(event.startDate, inSameDayAs: selectedDay) {
                    return false
                }
            } else {
                switch calendarTimeFilter {
                case .upcoming:
                    if event.startDate < startOfToday { return false }
                case .past:
                    if event.startDate >= startOfToday { return false }
                case .all:
                    break
                }
            }

            guard !query.isEmpty else { return true }
            return event.title.lowercased().contains(query)
                || (event.courseName?.lowercased().contains(query) ?? false)
                || (event.location?.lowercased().contains(query) ?? false)
                || (event.notes?.lowercased().contains(query) ?? false)
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
        RenWebReportParser.inferLetterGrade(for: average)
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

    public static func expirationStatusColor(for status: SavedLinkExpirationStatus?) -> Color {
        guard let status else { return .secondary }
        switch status {
        case .active:
            return .green
        case .expiringSoon:
            return .orange
        case .expired:
            return .red
        }
    }

    public static func expirationStatusIcon(for status: SavedLinkExpirationStatus?) -> String {
        guard let status else { return "link" }
        switch status {
        case .active:
            return "checkmark.seal.fill"
        case .expiringSoon:
            return "clock.badge.exclamationmark"
        case .expired:
            return "exclamationmark.triangle.fill"
        }
    }

    public static func calendarCategoryTint(for category: FamilyPortalCalendarCategory) -> Color {
        switch category {
        case .school:
            return .indigo
        case .classrooms:
            return .blue
        case .homework:
            return .teal
        }
    }
}
