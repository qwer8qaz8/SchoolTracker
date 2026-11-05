import SwiftUI
import AppIntents
import CoreSpotlight
import UniformTypeIdentifiers
import SchoolTrackerCore

// MARK: - macOS Liquid Glass Styling System

public struct LiquidGlassCard<Content: View>: View {
    public let cornerRadius: CGFloat
    public let content: Content

    public init(cornerRadius: CGFloat = 14, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    public var body: some View {
        content
            .padding()
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.35),
                                Color.white.opacity(0.08),
                                Color.black.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 3)
    }
}

public struct LiquidGlassBadge: View {
    public let text: String
    public let systemImage: String?
    public let tint: Color

    public init(_ text: String, systemImage: String? = nil, tint: Color = .accentColor) {
        self.text = text
        self.systemImage = systemImage
        self.tint = tint
    }

    public var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.semibold))
            }
            Text(text)
                .font(.caption2.weight(.medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
        }
        .overlay {
            Capsule()
                .strokeBorder(tint.opacity(0.35), lineWidth: 1)
        }
        .foregroundStyle(tint)
    }
}

public extension View {
    func liquidGlassPanel(cornerRadius: CGFloat = 12) -> some View {
        self
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.28), Color.white.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
    }
}

// MARK: - CoreSpotlight Academic Indexer

public enum SpotlightIndexManager {
    public static let courseDomainIdentifier = "com.schooltracker.app.courses"
    public static let termDomainIdentifier = "com.schooltracker.app.terms"

    public static func indexState(_ state: SchoolTrackerState) {
        var items: [CSSearchableItem] = []

        // 1. Index active courses
        for course in state.courses {
            let attributeSet = CSSearchableItemAttributeSet(contentType: .text)
            attributeSet.title = course.courseName
            let avgStr = course.numericAverage != nil ? String(format: "%.1f%%", course.numericAverage!) : "No Grade"
            let letter = course.letterGrade ?? ""
            let teacher = course.teacherName != nil ? " • \(course.teacherName!)" : ""
            attributeSet.contentDescription = "\(avgStr) (\(letter)) • \(course.effectiveWeightTier.displayName)\(teacher)"
            attributeSet.keywords = [
                course.courseName,
                course.courseCode ?? "",
                course.effectiveWeightTier.displayName,
                "Grade",
                "FLHS",
                "SchoolTracker"
            ]

            let item = CSSearchableItem(
                uniqueIdentifier: "course-\(course.id.uuidString)",
                domainIdentifier: courseDomainIdentifier,
                attributeSet: attributeSet
            )
            items.append(item)
        }

        // 2. Index archived term snapshots
        for snapshot in state.academicHistory {
            let attributeSet = CSSearchableItemAttributeSet(contentType: .compositeContent)
            attributeSet.title = "\(snapshot.termName) (\(snapshot.schoolYear))"
            let weighted = String(format: "%.2f", snapshot.gpaSummary.weightedGPA)
            let unweighted = String(format: "%.2f", snapshot.gpaSummary.unweightedGPA)
            let honor = snapshot.gpaSummary.honorRollStatus != .none ? " • \(snapshot.gpaSummary.honorRollStatus.rawValue)" : ""
            attributeSet.contentDescription = "Weighted GPA \(weighted) • Unweighted \(unweighted)\(honor) • \(snapshot.courses.count) courses"
            attributeSet.keywords = [
                snapshot.termName,
                snapshot.schoolYear,
                "Transcript",
                "Report Card",
                "GPA",
                "FLHS"
            ]

            let item = CSSearchableItem(
                uniqueIdentifier: "term-\(snapshot.id.uuidString)",
                domainIdentifier: termDomainIdentifier,
                attributeSet: attributeSet
            )
            items.append(item)
        }

        guard !items.isEmpty else { return }
        CSSearchableIndex.default().indexSearchableItems(items) { _ in }
    }

    public static func removeIndex() {
        CSSearchableIndex.default().deleteAllSearchableItems(completionHandler: nil)
    }
}

// MARK: - Siri & Shortcuts App Intents (macOS 14+)

@available(macOS 14.0, *)
public struct GetGPAIntent: AppIntent {
    public static var title: LocalizedStringResource = "Get GPA & Honor Roll"
    public static var description = IntentDescription("Calculates current weighted GPA, unweighted GPA, and FLHS Honor Roll status.")
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let store = SchoolTrackerStore()
        let state = (try? store.loadState()) ?? SchoolTrackerState()
        let summary = GPACalculator.calculateGPA(for: state.courses)
        let weighted = String(format: "%.2f", summary.weightedGPA)
        let unweighted = String(format: "%.2f", summary.unweightedGPA)
        let honorRollText = summary.honorRollStatus != .none ? " qualifying for \(summary.honorRollStatus.rawValue)" : ""
        let dialog = "Your current weighted GPA is \(weighted) (unweighted \(unweighted))\(honorRollText) with \(String(format: "%.1f", summary.earnedCredits)) credits earned."

