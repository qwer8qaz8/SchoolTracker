import SwiftUI
import SchoolTrackerCore

struct CourseDetailView: View {
    let course: ImportedCourse
    @ObservedObject var viewModel: SchoolTrackerViewModel

    private var categoryNames: [String] {
        let fromBreakdown = course.categories.map(\.name)
        let fromAssignments = course.assignments.map(\.category)
        let unique = Array(Set(fromBreakdown + fromAssignments)).sorted()
        return ["All"] + unique
    }

    private var filteredAssignments: [ImportedAssignment] {
        let query = viewModel.courseAssignmentFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let activeCategory = categoryNames.contains(viewModel.courseSelectedCategory) ? viewModel.courseSelectedCategory : "All"
        return course.assignments.filter { item in
            if activeCategory != "All" && item.category != activeCategory {
                return false
            }
            guard !query.isEmpty else { return true }
            return item.title.lowercased().contains(query)
                || item.category.lowercased().contains(query)
                || (item.status?.lowercased().contains(query) ?? false)
                || (item.note?.lowercased().contains(query) ?? false)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                courseHeaderCard

                if !course.categories.isEmpty {
                    categoryBreakdownSection
                }

                assignmentsSection
            }
            .padding(24)
        }
        .navigationTitle(course.courseName)
    }

    private var courseHeaderCard: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(course.courseName)
                        .font(.title2.weight(.bold))
                    if let code = course.courseCode, !code.isEmpty {
                        Text(code)
                            .font(.caption.monospaced())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.quaternary, in: Capsule())
                    }
                }

                HStack(spacing: 16) {
                    if let teacher = course.teacherName, !teacher.isEmpty {
                        Label(teacher, systemImage: "person.fill")
                    }
                    if let term = course.term, !term.isEmpty {
                        Label("Term: \(term)", systemImage: "calendar")
                    }
                    Label("\(course.assignments.count) graded items", systemImage: "doc.text")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 10) {
                    if let letter = course.letterGrade, !letter.isEmpty {
                        Text(letter)
                            .font(.title2.weight(.bold))
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
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    } else {
                        Text("No Average")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }
                Text("Current Term Standing")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }

    private var categoryBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Category Weights & Averages")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                ForEach(course.categories) { category in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(category.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Spacer()
                            if let weight = category.weight {
                                Text(String(format: "%.0f%% wt", weight))
                                    .font(.caption2.monospacedDigit())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.quaternary, in: Capsule())
                            }
                        }

                        if let avg = category.average {
                            Text(String(format: "%.1f%%", avg))
                                .font(.title3.monospacedDigit().weight(.bold))
                                .foregroundStyle(SchoolTrackerViewModel.gradeColor(for: avg))
                        } else {
                            Text("No grades yet")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .background(.background, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(.quaternary, lineWidth: 1)
                    )
                }
            }
        }
    }

    private var assignmentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Assignments (\(filteredAssignments.count))")
                    .font(.headline)

                Spacer()

                if categoryNames.count > 2 {
                    Picker("Category", selection: $viewModel.courseSelectedCategory) {
                        ForEach(categoryNames, id: \.self) { category in
                            Text(category).tag(category)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 180)
                }

                TextField("Filter assignments…", text: $viewModel.courseAssignmentFilter)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
            }

            if course.assignments.isEmpty {
                ContentUnavailableView(
                    "No Assignments Recorded",
                    systemImage: "doc.plaintext",
                    description: Text("This course does not list any individual assignments in the latest report.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            } else if filteredAssignments.isEmpty {
                ContentUnavailableView.search(text: viewModel.courseAssignmentFilter)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
            } else {
                VStack(spacing: 8) {
                    ForEach(filteredAssignments) { assignment in
                        AssignmentRowView(
                            assignment: assignment,
                            onToggleComplete: {
                                viewModel.toggleAssignmentCompletion(
                                    courseID: course.id,
                                    assignmentID: assignment.id
                                )
                            },
                            onCreateFollowUp: {
                                viewModel.createFollowUpTask(
                                    from: assignment,
                                    courseName: course.courseName
                                )
                            }
                        )
                    }
                }
            }
        }
    }
}

private struct AssignmentRowView: View {
    let assignment: ImportedAssignment
    let onToggleComplete: () -> Void
    let onCreateFollowUp: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggleComplete) {
                Image(systemName: assignment.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(assignment.isCompleted ? .green : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .help("Toggle assignment completion status")

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(assignment.title)
                        .font(.body.weight(.medium))
                    Text(assignment.category)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                    if let status = assignment.status, !status.isEmpty {
                        Text(status)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }

                if let note = assignment.note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            if let due = assignment.dueDate, !due.isEmpty {
                Text(due)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .trailing, spacing: 2) {
                Text(assignment.scoreDisplay)
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                if let pct = assignment.percentage {
                    Text(String(format: "%.1f%%", pct))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(SchoolTrackerViewModel.gradeColor(for: pct))
                }
            }
            .frame(minWidth: 85, alignment: .trailing)

            Button(action: onCreateFollowUp) {
                Image(systemName: "plus.bubble")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Create a follow-up study task for this assignment")
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }
}
