import SwiftUI
import AppKit
import UniformTypeIdentifiers
import SchoolTrackerCore

public struct AcademicHistoryView: View {
    @ObservedObject var viewModel: SchoolTrackerViewModel

    public init(viewModel: SchoolTrackerViewModel) {
        self.viewModel = viewModel
    }

    private var snapshots: [TermSnapshot] {
        viewModel.state.academicHistory
    }

    private var availableSchoolYears: [String] {
        let years = Array(Set(snapshots.map(\.schoolYear))).sorted().reversed()
        return ["All"] + years
    }

    private var filteredSnapshots: [TermSnapshot] {
        snapshots.filter { snapshot in
            let matchesYear = (viewModel.historySelectedYearFilter == "All" || snapshot.schoolYear == viewModel.historySelectedYearFilter)
            let matchesSearch = viewModel.historySearchText.isEmpty
                || snapshot.termName.localizedCaseInsensitiveContains(viewModel.historySearchText)
                || snapshot.schoolYear.localizedCaseInsensitiveContains(viewModel.historySearchText)
                || snapshot.courses.contains { $0.courseName.localizedCaseInsensitiveContains(viewModel.historySearchText) }
            return matchesYear && matchesSearch
        }.sorted { $0.syncedAt > $1.syncedAt }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerView

                if snapshots.isEmpty {
                    emptyStateView
                } else {
                    filterBar
                    historyTimelineView
                }
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("Delete Snapshot?", isPresented: $viewModel.isShowingHistoryDeleteAlert, presenting: viewModel.historySnapshotToDelete) { snapshot in
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                viewModel.deleteHistorySnapshot(id: snapshot.id)
            }
        } message: { snapshot in
            Text("Are you sure you want to delete the archived snapshot for \(snapshot.termName) (\(snapshot.schoolYear))? This cannot be undone.")
        }
        .alert("Export Ready", isPresented: $viewModel.isShowingHistoryExportNotification) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.historyExportNotificationMessage ?? "Export file generated successfully.")
        }
    }

    // MARK: - Header & Export Actions

    private var headerView: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("Academic History & Archival")
                        .font(.title2.weight(.bold))
                    LiquidGlassBadge("Persistent", systemImage: "archivebox.fill", tint: .blue)
                }
                Text("Permanent multi-quarter and multi-year record. Persists even when temporary RenWeb links expire.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Menu {
                Button {
                    exportFile(format: .markdown)
                } label: {
                    Label("Export Markdown Transcript (.md)", systemImage: "doc.richtext")
                }

                Button {
                    exportFile(format: .csv)
                } label: {
                    Label("Export Spreadsheet CSV (.csv)", systemImage: "tablecells")
                }

                Button {
                    exportFile(format: .json)
                } label: {
                    Label("Export Raw JSON (.json)", systemImage: "curlybraces")
                }

                Divider()

                Button {
                    copyToClipboard(format: .markdown)
                } label: {
                    Label("Copy Markdown to Clipboard", systemImage: "doc.on.clipboard")
                }
            } label: {
                Label("Export History…", systemImage: "square.and.arrow.up")
            }
            .menuStyle(.borderedButton)
            .disabled(snapshots.isEmpty)

            Button {
                _ = viewModel.snapshotCurrentTerm()
                viewModel.historyExportNotificationMessage = "Successfully froze current report grades into a new term snapshot."
                viewModel.isShowingHistoryExportNotification = true
            } label: {
                Label("Snapshot Current Report", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.state.courses.isEmpty)
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search terms, years, or courses…", text: $viewModel.historySearchText)
                    .textFieldStyle(.plain)
                if !viewModel.historySearchText.isEmpty {
                    Button {
                        viewModel.historySearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .frame(maxWidth: 320)

            Spacer()

            Picker("School Year", selection: $viewModel.historySelectedYearFilter) {
                ForEach(availableSchoolYears, id: \.self) { year in
                    Text(year).tag(year)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 150)

            Text("\(filteredSnapshots.count) snapshot\(filteredSnapshots.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Timeline & Snapshot Cards

    private var historyTimelineView: some View {
        VStack(spacing: 14) {
            ForEach(filteredSnapshots) { snapshot in
                snapshotCard(snapshot)
            }
        }
    }

    private func snapshotCard(_ snapshot: TermSnapshot) -> some View {
        let isExpanded = (viewModel.selectedHistorySnapshotID == snapshot.id)

        return LiquidGlassCard(cornerRadius: 12) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(snapshot.termName)
                                .font(.title3.weight(.bold))
                            Text(snapshot.schoolYear)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.accentColor)

                            sourceBadge(snapshot.source)
                        }

                        Text("Archived on \(snapshot.syncedAt.formatted(date: .abbreviated, time: .shortened)) • \(snapshot.courses.count) courses")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    HStack(spacing: 16) {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Weighted GPA")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.2f", snapshot.gpaSummary.weightedGPA))
                                .font(.title3.weight(.bold))
                                .foregroundStyle(Color.accentColor)
                        }

                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Unweighted GPA")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.2f", snapshot.gpaSummary.unweightedGPA))
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.teal)
                        }

                        if snapshot.gpaSummary.honorRollStatus != .none {
                            LiquidGlassBadge(
                                snapshot.gpaSummary.honorRollStatus.rawValue,
                                systemImage: "medal.fill",
                                tint: .orange
                            )
                        }

                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                if viewModel.selectedHistorySnapshotID == snapshot.id {
                                    viewModel.selectedHistorySnapshotID = nil
                                } else {
                                    viewModel.selectedHistorySnapshotID = snapshot.id
                                }
                            }
                        } label: {
                            Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)

                        Menu {
                            Button("Copy Term Markdown") {
                                copySnapshotMarkdown(snapshot)
                            }
                            Divider()
                            Button("Delete Snapshot…", role: .destructive) {
                                viewModel.historySnapshotToDelete = snapshot
                                viewModel.isShowingHistoryDeleteAlert = true
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                        .menuStyle(.borderlessButton)
                    }
                }

                // Expanded Courses Detail
                if isExpanded {
                    Divider()
                        .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Archived Course Grades")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)

                        ForEach(snapshot.courses) { course in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(course.courseName)
                                            .font(.subheadline.weight(.semibold))
                                        if let code = course.courseCode {
                                            Text(code)
                                                .font(.caption2)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(Color.secondary.opacity(0.12))
                                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                        }
                                        LiquidGlassBadge(course.effectiveWeightTier.displayName, tint: tierColor(course.effectiveWeightTier))
                                    }
                                    if let teacher = course.teacherName {
                                        Text(teacher)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                if let score = course.numericAverage {
                                    let weightedPts = GPACalculator.weightedPoints(for: score, tier: course.effectiveWeightTier)
                                    HStack(spacing: 8) {
                                        Text(String(format: "%.1f%%", score))
                                            .font(.subheadline.weight(.bold))
                                            .foregroundStyle(SchoolTrackerViewModel.gradeColor(for: score))

                                        if let letter = course.letterGrade {
                                            Text(letter)
                                                .font(.caption.weight(.bold))
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(SchoolTrackerViewModel.gradeColor(for: score).opacity(0.15))
                                                .foregroundStyle(SchoolTrackerViewModel.gradeColor(for: score))
                                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                        }

                                        Text("\(String(format: "%.2f", weightedPts)) pts")
                                            .font(.caption2.weight(.medium))
                                            .foregroundStyle(.secondary)
                                    }
                                } else {
                                    Text("No Grade")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 3)

                            if course.id != snapshot.courses.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }

    private func sourceBadge(_ source: String) -> some View {
        switch source.lowercased() {
        case "renweb":
            return LiquidGlassBadge("RenWeb", systemImage: "link", tint: .indigo)
        case "transcript_pdf":
            return LiquidGlassBadge("Apple Intelligence OCR", systemImage: "sparkles", tint: .teal)
        case "transcript_ocr":
            return LiquidGlassBadge("Vision OCR", systemImage: "camera", tint: .teal)
        default:
            return LiquidGlassBadge("Snapshot", systemImage: "camera.badge.ellipsis", tint: .secondary)
        }
    }

    private func tierColor(_ tier: CourseWeightTier) -> Color {
        switch tier {
        case .regular:
            return .secondary
        case .honors:
            return .blue
        case .advancedHonorsDualCredit:
            return .purple
        }
    }

    // MARK: - Export Helpers

    public enum ExportFormat {
        case json, csv, markdown
    }

    private func exportFile(format: ExportFormat) {
        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true

        let defaultFilename: String
        let content: String
        switch format {
        case .json:
            defaultFilename = "SchoolTracker-AcademicHistory.json"
            savePanel.allowedContentTypes = [UTType.json]
            content = viewModel.exportHistoryJSON()
        case .csv:
            defaultFilename = "SchoolTracker-AcademicHistory.csv"
            savePanel.allowedContentTypes = [UTType.commaSeparatedText]
            content = viewModel.exportHistoryCSV()
        case .markdown:
            defaultFilename = "SchoolTracker-Transcript.md"
            savePanel.allowedContentTypes = [UTType.plainText]
            content = viewModel.exportHistoryMarkdown()
        }

        savePanel.nameFieldStringValue = defaultFilename
        savePanel.begin { response in
            if response == .OK, let targetURL = savePanel.url {
                do {
                    try content.write(to: targetURL, atomically: true, encoding: .utf8)
                    viewModel.historyExportNotificationMessage = "Saved export file to: \(targetURL.lastPathComponent)"
                    viewModel.isShowingHistoryExportNotification = true
                } catch {
                    viewModel.historyExportNotificationMessage = "Failed to save export: \(error.localizedDescription)"
                    viewModel.isShowingHistoryExportNotification = true
                }
            }
        }
    }

    private func copyToClipboard(format: ExportFormat) {
        let text: String
        switch format {
        case .json:
            text = viewModel.exportHistoryJSON()
        case .csv:
            text = viewModel.exportHistoryCSV()
        case .markdown:
            text = viewModel.exportHistoryMarkdown()
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        viewModel.historyExportNotificationMessage = "Copied academic transcript markdown to clipboard."
        viewModel.isShowingHistoryExportNotification = true
    }

    private func copySnapshotMarkdown(_ snapshot: TermSnapshot) {
        let text = AcademicHistoryStore().exportMarkdownTranscript(snapshots: [snapshot])
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        viewModel.historyExportNotificationMessage = "Copied \(snapshot.termName) markdown to clipboard."
        viewModel.isShowingHistoryExportNotification = true
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Academic Snapshots Recorded")
                .font(.headline)
            Text("Archived snapshots preserve your historical courses and GPAs across quarter boundaries, even after temporary RenWeb email links expire.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)

            HStack(spacing: 12) {
                if !viewModel.state.courses.isEmpty {
                    Button {
                        _ = viewModel.snapshotCurrentTerm()
                    } label: {
                        Label("Archive Current Courses Now", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button {
                    viewModel.openTranscriptImportSheet()
                } label: {
                    Label("Upload Transcript / Report Card…", systemImage: "doc.text.viewfinder")
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }
}
