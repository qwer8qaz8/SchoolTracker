import SwiftUI
import AppKit
import UniformTypeIdentifiers
import SchoolTrackerCore

public enum TranscriptImportSheetState: Equatable {
    case idle
    case processing(filename: String)
    case preview(snapshot: TermSnapshot, courses: [ImportedCourse], rawTextSnippet: String)
    case success(termName: String, courseCount: Int, totalTerms: Int = 1, totalCourses: Int = 0)
    case error(String)
}

public struct TranscriptImportSheet: View {
    @ObservedObject var viewModel: SchoolTrackerViewModel
    @Environment(\.dismiss) private var dismiss

    public init(viewModel: SchoolTrackerViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            ScrollView {
                VStack(spacing: 20) {
                    switch viewModel.transcriptImportState {
                    case .idle:
                        dropZoneView
                    case .processing(let filename):
                        processingView(filename: filename)
                    case .preview(let snapshot, let courses, let rawSnippet):
                        previewView(snapshot: snapshot, courses: courses, rawSnippet: rawSnippet)
                    case .success(let termName, let courseCount, let totalTerms, let totalCourses):
                        successView(termName: termName, courseCount: courseCount, totalTerms: totalTerms, totalCourses: totalCourses)
                    case .error(let message):
                        errorView(message: message)
                    }
                }
                .padding(24)
            }

            Divider()
            bottomActionBar
        }
        .frame(minWidth: 620, idealWidth: 700, minHeight: 480, idealHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("Import Transcript / Report Card")
                        .font(.headline)
                    LiquidGlassBadge("On-Device AI", systemImage: "sparkles", tint: .teal)
                }
                Text("Uses local PDFKit and Apple Vision OCR. Zero student data or grades leave your Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Drop Zone (Idle)

    private var dropZoneView: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        viewModel.isTargetedForTranscriptDrop ? Color.accentColor : Color.secondary.opacity(0.3),
                        style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(viewModel.isTargetedForTranscriptDrop ? Color.accentColor.opacity(0.08) : Color.clear)
                    )

