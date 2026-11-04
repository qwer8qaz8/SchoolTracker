import Foundation

// MARK: - HTML Report Parser

public enum RenWebReportParser {
    private static let expiredPhrases: [String] = [
        "session has expired",
        "link is no longer valid",
        "report unavailable",
        "session is invalid",
        "report is no longer available",
        "parameter sessionid"
    ]

    public static func parse(html: String) throws -> ImportedGradeReport {
        let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            SchoolTrackerTelemetry.shared.increment(.reportParseFailure, context: "empty_html")
            throw RenWebError.parseFailure(reason: "HTML report payload is empty.")
        }

        let lowerHTML = trimmed.lowercased()

        // 1. Check for structured <div class="course-section"> layout (synthetic fixtures & modern markup)
        if lowerHTML.contains("course-section") {
            let courses = parseCourseSectionBlocks(from: trimmed)
            if !courses.isEmpty {
                SchoolTrackerTelemetry.shared.increment(
                    .reportParseSuccess,
                    context: "layout=course-section courses=\(courses.count)"
                )
                return ImportedGradeReport(courses: courses)
            }
        }

        // 2. Check for live ColdFusion GetReport.cfm multi-table layout
        let coldFusionReport = parseColdFusionTables(from: trimmed)
        if !coldFusionReport.courses.isEmpty {
            SchoolTrackerTelemetry.shared.increment(
                .reportParseSuccess,
                context: "layout=coldfusion-tables courses=\(coldFusionReport.courses.count)"
            )
            return coldFusionReport
        }

        // 3. Check for expired/invalid session markers
        if isExpiredSessionPage(lowerHTML: lowerHTML) {
            SchoolTrackerTelemetry.shared.increment(.reportParseExpiredSession, context: "expired_session_detected")
            throw RenWebError.expiredOrInvalidSession
        }