        return .result(
            dialog: IntentDialog(stringLiteral: dialog),
            view: GPASummaryIntentSnippet(summary: summary)
        )
    }
}

@available(macOS 14.0, *)
public struct GetGradeSummaryIntent: AppIntent {
    public static var title: LocalizedStringResource = "Get Grade Summary"
    public static var description = IntentDescription("Fetches active course averages and overall academic standing.")
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let store = SchoolTrackerStore()
        let state = (try? store.loadState()) ?? SchoolTrackerState()
        let courses = state.courses
        let count = courses.count
        let avg = state.overallAverage != nil ? String(format: "%.1f%%", state.overallAverage!) : "N/A"
        let dialog = "You have \(count) active courses with an overall average of \(avg)."

        return .result(
            dialog: IntentDialog(stringLiteral: dialog),
            view: GradeSummaryIntentSnippet(courses: courses, overallAverage: state.overallAverage)
        )
    }
}

@available(macOS 14.0, *)
public struct SyncGradesIntent: AppIntent {
    public static var title: LocalizedStringResource = "Sync School Grades"
    public static var description = IntentDescription("Fetches latest grades using your saved FACTS/RenWeb report link.")
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = SchoolTrackerStore()
        guard let savedLink = try? store.loadSavedRenWebLink() else {
            return .result(dialog: "No saved FACTS/RenWeb link found. Please save a report link in SchoolTracker first.")
        }

        let client = RenWebClient()
        do {
            let report = try await client.importReport(from: savedLink)
            _ = try store.applyImportedReport(report, from: savedLink)
            return .result(dialog: "Synced \(report.courses.count) courses successfully.")
        } catch {
            return .result(dialog: "Failed to sync grades: \(error.localizedDescription)")
        }
    }
}

@available(macOS 14.0, *)
public struct SchoolTrackerShortcuts: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetGPAIntent(),
            phrases: [
                "What is my GPA in \(.applicationName)?",
                "Check my GPA in \(.applicationName)",
                "Calculate my GPA with \(.applicationName)"
            ],
            shortTitle: "Get GPA",
            systemImageName: "graduationcap"
        )
        AppShortcut(
            intent: GetGradeSummaryIntent(),
            phrases: [
                "What are my grades in \(.applicationName)?",
                "Check my grades in \(.applicationName)",
                "Show my grade summary in \(.applicationName)"
            ],
            shortTitle: "Get Grades",
            systemImageName: "chart.bar.doc.horizontal"
        )
        AppShortcut(
            intent: SyncGradesIntent(),
            phrases: [
                "Sync my grades in \(.applicationName)",
                "Refresh grades in \(.applicationName)"
            ],
            shortTitle: "Sync Grades",
            systemImageName: "arrow.triangle.2.circlepath"
        )
    }
}

// MARK: - Siri Snippet Views

public struct GPASummaryIntentSnippet: View {
    public let summary: GPASummary

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("FLHS GPA Standing", systemImage: "graduationcap.fill")
                    .font(.headline)
                    .foregroundStyle(Color.accentColor)
                Spacer()
                if summary.honorRollStatus != .none {
                    Text(summary.honorRollStatus.rawValue)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.yellow.opacity(0.2))
                        .foregroundStyle(Color.orange)
                        .clipShape(Capsule())
                }
            }

            HStack(spacing: 20) {
                VStack(alignment: .leading) {
                    Text("Weighted GPA")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.2f", summary.weightedGPA))
                        .font(.title2.weight(.bold))
                }

                VStack(alignment: .leading) {
                    Text("Unweighted GPA")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.2f", summary.unweightedGPA))
                        .font(.title2.weight(.bold))
                }

                VStack(alignment: .leading) {
                    Text("Credits Earned")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(String(format: "%.1f", summary.earnedCredits)) / \(String(format: "%.0f", GPACalculator.graduationCreditsRequired))")
                        .font(.title3.weight(.semibold))
                }
            }
        }
        .padding()
        .frame(minWidth: 280)
    }
}

public struct GradeSummaryIntentSnippet: View {
    public let courses: [ImportedCourse]
    public let overallAverage: Double?

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Current Courses (\(courses.count))")
                    .font(.headline)
                Spacer()
                if let overallAverage {
                    Text(String(format: "%.1f%%", overallAverage))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                }
            }

            Divider()

            ForEach(courses.prefix(4)) { course in
                HStack {
                    Text(course.courseName)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    if let avg = course.numericAverage {
                        Text(String(format: "%.1f%%", avg))
                            .font(.caption.weight(.semibold))
                    }
                    if let letter = course.letterGrade {
                        Text(letter)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if courses.count > 4 {
                Text("+ \(courses.count - 4) more courses")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(minWidth: 280)
    }
}