                VStack(spacing: 14) {
                    Image(systemName: viewModel.isTargetedForTranscriptDrop ? "arrow.down.doc.fill" : "doc.badge.plus")
                        .font(.system(size: 46))
                        .foregroundStyle(viewModel.isTargetedForTranscriptDrop ? Color.accentColor : .secondary)

                    VStack(spacing: 4) {
                        Text(viewModel.isTargetedForTranscriptDrop ? "Drop Transcript File Here" : "Drag and Drop Transcript or Report Card")
                            .font(.headline)
                        Text("Supports PDF documents, scanned images (PNG, JPEG, TIFF, HEIC)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        selectFileViaOpenPanel()
                    } label: {
                        Label("Choose File…", systemImage: "folder")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
                .padding(.vertical, 40)
                .padding(.horizontal, 24)
            }
            .onDrop(of: [.fileURL], isTargeted: $viewModel.isTargetedForTranscriptDrop) { providers in
                handleFileDrop(providers: providers)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("How On-Device Apple Intelligence Ingestion Works")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)

                HStack(alignment: .top, spacing: 14) {
                    featureBullet(icon: "lock.shield", title: "100% Private", desc: "No internet requests or API keys required.")
                    featureBullet(icon: "text.viewfinder", title: "Apple Vision OCR", desc: "Parses tabular course codes, averages, and terms.")
                    featureBullet(icon: "graduationcap", title: "Auto-Tier Weighting", desc: "Maps Honors and Dual Credit directly to FLHS scales.")
                }
            }
            .padding()
            .liquidGlassPanel()
        }
    }

    private func featureBullet(icon: String, title: String, desc: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
            Text(desc)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Processing View

    private func processingView(filename: String) -> some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Analyzing \(filename)…")
                .font(.headline)
            Text("Extracting course names, numeric averages, and term dates via local Apple Intelligence…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 60)
        .frame(maxWidth: .infinity)
        .liquidGlassPanel()
    }

    // MARK: - Preview View

    private func previewView(snapshot: TermSnapshot, courses: [ImportedCourse], rawSnippet: String) -> some View {
        let displayCourses = viewModel.draftTranscriptFilterNonHighSchool
            ? courses.filter { $0.countsTowardGraduation || $0.isRelevantForHighSchool }
            : courses
        let previewSummary = GPACalculator.calculateGPA(for: displayCourses)
        let excludedCount = courses.filter { !$0.countsTowardGraduation && !$0.isRelevantForHighSchool }.count

        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Extraction Preview")
                        .font(.headline)
                    Text("Parsed \(courses.count) course\(courses.count == 1 ? "" : "s") from your document. Elementary (grades 1–8) and non-academic entries are excluded from graduation credits.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                LiquidGlassBadge("Vision OCR Complete", systemImage: "checkmark.circle.fill", tint: .green)
            }

            // High school filtering toggle and excluded banner
            LiquidGlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Toggle("Only import relevant High School courses (exclude 1st–8th grade & non-credit)", isOn: $viewModel.draftTranscriptFilterNonHighSchool)
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        if excludedCount > 0 {
                            LiquidGlassBadge("\(excludedCount) excluded (0.0 credits)", systemImage: "shield.slash.fill", tint: .orange)
                        }
                    }

                    if excludedCount > 0 {
                        Text("Notice: \(excludedCount) course\(excludedCount == 1 ? " was" : "s were") identified as elementary/middle school (grades 1–8) or non-academic and earn 0.0 graduation credits.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if viewModel.draftTranscriptAdditionalSnapshots.count > 1 {
                        HStack(spacing: 8) {
                            LiquidGlassBadge("Multi-Term Transcript: \(viewModel.draftTranscriptAdditionalSnapshots.count) terms", systemImage: "archivebox.fill", tint: .indigo)
                            Text("All historical terms will be saved into Academic History.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // Editable Term & Year Metadata
            LiquidGlassCard {
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("School Year")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        TextField("e.g. 2026-2027", text: $viewModel.draftTranscriptSchoolYear)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Term / Grading Period")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        TextField("e.g. Semester 1 or Quarter 1", text: $viewModel.draftTranscriptTermName)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }

            // Calculated GPA Preview Card
            LiquidGlassCard {
                HStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Weighted GPA")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.2f", previewSummary.weightedGPA))
                            .font(.title2.weight(.bold))
                            .foregroundStyle(Color.accentColor)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Unweighted GPA")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.2f", previewSummary.unweightedGPA))
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.teal)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Honor Roll")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(previewSummary.honorRollStatus.rawValue)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(previewSummary.honorRollStatus != .none ? Color.orange : Color.secondary)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Credits Earned")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.1f", previewSummary.earnedCredits))
                            .font(.title2.weight(.semibold))
                    }
                }
            }

            // Extracted Courses List
            VStack(alignment: .leading, spacing: 8) {
                Text("Extracted Courses (\(displayCourses.count))")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)

                ForEach(displayCourses) { course in
                    LiquidGlassCard(cornerRadius: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(course.courseName)
                                        .font(.subheadline.weight(.semibold))
                                    if let code = course.courseCode {
                                        Text(code)
                                            .font(.caption2)
                                            .padding(.horizontal, 4)
                                            .background(Color.secondary.opacity(0.12))
                                            .clipShape(RoundedRectangle(cornerRadius: 3))
                                    }
                                }

                                HStack(spacing: 6) {
                                    LiquidGlassBadge(course.effectiveWeightTier.displayName, tint: .indigo)
                                    if !course.countsTowardGraduation || !course.countsTowardGPA {
                                        LiquidGlassBadge(course.exclusionReason ?? "Excluded (0.0 Cr)", systemImage: "xmark.shield", tint: .orange)
                                    } else {
                                        LiquidGlassBadge("HS Credit", systemImage: "checkmark.seal.fill", tint: .green)
                                    }
                                }
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 2) {
                                if let avg = course.numericAverage {
                                    HStack(spacing: 6) {
                                        Text(String(format: "%.1f%%", avg))
                                            .font(.subheadline.weight(.bold))
                                            .foregroundStyle(SchoolTrackerViewModel.gradeColor(for: avg))

                                        if let letter = course.letterGrade {
                                            Text(letter)
                                                .font(.caption.weight(.bold))
                                                .padding(.horizontal, 4)
                                                .background(SchoolTrackerViewModel.gradeColor(for: avg).opacity(0.15))
                                                .foregroundStyle(SchoolTrackerViewModel.gradeColor(for: avg))
                                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                        }
                                    }
                                }

                                if course.countsTowardGraduation {
                                    Text(String(format: "+%.2f Credit", course.creditHours ?? GPACalculator.defaultSemesterCourseCredit))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("0.00 Credit (Excluded)")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                }
            }

            // Merge Option Checkbox
            Toggle("Also set these as current active courses in SchoolTracker", isOn: $viewModel.draftTranscriptMergeCourses)
                .font(.subheadline)
                .padding(.top, 4)
        }
    }

    // MARK: - Success View

    private func successView(termName: String, courseCount: Int, totalTerms: Int, totalCourses: Int) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text(totalTerms > 1 ? "Entire School Career Imported" : "Transcript Saved Successfully")
                .font(.headline)
            if totalTerms > 1 {
                Text("Archived \(totalCourses) courses across \(totalTerms) terms into Academic History. High school GPA and graduation credits are active.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("Archived \(courseCount) courses for \(termName) into Academic History.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button("Done") {
                viewModel.transcriptImportState = .idle
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
        .padding(.vertical, 50)
        .frame(maxWidth: .infinity)
        .liquidGlassPanel()
    }

    // MARK: - Error View

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.red)
            Text("Could Not Parse Transcript")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            HStack(spacing: 12) {
                Button("Try Another File") {
                    viewModel.transcriptImportState = .idle
                }
                .buttonStyle(.borderedProminent)

                Button("Cancel") {
                    viewModel.transcriptImportState = .idle
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 50)
        .frame(maxWidth: .infinity)
        .liquidGlassPanel()
    }

    // MARK: - Bottom Action Bar

    private var bottomActionBar: some View {
        HStack {
            if case .preview = viewModel.transcriptImportState {
                Button("Choose Another File") {
                    viewModel.transcriptImportState = .idle
                }
                .buttonStyle(.borderless)
            }

            Spacer()

            Button("Cancel") {
                viewModel.transcriptImportState = .idle
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            if case .preview(var snapshot, let courses, _) = viewModel.transcriptImportState {
                Button {
                    snapshot.schoolYear = viewModel.draftTranscriptSchoolYear.trimmingCharacters(in: .whitespacesAndNewlines)
                    snapshot.termName = viewModel.draftTranscriptTermName.trimmingCharacters(in: .whitespacesAndNewlines)
                    snapshot.courses = courses
                    snapshot.gpaSummary = GPACalculator.calculateGPA(for: courses)

                    let totalTerms = viewModel.draftTranscriptAdditionalSnapshots.isEmpty ? 1 : viewModel.draftTranscriptAdditionalSnapshots.count
                    let totalCourses = viewModel.draftTranscriptAdditionalSnapshots.isEmpty
                        ? courses.count
                        : viewModel.draftTranscriptAdditionalSnapshots.reduce(0) { $0 + $1.courses.count }

                    viewModel.commitTranscriptSnapshot(snapshot, mergeIntoCurrentCourses: viewModel.draftTranscriptMergeCourses)
                    viewModel.transcriptImportState = .success(
                        termName: snapshot.termName,
                        courseCount: courses.count,
                        totalTerms: totalTerms,
                        totalCourses: totalCourses
                    )
                } label: {
                    Text("Save to Academic History")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - File Selection & OCR Processing

    private func selectFileViaOpenPanel() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false
        openPanel.allowedContentTypes = [
            UTType.pdf,
            UTType.png,
            UTType.jpeg,
            UTType.tiff,
            UTType.heic
        ]

        if openPanel.runModal() == .OK, let url = openPanel.url {
            processFile(at: url)
        }
    }

    private func handleFileDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            if let url {
                DispatchQueue.main.async {
                    self.processFile(at: url)
                }
            }
        }
        return true
    }

    private func processFile(at url: URL) {
        viewModel.transcriptImportState = .processing(filename: url.lastPathComponent)
        Task {
            do {
                let result = try LocalTranscriptParser.parseDocument(at: url)
                await MainActor.run {
                    self.viewModel.draftTranscriptSchoolYear = result.snapshot.schoolYear
                    self.viewModel.draftTranscriptTermName = result.snapshot.termName
                    self.viewModel.draftTranscriptAdditionalSnapshots = result.allSnapshots
                    self.viewModel.transcriptImportState = .preview(
                        snapshot: result.snapshot,
                        courses: result.courses,
                        rawTextSnippet: ""
                    )
                }
            } catch {
                await MainActor.run {
                    self.viewModel.transcriptImportState = .error(error.localizedDescription)
                }
            }
        }
    }
}
