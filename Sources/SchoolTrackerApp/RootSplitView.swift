import SwiftUI
import SchoolTrackerCore

struct RootSplitView: View {
    @ObservedObject var viewModel: SchoolTrackerViewModel

    var body: some View {
        NavigationSplitView {
            SidebarView(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 225, ideal: 260, max: 340)
        } detail: {
            VStack(spacing: 0) {
                if let bannerError = viewModel.persistenceBannerError {
                    PersistenceErrorBanner(
                        message: bannerError,
                        showReplaceLinkAction: viewModel.savedLinkExpirationStatus?.isExpired == true,
                        onReplaceLink: {
                            viewModel.persistenceBannerError = nil
                            viewModel.openImportSheet()
                        },
                        onDismiss: {
                            viewModel.persistenceBannerError = nil
                        }
                    )
                }

                detailContent
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        viewModel.openTranscriptImportSheet()
                    } label: {
                        Label("Import Transcript", systemImage: "doc.text.viewfinder")
                    }
                    .help("Import a PDF report card or scanned transcript via on-device Apple Intelligence OCR")

                    Button {
                        viewModel.openCalendarSubscriptionSheet()
                    } label: {
                        Label("Calendars", systemImage: "calendar.badge.plus")
                    }
                    .help("Subscribe to Family Portal Calendars (School, My Classrooms, My Homework)")

                    Button {
                        viewModel.isPresentingNewTaskSheet = true
                    } label: {
                        Label("New Task", systemImage: "plus.circle")
                    }
                    .help("Add a study task or assignment reminder")

                    if viewModel.hasSavedLink {
                        Button {
                            Task {
                                await viewModel.syncSavedLink()
                            }
                        } label: {
                            if viewModel.isSyncingSavedLink {
                                Label("Syncing…", systemImage: "arrow.triangle.2.circlepath")
                            } else {
                                Label("Sync Saved Link", systemImage: "arrow.triangle.2.circlepath")
                            }
                        }
                        .disabled(viewModel.isSyncingSavedLink)
                        .help("Fetch the latest grades using your saved FACTS/RenWeb link (⌘R)")
                    }

                    Button {
                        viewModel.openImportSheet()
                    } label: {
                        Label(
                            viewModel.hasSavedLink ? "Saved Link…" : "Import RenWeb Link",
                            systemImage: viewModel.hasSavedLink ? "link.circle.fill" : "link.badge.plus"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Save, replace, or inspect your temporary FACTS/RenWeb GetReport.cfm email link")
                }
            }
        }
        .sheet(isPresented: $viewModel.isPresentingImportSheet) {
            RenWebImportSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.isPresentingNewTaskSheet) {
            NewTaskSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.isPresentingCalendarSubscriptionSheet) {
            CalendarSubscriptionSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.isPresentingNewCalendarEventSheet) {
            NewCalendarEventSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.isPresentingTranscriptImportSheet) {
            TranscriptImportSheet(viewModel: viewModel)
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        if case .calendar(let category) = viewModel.selectedSection {
            CalendarCategorySpaceView(category: category, viewModel: viewModel)
        } else {
            switch viewModel.loadState {
            case .loading:
                AppLoadingStateView()
            case .error(let message):
                AppErrorStateView(
                    message: message,
                    onRetry: { viewModel.loadInitialState() },
                    onImport: { viewModel.openImportSheet() }
                )
            case .empty:
                AppEmptyStateView(
                    onImportRenWeb: { viewModel.openImportSheet() },
                    onSubscribeCalendars: { viewModel.openCalendarSubscriptionSheet() },
                    onCreateTask: { viewModel.isPresentingNewTaskSheet = true }
                )
            case .loaded:
                switch viewModel.selectedSection ?? .overview {
                case .overview:
                    GradeSummaryView(viewModel: viewModel)
                case .gpa:
                    GPADashboardView(viewModel: viewModel)
                case .history:
                    AcademicHistoryView(viewModel: viewModel)
                case .tasks:
                    TaskTrackerView(viewModel: viewModel)
                case .calendar(let category):
                    CalendarCategorySpaceView(category: category, viewModel: viewModel)
                case .course(let courseID):
                    if let course = viewModel.course(for: courseID) {
                        CourseDetailView(course: course, viewModel: viewModel)
                    } else {
                        ContentUnavailableView(
                            "Course Not Found",
                            systemImage: "book.closed",
                            description: Text("This course is no longer in the current report.")
                        )
                    }
                }
            }
        }
    }
}

private struct SidebarView: View {
    @ObservedObject var viewModel: SchoolTrackerViewModel