        SchoolTrackerTelemetry.shared.increment(.reportParseFailure, context: "no_courses_extracted")
        throw RenWebError.parseFailure(reason: "No valid course or grade tables found in HTML report.")
    }

    // MARK: - Expired Session Detection

    private static func isExpiredSessionPage(lowerHTML: String) -> Bool {
        if lowerHTML.contains("class=\"error-message\"") || lowerHTML.contains("class='error-message'") {
            return true
        }
        for phrase in expiredPhrases where lowerHTML.contains(phrase) {
            return true
        }
        return false
    }

    // MARK: - Path A: <div class="course-section"> Parser

    private static func parseCourseSectionBlocks(from html: String) -> [ImportedCourse] {
        let parts = html.components(separatedBy: "<div class=\"course-section\"")
        guard parts.count > 1 else { return [] }

        var courses: [ImportedCourse] = []
        courses.reserveCapacity(parts.count - 1)

        for index in 1..<parts.count {
            let block = parts[index]
            let dataCourseAttr = extractFirstSubstring(
                in: block,
                after: "data-course=\"",
                before: "\""
            ).map(decodeHTMLEntities)

            let titleCell = extractTagContent(in: block, classMarker: "course-title")
            let teacherCell = extractTagContent(in: block, classMarker: "course-teacher")
            let gradeCell = extractTagContent(in: block, classMarker: "course-grade")

            let rawCourseName = (titleCell?.isEmpty == false ? titleCell : dataCourseAttr) ?? ""
            let courseName = rawCourseName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !courseName.isEmpty else { continue }

            let (numericAverage, letterGrade) = parseCourseGradeSummary(gradeCell ?? "")

            var assignments: [ImportedAssignment] = []
            if let tbodyRange = block.range(of: "<table class=\"assignments\"", options: [.caseInsensitive]) {
                let assignmentsSlice = String(block[tbodyRange.upperBound...])
                let tableContent = assignmentsSlice.components(separatedBy: "</table>").first ?? assignmentsSlice
                let rows = extractTableRows(from: tableContent)
                assignments.reserveCapacity(rows.count)

                for row in rows {
                    if row.lowercased().contains("<th") {
                        continue
                    }
                    let cells = extractTableCells(from: row)
                    guard cells.count >= 6 else { continue }
                    let category = cells[0].isEmpty ? "General" : cells[0]
                    let title = cells[1]
                    guard !title.isEmpty else { continue }
                    let dueDate = cells[2].isEmpty ? nil : cells[2]
                    let pointsEarned = parseNumericValue(cells[3])
                    let pointsPossible = parseNumericValue(cells[4])
                    let percentage = parsePercentageValue(cells[5]) ?? computePercentage(earned: pointsEarned, possible: pointsPossible)
                    let isPending = pointsEarned == nil && percentage == nil

                    assignments.append(
                        ImportedAssignment(
                            title: title,
                            category: category,
                            dueDate: dueDate,
                            pointsEarned: pointsEarned,
                            pointsPossible: pointsPossible,
                            percentage: percentage,
                            status: isPending ? "Pending" : "Graded",
                            isCompleted: !isPending
                        )
                    )
                }
            }

            courses.append(
                ImportedCourse(
                    courseName: courseName,
                    teacherName: teacherCell?.isEmpty == false ? teacherCell : nil,
                    numericAverage: numericAverage,
                    letterGrade: letterGrade,
                    assignments: assignments
                )
            )
        }

        return courses
    }

    // MARK: - Path B: Live ColdFusion GetReport.cfm Multi-Table Parser

    private static func parseColdFusionTables(from html: String) -> ImportedGradeReport {
        let tables = extractBlocks(from: html, openTag: "<table", closeTag: "</table>")
        guard !tables.isEmpty else {
            return ImportedGradeReport(courses: [])
        }

        var courses: [ImportedCourse] = []
        var currentCourse: ImportedCourse?
        var currentCategory = "General"
        var detectedYear: String?
        var detectedTerm: String?

        for tableHTML in tables {
            let rawRows = extractTableRows(from: tableHTML)
            let rows = rawRows.map { extractTableCells(from: $0) }

            // Detect a 4-row ColdFusion course header table:
            // Row 1: [Student Name, School Year (YYYY-YYYY), Teacher Name]
            // Row 2: [Course Code, Term (e.g. Q2), Grading Mode (MIXED/PERCENT/POINTS)]
            // Row 3: [Course Name]
            if rows.count == 4,
               rows[1].count == 3,
               rows[2].count == 3,
               isSchoolYearToken(rows[1][1])
            {
                if let finishedCourse = currentCourse {
                    courses.append(finalizeCourse(finishedCourse))
                }

                let schoolYear = rows[1][1]
                let teacherName = rows[1][2]
                let courseCode = rows[2][0]
                let term = rows[2][1]
                let courseTitle = rows[3].first(where: { !$0.isEmpty }) ?? courseCode

                if detectedYear == nil { detectedYear = schoolYear }
                if detectedTerm == nil { detectedTerm = term }

                currentCourse = ImportedCourse(
                    courseName: courseTitle,
                    courseCode: courseCode.isEmpty ? nil : courseCode,
                    teacherName: teacherName.isEmpty ? nil : teacherName,
                    term: term.isEmpty ? nil : term,
                    numericAverage: nil,
                    letterGrade: nil,
                    assignments: [],
                    categories: []
                )
                currentCategory = "General"
                continue
            }

            guard var activeCourse = currentCourse else {
                continue
            }

            for cells in rows {
                guard !cells.isEmpty, cells.contains(where: { !$0.isEmpty }) else {
                    continue
                }

                // Category header row: ["Homework", "", "Weight = 30.0"]
                if cells.count == 3, cells[2].lowercased().hasPrefix("weight") {
                    let catName = cells[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !catName.isEmpty {
                        currentCategory = catName
                        let weightVal = parseWeightValue(cells[2])
                        if !activeCourse.categories.contains(where: { $0.name == catName }) {
                            activeCourse.categories.append(
                                CategoryBreakdown(name: catName, weight: weightVal, average: nil)
                            )
                        }
                    }
                    continue
                }

                let firstCell = cells[0]

                // Column header row
                if firstCell.caseInsensitiveCompare("Assignment") == .orderedSame,
                   cells.count >= 4,
                   cells[1].caseInsensitiveCompare("Pts") == .orderedSame
                {
                    continue
                }

                // Category Average summary row: ["Category Average", "81.83", ""]
                if firstCell.caseInsensitiveCompare("Category Average") == .orderedSame {
                    if cells.count >= 2,
                       let avg = parseNumericValue(cells[1]),
                       let idx = activeCourse.categories.lastIndex(where: { $0.name == currentCategory })
                    {
                        activeCourse.categories[idx].average = avg
                    }
                    continue
                }

                // Term Grade summary row: ["Term Grade", "93", "A"]
                if firstCell.caseInsensitiveCompare("Term Grade") == .orderedSame {
                    if cells.count >= 2, let avg = parseNumericValue(cells[1]) {
                        activeCourse.numericAverage = avg
                    }
                    if cells.count >= 3, !cells[2].isEmpty {
                        activeCourse.letterGrade = cells[2]
                    }
                    continue
                }

                // Assignment data row: ["5.2 day 1", "91.0", "100.0", "91.0", "Valid", "10/13", ...]
                if cells.count >= 6, !firstCell.isEmpty {
                    let title = firstCell
                    let ptsEarned = parseNumericValue(cells[1])
                    let ptsMax = parseNumericValue(cells[2])
                    let avgPct = parsePercentageValue(cells[3]) ?? computePercentage(earned: ptsEarned, possible: ptsMax)
                    let status = cells[4].isEmpty ? nil : cells[4]
                    let due = cells[5].isEmpty ? nil : cells[5]
                    let note = cells.last?.isEmpty == false && cells.count >= 10 ? cells.last : nil
                    let isPending = ptsEarned == nil && avgPct == nil

                    activeCourse.assignments.append(
                        ImportedAssignment(
                            title: title,
                            category: currentCategory,
                            dueDate: due,
                            pointsEarned: ptsEarned,
                            pointsPossible: ptsMax,
                            percentage: avgPct,
                            status: status,
                            note: note,
                            isCompleted: !isPending
                        )
                    )
                }
            }

            currentCourse = activeCourse
        }

        if let finishedCourse = currentCourse {
            courses.append(finalizeCourse(finishedCourse))
        }

        return ImportedGradeReport(
            term: detectedTerm,
            schoolYear: detectedYear,
            courses: courses
        )
    }

    private static func finalizeCourse(_ course: ImportedCourse) -> ImportedCourse {
        var updated = course
        if updated.numericAverage == nil {
            let catAvgs = updated.categories.compactMap(\.average)
            if !catAvgs.isEmpty {
                updated.numericAverage = catAvgs.reduce(0, +) / Double(catAvgs.count)
            } else {
                let itemPcts = updated.assignments.compactMap(\.percentage)
                if !itemPcts.isEmpty {
                    updated.numericAverage = itemPcts.reduce(0, +) / Double(itemPcts.count)
                }
            }
        }
        if updated.letterGrade == nil, let avg = updated.numericAverage {
            updated.letterGrade = inferLetterGrade(for: avg)
        }
        return updated
    }

    // MARK: - Low-Level Extraction Helpers

    private static func isSchoolYearToken(_ text: String) -> Bool {
        let bytes = Array(text.utf8)
        guard bytes.count == 9, bytes[4] == UInt8(ascii: "-") else { return false }
        for (idx, b) in bytes.enumerated() where idx != 4 {
            if b < UInt8(ascii: "0") || b > UInt8(ascii: "9") {
                return false
            }
        }
        return true
    }

    private static func extractFirstSubstring(in source: String, after startToken: String, before endToken: String) -> String? {
        guard let startRange = source.range(of: startToken) else { return nil }
        let suffix = source[startRange.upperBound...]
        guard let endRange = suffix.range(of: endToken) else { return nil }
        return String(suffix[..<endRange.lowerBound])
    }

    private static func extractTagContent(in source: String, classMarker: String) -> String? {
        guard let markerRange = source.range(of: classMarker, options: [.caseInsensitive]) else {
            return nil
        }
        let afterMarker = source[markerRange.upperBound...]
        guard let openBracketEnd = afterMarker.firstIndex(of: ">") else {
            return nil
        }
        let contentStart = afterMarker.index(after: openBracketEnd)
        let remaining = afterMarker[contentStart...]
        let endIndex = remaining.range(of: "</td", options: [.caseInsensitive])?.lowerBound
            ?? remaining.range(of: "</div", options: [.caseInsensitive])?.lowerBound
            ?? remaining.endIndex
        let rawContent = String(remaining[..<endIndex])
        return cleanHTMLText(rawContent)
    }

    private static func extractBlocks(from html: String, openTag: String, closeTag: String) -> [String] {
        var results: [String] = []
        var searchStart = html.startIndex

        while let openRange = html.range(of: openTag, options: [.caseInsensitive], range: searchStart..<html.endIndex) {
            guard let closeRange = html.range(
                of: closeTag,
                options: [.caseInsensitive],
                range: openRange.upperBound..<html.endIndex
            ) else {
                break
            }
            results.append(String(html[openRange.lowerBound..<closeRange.upperBound]))
            searchStart = closeRange.upperBound
        }

        return results
    }

    private static func extractTableRows(from tableHTML: String) -> [String] {
        extractBlocks(from: tableHTML, openTag: "<tr", closeTag: "</tr>")
    }

    /// Extracts cell text from a `<tr>...</tr>` block, handling ColdFusion's malformed `</td` without closing `>`.
    private static func extractTableCells(from rowHTML: String) -> [String] {
        var cells: [String] = []
        var cursor = rowHTML.startIndex

        while cursor < rowHTML.endIndex {
            guard let tdStart = findNextCellStart(in: rowHTML, from: cursor) else {
                break
            }
            guard let tagClose = rowHTML[tdStart...].firstIndex(of: ">") else {
                break
            }
            let contentStart = rowHTML.index(after: tagClose)
            let remainder = rowHTML[contentStart...]

            let contentEnd: String.Index
            if let closeTD = remainder.range(of: "</t", options: [.caseInsensitive]) {
                contentEnd = closeTD.lowerBound
                if let closeTagEnd = remainder[closeTD.lowerBound...].firstIndex(of: ">") {
                    cursor = remainder.index(after: closeTagEnd)
                } else {
                    cursor = closeTD.upperBound
                }
            } else if let nextTD = findNextCellStart(in: rowHTML, from: contentStart) {
                contentEnd = nextTD
                cursor = nextTD
            } else {
                contentEnd = rowHTML.endIndex
                cursor = rowHTML.endIndex
            }

            let rawCell = String(rowHTML[contentStart..<contentEnd])
            cells.append(cleanHTMLText(rawCell))
        }

        return cells
    }

    private static func findNextCellStart(in rowHTML: String, from start: String.Index) -> String.Index? {
        var searchIndex = start
        while searchIndex < rowHTML.endIndex {
            guard let ltIndex = rowHTML[searchIndex...].firstIndex(of: "<") else {
                return nil
            }
            let afterLt = rowHTML.index(after: ltIndex)
            if afterLt < rowHTML.endIndex {
                let slice = rowHTML[afterLt...]
                if slice.lowercased().hasPrefix("td") || slice.lowercased().hasPrefix("th") {
                    let thirdIndex = rowHTML.index(afterLt, offsetBy: 2, limitedBy: rowHTML.endIndex) ?? rowHTML.endIndex
                    if thirdIndex < rowHTML.endIndex {
                        let nextChar = rowHTML[thirdIndex]
                        if nextChar == ">" || nextChar == " " || nextChar == "\t" || nextChar == "\r" || nextChar == "\n" {
                            return ltIndex
                        }
                    }
                }
            }
            searchIndex = afterLt
        }
        return nil
    }

    private static func cleanHTMLText(_ raw: String) -> String {
        // Strip HTML tags
        var stripped = ""
        stripped.reserveCapacity(raw.utf8.count)
        var insideTag = false
        for ch in raw {
            if ch == "<" {
                insideTag = true
            } else if ch == ">" {
                insideTag = false
            } else if !insideTag {
                stripped.append(ch)
            }
        }

        let decoded = decodeHTMLEntities(stripped)
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return decoded
    }

    public static func decodeHTMLEntities(_ input: String) -> String {
        guard input.contains("&") else { return input }
        var result = input
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&mdash;", with: "—")
            .replacingOccurrences(of: "&ndash;", with: "–")

        // Numeric entities &#NNN;
        if result.contains("&#"),
           let regex = try? NSRegularExpression(pattern: #"&#(\d+);"#, options: [])
        {
            let matches = regex.matches(in: result, options: [], range: NSRange(result.startIndex..<result.endIndex, in: result))
            for match in matches.reversed() {
                if let codeRange = Range(match.range(at: 1), in: result),
                   let fullRange = Range(match.range(at: 0), in: result),
                   let codePoint = UInt32(result[codeRange]),
                   let scalar = UnicodeScalar(codePoint)
                {
                    result.replaceSubrange(fullRange, with: String(Character(scalar)))
                }
            }
        }

        return result
    }

    /// Parses strings like `"94.5% (A)"`, `"102.5% (A+)"`, or `"88.0%"` into `(numericAverage, letterGrade)`.
    private static func parseCourseGradeSummary(_ text: String) -> (Double?, String?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (nil, nil) }

        var letter: String?
        if let openParen = trimmed.firstIndex(of: "("),
           let closeParen = trimmed[openParen...].firstIndex(of: ")"),
           openParen < closeParen
        {
            let inside = trimmed[trimmed.index(after: openParen)..<closeParen]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !inside.isEmpty {
                letter = inside
            }
        }

        let numericPart = trimmed
            .components(separatedBy: "(")
            .first?
            .replacingOccurrences(of: "%", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let numeric = Double(numericPart)
        if letter == nil, let numeric {
            letter = inferLetterGrade(for: numeric)
        }
        return (numeric, letter)
    }

    private static func parseWeightValue(_ text: String) -> Double? {
        let cleaned = text
            .replacingOccurrences(of: "Weight", with: "", options: [.caseInsensitive])
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "%", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(cleaned)
    }

    private static func parseNumericValue(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned != "--", cleaned != "-" else { return nil }
        return Double(cleaned)
    }

    private static func parsePercentageValue(_ text: String) -> Double? {
        let cleaned = text
            .replacingOccurrences(of: "%", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned != "--", cleaned != "-" else { return nil }
        return Double(cleaned)
    }

    private static func computePercentage(earned: Double?, possible: Double?) -> Double? {
        guard let earned, let possible, possible > 0 else { return nil }
        return (earned / possible) * 100.0
    }

    public static func inferLetterGrade(for average: Double) -> String {
        switch average {
        case 97.0...: return "A+"
        case 93.0..<97.0: return "A"
        case 90.0..<93.0: return "A-"
        case 87.0..<90.0: return "B+"
        case 83.0..<87.0: return "B"
        case 80.0..<83.0: return "B-"
        case 77.0..<80.0: return "C+"
        case 73.0..<77.0: return "C"
        case 70.0..<73.0: return "C-"
        case 67.0..<70.0: return "D+"
        case 63.0..<67.0: return "D"
        case 60.0..<63.0: return "D-"
        default: return "F"
        }
    }
}
