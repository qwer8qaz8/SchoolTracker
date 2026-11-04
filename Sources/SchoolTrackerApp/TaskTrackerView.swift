import SwiftUI
import SchoolTrackerCore

struct TaskTrackerView: View {
    @ObservedObject var viewModel: SchoolTrackerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            filterToolbar

            if viewModel.state.tasks.isEmpty {
                ContentUnavailableView {
                    Label("No Study Tasks Yet", systemImage: "checklist")
                } description: {
                    Text("Track upcoming homework, exam prep, or grade follow-ups alongside your RenWeb courses.")
                } actions: {
                    Button("New Task") {
                        viewModel.isPresentingNewTaskSheet = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.filteredTasks.isEmpty {
                ContentUnavailableView(
                    "No Matching Tasks",
                    systemImage: "magnifyingglass",
                    description: Text("No tasks match the current filter or search query.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(viewModel.filteredTasks) { task in
                            TaskRowView(
                                task: task,
                                onToggle: { viewModel.toggleTaskCompletion(task.id) },
                                onDelete: { viewModel.deleteTask(task.id) }
                            )
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
        }
        .navigationTitle("Task Tracker")
    }

    private var filterToolbar: some View {
        HStack(spacing: 12) {
            Picker("Status", selection: $viewModel.taskFilter) {
                ForEach(TaskFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 260)

            Spacer()

            TextField("Search tasks or course…", text: $viewModel.searchQuery)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)

            Button {
                viewModel.isPresentingNewTaskSheet = true
            } label: {
                Label("Add Task", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
    }
}

private struct TaskRowView: View {
    let task: TrackedTask
    let onToggle: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(task.title)
                        .font(.body.weight(.medium))
                        .strikethrough(task.isCompleted)
                        .foregroundStyle(task.isCompleted ? .secondary : .primary)

                    Text(task.courseName)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                }

                if let notes = task.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let dueDate = task.dueDate {
                Label(
                    dueDate.formatted(date: .abbreviated, time: .omitted),
                    systemImage: "calendar"
                )
                .font(.caption)
                .foregroundStyle(dueDate < Date() && !task.isCompleted ? .red : .secondary)
            }

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Delete task")
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }
}

struct NewTaskSheet: View {
    @ObservedObject var viewModel: SchoolTrackerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("New Study Task")
                .font(.title3.weight(.bold))

            Form {
                TextField("Task Title", text: $viewModel.draftTaskTitle, prompt: Text("e.g., Complete Chapter 5 Problem Set"))

                if viewModel.state.courses.isEmpty {
                    TextField("Course Name", text: $viewModel.draftTaskCourseName, prompt: Text("e.g., AP Calculus BC"))
                } else {
                    Picker("Course", selection: $viewModel.draftTaskCourseName) {
                        Text("General").tag("General")
                        ForEach(viewModel.state.courses) { course in
                            Text(course.courseName).tag(course.courseName)
                        }
                    }
                }

                Toggle("Include Due Date", isOn: $viewModel.draftTaskIncludeDueDate)
                if viewModel.draftTaskIncludeDueDate {
                    DatePicker("Due Date", selection: $viewModel.draftTaskDueDate, displayedComponents: [.date])
                }

                TextField("Notes (Optional)", text: $viewModel.draftTaskNotes, axis: .vertical)
                    .lineLimit(2...4)
            }
            .formStyle(.grouped)

            if let validationError = viewModel.draftTaskValidationError {
                Label(validationError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save Task") {
                    let trimmed = viewModel.draftTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else {
                        viewModel.draftTaskValidationError = "Enter a title for the task."
                        return
                    }
                    viewModel.addTask(
                        title: trimmed,
                        courseName: viewModel.draftTaskCourseName.isEmpty ? "General" : viewModel.draftTaskCourseName,
                        dueDate: viewModel.draftTaskIncludeDueDate ? viewModel.draftTaskDueDate : nil,
                        notes: viewModel.draftTaskNotes
                    )
                    viewModel.draftTaskTitle = ""
                    viewModel.draftTaskNotes = ""
                    viewModel.draftTaskValidationError = nil
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
        .onAppear {
            viewModel.draftTaskValidationError = nil
            if viewModel.draftTaskCourseName.isEmpty {
                viewModel.draftTaskCourseName = viewModel.state.courses.first?.courseName ?? "General"
            }
        }
    }
}