    var body: some View {
        List(selection: $viewModel.selectedSection) {
            Section("Academic Standing") {
                NavigationLink(value: SidebarSection.overview) {
                    Label("Grade Summary", systemImage: "chart.bar.doc.horizontal")
                }

                NavigationLink(value: SidebarSection.gpa) {
                    HStack {
                        Label("FLHS GPA & Credits", systemImage: "graduationcap.fill")
                        Spacer()
                        Text(String(format: "%.2f", viewModel.gpaSummary.weightedGPA))
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(Capsule())
                    }
                }

                NavigationLink(value: SidebarSection.history) {
                    HStack {
                        Label("Academic History", systemImage: "clock.arrow.circlepath")
                        Spacer()
                        if !viewModel.state.academicHistory.isEmpty {
                            Text("\(viewModel.state.academicHistory.count)")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.15))
                                .foregroundStyle(.secondary)
                                .clipShape(Capsule())
                        }
                    }
                }

                NavigationLink(value: SidebarSection.tasks) {
                    HStack {
                        Label("Task Tracker", systemImage: "checklist")
                        Spacer()
                        if viewModel.pendingTasksCount > 0 {
                            Text("\(viewModel.pendingTasksCount)")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.15))
                                .foregroundStyle(Color.accentColor)
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            Section("Family Portal Calendars") {
                ForEach(viewModel.subscribedCalendarCategories) { category in
                    NavigationLink(value: SidebarSection.calendar(category)) {
                        SidebarCalendarCategoryRow(
                            category: category,
                            eventCount: viewModel.state.events(for: category).count
                        )
                    }
                }

                Button {
                    viewModel.openCalendarSubscriptionSheet()
                } label: {
                    Label("Subscribe to Calendars…", systemImage: "calendar.badge.plus")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.borderless)
                .padding(.top, 2)
            }

            Section("Courses (\(viewModel.state.courses.count))") {
                if viewModel.state.courses.isEmpty {
                    Text("No courses imported yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(viewModel.state.courses) { course in
                        NavigationLink(value: SidebarSection.course(course.id)) {
                            SidebarCourseRow(course: course)
                        }
                    }
                }
            }

            Section("Saved Report Link") {
                if let savedLink = viewModel.state.savedLink {
                    let status = savedLink.expirationStatus()
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: SchoolTrackerViewModel.expirationStatusIcon(for: status))
                                .foregroundStyle(SchoolTrackerViewModel.expirationStatusColor(for: status))
                            Text("District: \(savedLink.district)")
                                .font(.caption.weight(.semibold))
                        }

                        Text(savedLink.expirationSummaryText())
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(SchoolTrackerViewModel.expirationStatusColor(for: status))

                        if let syncedAt = viewModel.state.lastSyncedAt {
                            Text("Synced \(syncedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 8) {
                            Button {
                                Task {
                                    await viewModel.syncSavedLink()
                                }
                            } label: {
                                Text(viewModel.isSyncingSavedLink ? "Syncing…" : "Sync Now")
                                    .font(.caption2.weight(.semibold))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            .disabled(viewModel.isSyncingSavedLink)

                            Button {
                                viewModel.openImportSheet()
                            } label: {
                                Text(status.isExpired ? "Replace" : "Manage")
                                    .font(.caption2)
                            }
                            .buttonStyle(.borderless)
                            .controlSize(.mini)
                        }
                        .padding(.top, 2)
                    }
                    .padding(.vertical, 4)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No link saved")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Button("Save RenWeb Link…") {
                            viewModel.openImportSheet()
                        }
                        .buttonStyle(.borderless)
                        .font(.caption2)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .listStyle(.sidebar)
    }
}

private struct SidebarCalendarCategoryRow: View {
    let category: FamilyPortalCalendarCategory
    let eventCount: Int

    var body: some View {
        let tint = SchoolTrackerViewModel.calendarCategoryTint(for: category)
        HStack(spacing: 8) {
            Image(systemName: category.systemImage)
                .foregroundStyle(tint)
            Text(category.displayName)
                .lineLimit(1)
            Spacer()
            if eventCount > 0 {
                Text("\(eventCount)")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(tint.opacity(0.15), in: Capsule())
                    .foregroundStyle(tint)
            }
        }
    }
}

private struct SidebarCourseRow: View {
    let course: ImportedCourse

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "book.closed")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(course.courseName)
                    .lineLimit(1)
                if let teacher = course.teacherName, !teacher.isEmpty {
                    Text(teacher)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if let avg = course.numericAverage {
                Text(String(format: "%.0f%%", avg))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(SchoolTrackerViewModel.gradeColor(for: avg))
            } else if let letter = course.letterGrade {
                Text(letter)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct AppLoadingStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("Loading local school tracker state…")
                .font(.headline)
            Text("Reading courses, tasks, calendar spaces, and saved link metadata from Application Support.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(32)
    }
}

private struct AppErrorStateView: View {
    let message: String
    let onRetry: () -> Void
    let onImport: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)

            Text("Could Not Load Local Tracker State")
                .font(.title3.weight(.semibold))

            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)

            HStack(spacing: 12) {
                Button("Retry Load", action: onRetry)
                    .buttonStyle(.borderedProminent)
                Button("Import Fresh RenWeb Link", action: onImport)
                    .buttonStyle(.bordered)
            }
        }
        .padding(32)
    }
}

private struct AppEmptyStateView: View {
    let onImportRenWeb: () -> Void
    let onSubscribeCalendars: () -> Void
    let onCreateTask: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "graduationcap.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.tint)

            VStack(spacing: 6) {
                Text("No Courses or Tasks Yet")
                    .font(.title2.weight(.semibold))
                Text("Paste a temporary FACTS/RenWeb GetReport.cfm email link to save it in the app, track when it expires, and pull your current grades, or configure your Family Portal Calendar spaces.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 500)
            }

            HStack(spacing: 12) {
                Button(action: onImportRenWeb) {
                    Label("Save & Import RenWeb Link", systemImage: "link.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(action: onSubscribeCalendars) {
                    Label("Subscribe to Calendars", systemImage: "calendar.badge.plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button(action: onCreateTask) {
                    Label("Add Study Task", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .padding(40)
    }
}

private struct PersistenceErrorBanner: View {
    let message: String
    let showReplaceLinkAction: Bool
    let onReplaceLink: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.octagon.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.callout)
                .lineLimit(2)
            Spacer()
            if showReplaceLinkAction {
                Button("Replace Expired Link…", action: onReplaceLink)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            Button("Dismiss", action: onDismiss)
                .buttonStyle(.borderless)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.red.opacity(0.12))
    }
}
