import Foundation

// MARK: - Persistent Academic History Store (~/Library/Application Support/SchoolTracker/history.json)

public final class AcademicHistoryStore: @unchecked Sendable {
    public let historyFileURL: URL
    private let lock = NSRecursiveLock()
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(historyFileURL: URL = AcademicHistoryStore.defaultHistoryFileURL()) {
        self.historyFileURL = historyFileURL

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    /// Resolves `~/Library/Application Support/SchoolTracker/history.json`.
    public static func defaultHistoryFileURL() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("SchoolTracker", isDirectory: true)
            .appendingPathComponent("history.json", isDirectory: false)
    }

    public func loadHistory() throws -> [TermSnapshot] {
        lock.lock()
        defer { lock.unlock() }

        guard FileManager.default.fileExists(atPath: historyFileURL.path) else {
            return []
        }

        let data: Data
        do {
            data = try Data(contentsOf: historyFileURL)
        } catch {
            throw PersistenceError.readFailed(reason: error.localizedDescription)
        }

        do {
            return try decoder.decode([TermSnapshot].self, from: data)
        } catch {
            throw PersistenceError.decodeFailed(reason: error.localizedDescription)
        }
    }

    public func saveHistory(_ snapshots: [TermSnapshot]) throws {
        lock.lock()
        defer { lock.unlock() }

        let directoryURL = historyFileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
            let data = try encoder.encode(snapshots)
            try data.write(to: historyFileURL, options: [.atomic])
            try? FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: 0o600)],
                ofItemAtPath: historyFileURL.path
            )
        } catch {
            throw PersistenceError.writeFailed(reason: error.localizedDescription)
        }
    }

    /// Records or updates a term snapshot without overwriting older terms.
    @discardableResult
    public func recordSnapshot(
        courses: [ImportedCourse],
        schoolYear: String,
        termName: String,
        source: String = "renweb",
        syncedAt: Date = Date()
    ) throws -> TermSnapshot {
        lock.lock()
        defer { lock.unlock() }

        var history = (try? loadHistory()) ?? []
        let gpa = GPACalculator.calculateGPA(for: courses)

        let snapshot = TermSnapshot(
            schoolYear: schoolYear.trimmingCharacters(in: .whitespacesAndNewlines),
            termName: termName.trimmingCharacters(in: .whitespacesAndNewlines),
            syncedAt: syncedAt,
            gpaSummary: gpa,
            courses: courses,
            source: source
        )

        if let existingIndex = history.firstIndex(where: {
            $0.schoolYear.caseInsensitiveCompare(snapshot.schoolYear) == .orderedSame
                && $0.termName.caseInsensitiveCompare(snapshot.termName) == .orderedSame
        }) {
            var updated = snapshot
            updated.id = history[existingIndex].id
            history[existingIndex] = updated
        } else {
            history.append(snapshot)
        }

        // Keep chronological order
        history.sort { lhs, rhs in
            if lhs.schoolYear != rhs.schoolYear {
                return lhs.schoolYear < rhs.schoolYear
            }
            return lhs.termName < rhs.termName
        }

        try saveHistory(history)
        return snapshot
    }

    @discardableResult
    public func deleteSnapshot(id: UUID) throws -> [TermSnapshot] {
        lock.lock()
        defer { lock.unlock() }

        var history = (try? loadHistory()) ?? []
        history.removeAll { $0.id == id }
        try saveHistory(history)
        return history
    }

    public func clearHistory() throws {
        lock.lock()
        defer { lock.unlock() }

        if FileManager.default.fileExists(atPath: historyFileURL.path) {
            try? FileManager.default.removeItem(at: historyFileURL)
        }
    }

    // MARK: - Export Utilities (JSON, CSV, Markdown)

    public func exportJSON(snapshots: [TermSnapshot]? = nil) throws -> String {
        lock.lock()
        defer { lock.unlock() }

        let list = snapshots ?? ((try? loadHistory()) ?? [])
        let data = try encoder.encode(list)
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    public func exportCSV(snapshots: [TermSnapshot]? = nil) -> String {
        lock.lock()
        defer { lock.unlock() }

        let list = snapshots ?? ((try? loadHistory()) ?? [])
        var lines: [String] = [
            "School Year,Term,Course Name,Course Code,Teacher,Numeric Grade,Letter Grade,Weight Tier,Unweighted Points,Weighted Points,Credits Earned,Source"
        ]

        for snapshot in list {
            for course in snapshot.courses {
                let score = course.numericAverage.map { String(format: "%.1f", $0) } ?? ""
                let letter = course.letterGrade ?? (course.numericAverage.map { GPACalculator.letterGrade(for: $0) } ?? "")
                let tier = course.effectiveWeightTier
                let unweighted = course.numericAverage.map { String(format: "%.2f", GPACalculator.unweightedPoints(for: $0)) } ?? ""
                let weighted = course.numericAverage.map { String(format: "%.2f", GPACalculator.weightedPoints(for: $0, tier: tier)) } ?? ""
                let courseCredit = course.creditHours ?? GPACalculator.defaultSemesterCourseCredit
                let credits = (course.countsTowardGraduation && (course.numericAverage ?? 0.0) >= 70.0) ? String(format: "%.2f", courseCredit) : "0.00"

                let fields = [
                    escapeCSV(snapshot.schoolYear),
                    escapeCSV(snapshot.termName),
                    escapeCSV(course.courseName),
                    escapeCSV(course.courseCode ?? ""),
                    escapeCSV(course.teacherName ?? ""),
                    score,
                    letter,
                    escapeCSV(tier.rawValue),
                    unweighted,
                    weighted,
                    credits,
                    escapeCSV(snapshot.source)
                ]
                lines.append(fields.joined(separator: ","))
            }
        }

        return lines.joined(separator: "\n")
    }

    public func exportMarkdownTranscript(snapshots: [TermSnapshot]? = nil) -> String {
        lock.lock()
        defer { lock.unlock() }

        let list = snapshots ?? ((try? loadHistory()) ?? [])
        guard !list.isEmpty else {
            return "# Academic Transcript & Historical Records\n\nNo historical terms recorded."
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none

        var md = "# Official Academic Record & Historical Transcripts\n\n"
        md += "_Generated on: \(dateFormatter.string(from: Date()))_\n\n"

        for snapshot in list {
            md += "## \(snapshot.schoolYear) — \(snapshot.termName)\n\n"
            md += "- **Weighted GPA:** \(String(format: "%.2f", snapshot.gpaSummary.weightedGPA))\n"
            md += "- **Unweighted GPA:** \(String(format: "%.2f", snapshot.gpaSummary.unweightedGPA))\n"
            md += "- **Credits Earned:** \(String(format: "%.2f", snapshot.gpaSummary.earnedCredits)) / \(String(format: "%.2f", snapshot.gpaSummary.totalCreditsAttempted))\n"
            if snapshot.gpaSummary.honorRollStatus != .none {
                md += "- **Honor Roll:** \(snapshot.gpaSummary.honorRollStatus.rawValue)\n"
            }
            md += "\n"

            md += "| Course | Code | Grade | Letter | Weight Tier | Earned Credits |\n"
            md += "|:-------|:-----|:------|:-------|:------------|:---------------|\n"

            for course in snapshot.courses {
                let gradeStr = course.numericAverage.map { String(format: "%.1f%%", $0) } ?? "N/A"
                let letter = course.letterGrade ?? (course.numericAverage.map { GPACalculator.letterGrade(for: $0) } ?? "-")
                let tier = course.effectiveWeightTier.rawValue
                let courseCredit = course.creditHours ?? GPACalculator.defaultSemesterCourseCredit
                let credits = (course.countsTowardGraduation && (course.numericAverage ?? 0.0) >= 70.0) ? String(format: "%.2f", courseCredit) : "0.00"
                let code = course.courseCode ?? "-"

                md += "| \(course.courseName) | \(code) | \(gradeStr) | \(letter) | \(tier) | \(credits) |\n"
            }
            md += "\n---\n\n"
        }

        return md
    }

    private func escapeCSV(_ text: String) -> String {
        if text.contains(",") || text.contains("\"") || text.contains("\n") {
            let escaped = text.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return text
    }
}
