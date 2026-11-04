import SwiftUI
import SchoolTrackerCore

struct RootSplitView: View {
    @ObservedObject var viewModel: SchoolTrackerViewModel

    var body: some View {
        NavigationSplitView {
            SidebarView(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
        } detail: {
            VStack(spacing: 0) {
                if let bannerError = viewModel.persistenceBannerError {
                    PersistenceErrorBanner(message: bannerError) {
                        viewModel.persistenceBannerError = nil
                    }
                }

                detailContent
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        viewModel.isPresentingNewTaskSheet = true
                    } label: {
                        Label("New Task", systemImage: "plus.circle")
                    }
                    .help("Add a study task or assignment reminder")

                    Button {
                        viewModel.openImportSheet()
                    } label: {
                        Label("Import RenWeb Link", systemImage: "link.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Import grades from a temporary FACTS/RenWeb GetReport.cfm email link")
                }
            }
        }
        .sheet(isPresented: $viewModel.isPresentingImportSheet) {
            RenWebImportSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.isPresentingNewTaskSheet) {
            NewTaskSheet(viewModel: viewModel)
        }
    }

    @ViewBuilder
    private var detailContent: some View {
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
                onCreateTask: { viewModel.isPresentingNewTaskSheet = true }
            )
        case .loaded:
            switch viewModel.selectedSection ?? .overview {
            case .overview:
                GradeSummaryView(viewModel: viewModel)
            case .tasks:
                TaskTrackerView(viewModel: viewModel)
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

private struct SidebarView: View {
    @ObservedObject var viewModel: SchoolTrackerViewModel

    var body: some View {
        List(selection: $viewModel.selectedSection) {
            Section("Dashboard") {
                NavigationLink(value: SidebarSection.overview) {
                    Label("Grade Summary", systemImage: "chart.bar.doc.horizontal")
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

            if let syncedAt = viewModel.state.lastSyncedAt {
                Section("Last Sync") {
                    VStack(alignment: .leading, spacing: 4) {
                        if let district = viewModel.state.lastSyncedDistrict {
                            Label("District: \(district)", systemImage: "building.columns")
                                .font(.caption.weight(.medium))
                        }
                        Text(syncedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .listStyle(.sidebar)
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
            Text("Reading courses and tasks from Application Support.")
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
    let onCreateTask: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "graduationcap.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.tint)

            VStack(spacing: 6) {
                Text("No Courses or Tasks Yet")
                    .font(.title2.weight(.semibold))
                Text("Paste a temporary FACTS/RenWeb GetReport.cfm email link to pull your current courses, category weights, and assignment grades, or add your first task manually.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
            }

            HStack(spacing: 12) {
                Button(action: onImportRenWeb) {
                    Label("Import RenWeb Email Link", systemImage: "link.badge.plus")
                }
                .buttonStyle(.borderedProminent)
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
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.octagon.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.callout)
                .lineLimit(2)
            Spacer()
            Button("Dismiss", action: onDismiss)
                .buttonStyle(.borderless)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.red.opacity(0.12))
    }
}
