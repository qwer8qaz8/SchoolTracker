import SwiftUI
import SchoolTrackerCore

struct GradeSummaryView: View {
    @ObservedObject var viewModel: SchoolTrackerViewModel

    private let metricColumns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection

                savedLinkStatusCard

                LazyVGrid(columns: metricColumns, spacing: 14) {
                    SummaryMetricCard(
                        title: "Overall Average",
                        value: viewModel.overallAverageText,
                        subtitle: viewModel.overallLetterGrade,
                        icon: "percent",
                        tint: SchoolTrackerViewModel.gradeColor(for: viewModel.state.overallAverage)
                    )
                    SummaryMetricCard(
                        title: "Active Courses",
                        value: "\(viewModel.state.courses.count)",
                        subtitle: viewModel.state.lastSyncedDistrict.map { "District \($0)" } ?? "Not synced",
                        icon: "books.vertical.fill",
                        tint: .blue
                    )
                    SummaryMetricCard(
                        title: "Graded Items",
                        value: "\(viewModel.totalAssignmentsCount)",
                        subtitle: "Across all courses",
                        icon: "doc.text.fill",
                        tint: .indigo
                    )
                    SummaryMetricCard(
                        title: "Pending Tasks",
                        value: "\(viewModel.pendingTasksCount)",
                        subtitle: "\(viewModel.state.tasks.count) total tracked",
                        icon: "checklist",
                        tint: viewModel.pendingTasksCount > 0 ? .orange : .green
                    )
                }

                coursesSection

                calendarSpacesSection
            }
            .padding(24)
        }
        .navigationTitle("Grade Summary")
    }

    private var headerSection: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Academic Overview")
                    .font(.title2.weight(.bold))
                if let syncedAt = viewModel.state.lastSyncedAt {
                    Text("Last updated from RenWeb on \(syncedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Save a temporary FACTS/RenWeb email report link to pull live course grades and track link expiry.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var savedLinkStatusCard: some View {
        if let savedLink = viewModel.state.savedLink {
            let status = savedLink.expirationStatus()
            let statusColor = SchoolTrackerViewModel.expirationStatusColor(for: status)
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: SchoolTrackerViewModel.expirationStatusIcon(for: status))
                    .font(.title2)
                    .foregroundStyle(statusColor)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Saved RenWeb Report Link (\(savedLink.district))")
                            .font(.subheadline.weight(.semibold))
                        Text(savedLink.expirationSummaryText())
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(statusColor.opacity(0.15), in: Capsule())
                            .foregroundStyle(statusColor)
                    }

                    Text("Redacted URL: \(savedLink.redactedURL) · Saved \(savedLink.savedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        Task {
                            await viewModel.syncSavedLink()
                        }
                    } label: {
                        if viewModel.isSyncingSavedLink {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Syncing…")
                            }
                        } else {
                            Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(viewModel.isSyncingSavedLink)

                    Button(status.isExpired ? "Replace Link…" : "Manage…") {
                        viewModel.openImportSheet()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button(role: .destructive) {
                        viewModel.clearSavedLink()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove saved RenWeb link from this Mac")
                }
            }
            .padding(14)
            .background(statusColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(statusColor.opacity(0.3), lineWidth: 1)
            )
        } else {
            HStack(spacing: 12) {
                Image(systemName: "link.badge.plus")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("No RenWeb Report Link Saved")
                        .font(.subheadline.weight(.semibold))
                    Text("Save a temporary GetReport.cfm email link to see its 14-day expiration countdown and refresh grades in one click.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Save Link…") {
                    viewModel.openImportSheet()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(14)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private var coursesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Course Standings")
                .font(.headline)

            if viewModel.state.courses.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text("No courses imported yet")
                        .font(.subheadline.weight(.medium))
                    Text("Sync your saved RenWeb link or paste a fresh temporary report link to load course grades.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        if viewModel.hasSavedLink {
                            Button("Sync Saved Link") {
                                Task {
                                    await viewModel.syncSavedLink()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(viewModel.isSyncingSavedLink)
                        }
                        Button(viewModel.hasSavedLink ? "Replace Link…" : "Import RenWeb Link") {
                            viewModel.openImportSheet()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(28)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
            } else {
                VStack(spacing: 10) {
                    ForEach(viewModel.state.courses) { course in
                        Button {
                            viewModel.selectedSection = .course(course.id)
                        } label: {
                            CourseOverviewCard(course: course)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var calendarSpacesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Family Portal Calendar Spaces")
                    .font(.headline)
                Spacer()
                Button("Subscribe to Calendars…") {
                    viewModel.openCalendarSubscriptionSheet()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                ForEach(viewModel.subscribedCalendarCategories) { category in
                    let tint = SchoolTrackerViewModel.calendarCategoryTint(for: category)
                    let count = viewModel.state.events(for: category).count
                    Button {
                        viewModel.selectedSection = .calendar(category)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: category.systemImage)
                                .font(.title3)
                                .foregroundStyle(tint)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(category.displayName)
                                    .font(.subheadline.weight(.semibold))
                                Text("\(count) event\(count == 1 ? "" : "s") in space")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(14)
                        .background(.background, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(tint.opacity(0.28), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct SummaryMetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: icon)
                    .foregroundStyle(tint)
            }
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }
}

private struct CourseOverviewCard: View {
    let course: ImportedCourse

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(course.courseName)
                        .font(.headline)
                    if let code = course.courseCode, !code.isEmpty {
                        Text(code)
                            .font(.caption2.monospaced())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }

                HStack(spacing: 12) {
                    if let teacher = course.teacherName, !teacher.isEmpty {
                        Label(teacher, systemImage: "person")
                    }
                    if let term = course.term, !term.isEmpty {
                        Label(term, systemImage: "calendar")
                    }
                    Label("\(course.assignments.count) assignments", systemImage: "list.bullet.rectangle")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 12) {
                if let letter = course.letterGrade, !letter.isEmpty {
                    Text(letter)
                        .font(.title3.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            SchoolTrackerViewModel.gradeColor(for: course.numericAverage).opacity(0.15),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                        .foregroundStyle(SchoolTrackerViewModel.gradeColor(for: course.numericAverage))
                }

                if let avg = course.numericAverage {
                    Text(String(format: "%.1f%%", avg))
                        .font(.title3.monospacedDigit().weight(.semibold))
                } else {
                    Text("N/A")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }
}
