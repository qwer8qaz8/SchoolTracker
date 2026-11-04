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

                if let redactedURL = viewModel.state.lastRedactedReportURL {
                    syncMetadataFooter(redactedURL: redactedURL)
                }
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
                    Text("Import a temporary FACTS/RenWeb email report link to populate live course grades.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
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
                    Text("Use 'Import RenWeb Link' in the toolbar to pull your latest course report.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Import RenWeb Link") {
                        viewModel.openImportSheet()
                    }
                    .buttonStyle(.borderedProminent)
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

    private func syncMetadataFooter(redactedURL: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield")
                .foregroundStyle(.secondary)
            Text("Redacted source: \(redactedURL)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
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
