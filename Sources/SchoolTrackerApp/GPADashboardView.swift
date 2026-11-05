import SwiftUI
import SchoolTrackerCore

public struct GPADashboardView: View {
    @ObservedObject var viewModel: SchoolTrackerViewModel

    public init(viewModel: SchoolTrackerViewModel) {
        self.viewModel = viewModel
    }

    private var summary: GPASummary {
        viewModel.gpaSummary
    }

    private var academicStanding: (standing: String, nextThreshold: String) {
        let earned = summary.earnedCredits
        if earned < 8.0 {
            return ("Freshman", "\(String(format: "%.1f", 8.0 - earned)) credits to Sophomore")
        } else if earned < 16.0 {
            return ("Sophomore", "\(String(format: "%.1f", 16.0 - earned)) credits to Junior")
        } else if earned < 24.0 {
            return ("Junior", "\(String(format: "%.1f", 24.0 - earned)) credits to Senior")
        } else {
            return ("Senior", "\(String(format: "%.1f", max(0, 32.0 - earned))) credits to 32.0 Graduation")
        }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerView

                if viewModel.state.courses.isEmpty {
                    emptyStateView
                } else {
                    metricsGrid
                    creditsProgressCard
                    handbookInfoSection
                    coursesWeightEditorTable
                }
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("Term Snapshot Archived", isPresented: $viewModel.isShowingSnapshotConfirmation) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.snapshotSuccessMessage ?? "Current grades and GPA summary have been saved to your permanent Academic History.")
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("FLHS GPA & Credits")
                        .font(.title2.weight(.bold))
                    LiquidGlassBadge("Handbook 26–27", systemImage: "book.pages", tint: .indigo)
                }
                Text("Faith Lutheran High School weighted GPA, honor roll status, and 32.0 credit progress.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 10) {
                Button {
                    viewModel.openTranscriptImportSheet()
                } label: {
                    Label("Import Transcript…", systemImage: "doc.text.viewfinder")
                }
                .buttonStyle(.bordered)
                .help("Import a PDF report card or scanned transcript with on-device Apple Intelligence OCR")

                Button {
                    let snapshot = viewModel.snapshotCurrentTerm()
                    viewModel.snapshotSuccessMessage = "Archived snapshot for \(snapshot.termName) (\(snapshot.schoolYear)) with weighted GPA \(String(format: "%.2f", snapshot.gpaSummary.weightedGPA))."
                    viewModel.isShowingSnapshotConfirmation = true
                } label: {
                    Label("Archive Current Term", systemImage: "clock.arrow.2.circlepath")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.state.courses.isEmpty)
                .help("Freeze and save current term grades permanently into Academic History")
            }
        }
    }

    // MARK: - Metrics Grid

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 14)], spacing: 14) {
            LiquidGlassCard {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Weighted GPA")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .foregroundStyle(Color.accentColor)
                    }
                    Text(String(format: "%.2f", summary.weightedGPA))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.accentColor)
                    Text("Includes Honors (+0.50) & Dual Credit (+1.00)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            LiquidGlassCard {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Unweighted GPA")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "equal.circle")
                            .foregroundStyle(.teal)
                    }
                    Text(String(format: "%.2f", summary.unweightedGPA))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.teal)
                    Text("4.00 standard scale (all courses +0.0)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            LiquidGlassCard {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Honor Roll Recognition")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "medal.fill")
                            .foregroundStyle(honorRollColor)
                    }

                    HStack(spacing: 6) {
                        Text(summary.honorRollStatus.rawValue)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(honorRollColor)
                    }

                    Text(summary.honorRollStatus.badgeDescription)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            LiquidGlassCard {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Class Standing")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "graduationcap")
                            .foregroundStyle(.purple)
                    }
                    Text(academicStanding.standing)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.purple)
                    Text(academicStanding.nextThreshold)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var honorRollColor: Color {
        switch summary.honorRollStatus {
        case .principalsHonorRoll:
            return .yellow
        case .honorRoll:
            return .blue
        case .meritRoll:
            return .purple
        case .none:
            return .secondary
        }
    }

    // MARK: - Graduation Credits Meter

    private var creditsProgressCard: some View {
        LiquidGlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("FLHS Graduation Credit Meter", systemImage: "gauge.with.needle")
                        .font(.headline)
                    Spacer()
                    Text("\(String(format: "%.1f", summary.earnedCredits)) / \(String(format: "%.0f", GPACalculator.graduationCreditsRequired)) Credits")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }

                ProgressView(value: summary.earnedCredits, total: GPACalculator.graduationCreditsRequired)
                    .tint(Color.accentColor)

                HStack {
                    Text("Freshman (<8)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Sophomore (8–15.5)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Junior (16–23.5)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Senior (24–32)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Handbook Scale Accordion

    private var handbookInfoSection: some View {
        DisclosureGroup(isExpanded: $viewModel.isShowingHandbookScale) {
            VStack(alignment: .leading, spacing: 12) {
                Divider()

                Text("Points Awarded per Numerical Grade Bracket (Handbook p. 5–6)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    scaleBracketCard("97–100 (A)", regular: "4.0", honors: "4.5", advHonors: "5.0")
                    scaleBracketCard("93–96 (A)", regular: "3.8", honors: "4.3", advHonors: "4.8")
                    scaleBracketCard("90–92 (A)", regular: "3.6", honors: "4.1", advHonors: "4.6")
                    scaleBracketCard("87–89 (B)", regular: "3.4", honors: "3.9", advHonors: "4.4")
                    scaleBracketCard("83–86 (B)", regular: "3.2", honors: "3.7", advHonors: "4.2")
                    scaleBracketCard("80–82 (B)", regular: "3.0", honors: "3.5", advHonors: "4.0")
                    scaleBracketCard("77–79 (C)", regular: "2.8", honors: "3.3", advHonors: "3.8")
                    scaleBracketCard("73–76 (C)", regular: "2.6", honors: "3.1", advHonors: "3.6")
                    scaleBracketCard("71–72 (C)", regular: "2.4", honors: "2.9", advHonors: "3.4")
                    scaleBracketCard("70 (D)", regular: "2.0", honors: "2.5", advHonors: "3.0")
                    scaleBracketCard("< 70 (F)", regular: "0.0", honors: "0.0", advHonors: "0.0")
                }

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Semester Grade Policy")
                            .font(.caption.weight(.bold))
                        Text("Average of two quarters. Each passing semester course (≥ 70) earns 0.50 credit.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Honor Roll Requirements")
                            .font(.caption.weight(.bold))
                        Text("No grade below 70. Merit ≥ 3.25 (A/B), Honor ≥ 3.75 (A/B), Principal's ≥ 4.00 (All A).")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 4)
            }
            .padding(.top, 6)
        } label: {
            HStack {
                Label("FLHS Handbook Grade Scale & Weights", systemImage: "info.circle")
                    .font(.headline)
                Spacer()
                Text(viewModel.isShowingHandbookScale ? "Hide Reference" : "Show Reference")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
        }
    }

    private func scaleBracketCard(_ bracket: String, regular: String, honors: String, advHonors: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(bracket)
                .font(.caption.weight(.bold))
            HStack(spacing: 6) {
                Text("Reg: \(regular)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("H: \(honors)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.blue)
                Text("AH: \(advHonors)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.purple)
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Course Weight Tier Editor Table

    private var coursesWeightEditorTable: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Course Weight Tiers & Grade Points (\(viewModel.state.courses.count))")
                        .font(.headline)
                    Text("Auto-classified from course codes and handbook keywords. Change any tier to re-weight your GPA immediately.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            VStack(spacing: 8) {
                ForEach(viewModel.state.courses) { course in
                    courseWeightRow(course)
                }
            }
        }
    }

    private func courseWeightRow(_ course: ImportedCourse) -> some View {
        let score = course.numericAverage ?? 0.0
        let unweighted = GPACalculator.unweightedPoints(for: score)
        let weighted = GPACalculator.weightedPoints(for: score, tier: course.effectiveWeightTier)
        let isAuto = (course.weightTier == nil)

        return LiquidGlassCard(cornerRadius: 10) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(course.courseName)
                            .font(.headline)
                            .lineLimit(1)

                        if let code = course.courseCode, !code.isEmpty {
                            Text(code)
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }

                        if !course.countsTowardGraduation || !course.countsTowardGPA {
                            LiquidGlassBadge("Non-Credit / Excluded", systemImage: "xmark.shield", tint: .orange)
                        } else if isAuto {
                            LiquidGlassBadge("Auto", systemImage: "sparkles", tint: .teal)
                        } else {
                            LiquidGlassBadge("Custom", tint: .orange)
                        }
                    }

                    if let reason = course.exclusionReason {
                        Text(reason)
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    } else if let teacher = course.teacherName {
                        Text(teacher)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Numeric Grade + Letter
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 4) {
                        if let avg = course.numericAverage {
                            Text(String(format: "%.1f%%", avg))
                                .font(.title3.weight(.bold))
                                .foregroundStyle(SchoolTrackerViewModel.gradeColor(for: avg))
                        } else {
                            Text("—")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }

                        if let letter = course.letterGrade {
                            Text(letter)
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(SchoolTrackerViewModel.gradeColor(for: course.numericAverage).opacity(0.15))
                                .foregroundStyle(SchoolTrackerViewModel.gradeColor(for: course.numericAverage))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    Text("Grade Score")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 90, alignment: .trailing)

                Divider()
                    .frame(height: 36)

                // Weight Tier Picker
                VStack(alignment: .leading, spacing: 2) {
                    Picker("Weight Tier", selection: Binding<CourseWeightTier>(
                        get: { course.effectiveWeightTier },
                        set: { newTier in
                            viewModel.setCourseWeightTier(courseID: course.id, tier: newTier)
                        }
                    )) {
                        ForEach(CourseWeightTier.allCases) { tier in
                            Text(tier.displayName).tag(tier)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 170)

                    Text(course.effectiveWeightTier.weightBonus > 0 ? "+\(String(format: "%.2f", course.effectiveWeightTier.weightBonus)) weight bonus" : "Standard +0.0")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Divider()
                    .frame(height: 36)

                // Calculated GPA Points
                VStack(alignment: .trailing, spacing: 2) {
                    if course.countsTowardGPA {
                        HStack(spacing: 4) {
                            Text("W:")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.2f", weighted))
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Color.accentColor)
                            Text("• UW:")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.2f", unweighted))
                                .font(.subheadline.weight(.semibold))
                        }
                    } else {
                        Text("Excluded from GPA")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    if course.countsTowardGraduation {
                        Text(score >= 70.0 ? String(format: "%.2f Credit", course.creditHours ?? GPACalculator.defaultSemesterCourseCredit) : "0.00 Credit")
                            .font(.caption2)
                            .foregroundStyle(score >= 70.0 ? Color.green : Color.red)
                    } else {
                        Text("0.00 Credit (Non-Credit)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(minWidth: 110, alignment: .trailing)
                .contextMenu {
                    Button(course.countsTowardGraduation ? "Exclude from Graduation Credits" : "Count Toward Graduation Credits") {
                        viewModel.setCourseCountsTowardGraduation(courseID: course.id, counts: !course.countsTowardGraduation)
                    }
                    Button(course.countsTowardGPA ? "Exclude from GPA Calculation" : "Include in GPA Calculation") {
                        viewModel.setCourseCountsTowardGPA(courseID: course.id, counts: !course.countsTowardGPA)
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "graduationcap.circle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Course Grades Available")
                .font(.headline)
            Text("Import a FACTS/RenWeb report link or upload a transcript PDF/image to calculate your FLHS weighted GPA and graduation credits.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            HStack(spacing: 12) {
                Button {
                    viewModel.openImportSheet()
                } label: {
                    Label("Import RenWeb Link", systemImage: "link.badge.plus")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    viewModel.openTranscriptImportSheet()
                } label: {
                    Label("Upload Transcript…", systemImage: "doc.text.viewfinder")
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
