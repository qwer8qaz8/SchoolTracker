import Foundation
import PDFKit
import Vision

// MARK: - On-Device Apple Intelligence / Vision & PDFKit Transcript Parser

public enum TranscriptParseError: Error, Equatable, LocalizedError, Sendable {
    case fileNotFound(String)
    case unreadableDocument(String)
    case noTextFound
    case noCoursesParsed

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "File not found at \(path)"
        case .unreadableDocument(let reason):
            return "Cannot read document: \(reason)"
        case .noTextFound:
            return "No text could be extracted from document via PDFKit or Apple Vision OCR."
        case .noCoursesParsed:
            return "Could not parse any course or grade entries from document text."
        }
    }
}

public enum LocalTranscriptParser {
    /// Parses transcript or report card text on-device into a primary TermSnapshot, list of ImportedCourse, and all historical snapshots.
    /// Elementary/middle school courses (grades 1–8) and non-academic courses (Homeroom, Chapel, etc.)
    /// are parsed with `countsTowardGraduation = false` and `countsTowardGPA = false`, awarding 0.0 credits.
    public static func parseTranscriptTextFull(
        _ text: String,
        defaultSchoolYear: String = "2026-2027",
        defaultTerm: String = "Semester 1",
        filterElementaryCourses: Bool = false
    ) throws -> (snapshot: TermSnapshot, courses: [ImportedCourse], allSnapshots: [TermSnapshot]) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TranscriptParseError.noTextFound
        }

        // Strategy 1: Multi-year FACTS SIS Transcript export (e.g. "FACTS SIS_ Family Portal.pdf")
        if let factsResult = parseFactsSISTranscript(trimmed, filterElementaryCourses: filterElementaryCourses) {
            return factsResult
        }

        // Strategy 2: RenWeb / FACTS Report Card (e.g. "Report.pdf", handles line-wrapping across table cells)
        if let reportResult = parseRenWebReportCard(trimmed, filterElementaryCourses: filterElementaryCourses) {
            return reportResult
        }

        // Strategy 3: Tabular / flexible line-by-line fallback
        return try parseTabularTranscript(
            trimmed,
            defaultSchoolYear: defaultSchoolYear,
            defaultTerm: defaultTerm,
            filterElementaryCourses: filterElementaryCourses
        )
    }

    /// Convenience wrapper returning (snapshot, courses) for backwards compatibility.
    public static func parseTranscriptText(
        _ text: String,
        defaultSchoolYear: String = "2026-2027",
        defaultTerm: String = "Semester 1",
        filterElementaryCourses: Bool = false
    ) throws -> (snapshot: TermSnapshot, courses: [ImportedCourse]) {
        let full = try parseTranscriptTextFull(
            text,
            defaultSchoolYear: defaultSchoolYear,
            defaultTerm: defaultTerm,
            filterElementaryCourses: filterElementaryCourses
        )
        return (full.snapshot, full.courses)
    }

    // MARK: - Strategy 1: FACTS SIS Multi-Year Transcript Parser

    private static func parseFactsSISTranscript(
        _ text: String,
        filterElementaryCourses: Bool
    ) -> (snapshot: TermSnapshot, courses: [ImportedCourse], allSnapshots: [TermSnapshot])? {
        guard text.contains("Transcripts") || text.range(of: #"20\d{2}-20\d{2}\s+(?:Sem|Semester|Q|Quarter)\s+\d+"#, options: .regularExpression) != nil else {
            return nil
        }

        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        guard let yearPrefixRegex = try? NSRegularExpression(pattern: #"^(20\d{2}-20\d{2})\s+(Sem\s+\d+|Q\d+|Quarter\s+\d+|Semester\s+\d+)\s+"#),
              let fullRowRegex = try? NSRegularExpression(pattern: #"^(20\d{2}-20\d{2})\s+(Sem\s+\d+|Q\d+|Quarter\s+\d+|Semester\s+\d+)\s+(.+?)\s+([0-9]{1,3}(?:\.[0-9]+)?|[A-DFP][+-]?)\s+([0-9]+\.[0-9]{1,4}|[01](?:\.0+)?)\s+(.+)$"#)
        else { return nil }

        struct Row {
            let year: String
            let term: String
            let course: String
            let grade: Double?
            let letter: String?
            let credits: Double
            let teacher: String
        }

        var rows: [Row] = []
        var idx = 0
        while idx < lines.count {
            var line = lines[idx]
            let ns = line as NSString
            if yearPrefixRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) != nil {
                while idx + 1 < lines.count {
                    let next = lines[idx + 1]
                    if next.isEmpty || next.hasPrefix("11/5/26") || next.hasPrefix("https://") || next.contains("Transcripts") || next.contains("Credits Earned") || yearPrefixRegex.firstMatch(in: next, range: NSRange(location: 0, length: (next as NSString).length)) != nil {
                        break
                    }
                    line += " " + next
                    idx += 1
                }
                let nsRow = line as NSString
                if let m = fullRowRegex.firstMatch(in: line, range: NSRange(location: 0, length: nsRow.length)) {
                    let year = nsRow.substring(with: m.range(at: 1))
                    let term = normalizeTermString(nsRow.substring(with: m.range(at: 2)))
                    let course = nsRow.substring(with: m.range(at: 3)).trimmingCharacters(in: .whitespaces)
                    let gradeStr = nsRow.substring(with: m.range(at: 4))
                    let creditStr = nsRow.substring(with: m.range(at: 5))
                    let teacher = nsRow.substring(with: m.range(at: 6)).trimmingCharacters(in: .whitespaces)

                    let num = Double(gradeStr)
                    let letter = num == nil ? gradeStr : GPACalculator.letterGrade(for: num!)
                    let credits = Double(creditStr) ?? 0.50
                    rows.append(Row(year: year, term: term, course: course, grade: num, letter: letter, credits: credits, teacher: teacher))
                }
            }
            idx += 1
        }

        guard !rows.isEmpty else { return nil }

        // Group rows into chronological terms
        var termKeys: [String] = []
        var termBuckets: [String: [Row]] = [:]
        for r in rows {
            let key = "\(r.year)||\(r.term)"
            if termBuckets[key] == nil {
                termKeys.append(key)
            }
            termBuckets[key, default: []].append(r)
        }

        var allSnapshots: [TermSnapshot] = []
        for key in termKeys {
            let parts = key.components(separatedBy: "||")
            let schoolYear = parts[0]
            let termName = parts[1]
            let bucketRows = termBuckets[key] ?? []

            var importedCourses: [ImportedCourse] = []
            for r in bucketRows {
                let isExcluded = ImportedCourse.isExcludedFromHighSchool(
                    courseName: r.course,
                    courseCode: nil,
                    term: r.term,
                    schoolYear: r.year
                )
                let tier = CourseWeightTier.inferTier(courseName: r.course, courseCode: nil)
                let c = ImportedCourse(
                    courseName: r.course,
                    courseCode: nil,
                    teacherName: r.teacher.isEmpty ? nil : r.teacher,
                    term: r.term,
                    numericAverage: r.grade,
                    letterGrade: r.letter,
                    weightTier: tier,
                    creditHours: isExcluded ? 0.0 : r.credits,
                    countsTowardGraduation: !isExcluded,
                    countsTowardGPA: !isExcluded
                )
                importedCourses.append(c)
            }

            if filterElementaryCourses {
                importedCourses = importedCourses.filter { $0.countsTowardGraduation || $0.countsTowardGPA }
            }

            let gpa = GPACalculator.calculateGPA(for: importedCourses)
            let snapshot = TermSnapshot(
                schoolYear: schoolYear,
                termName: termName,
                syncedAt: Date(),
                gpaSummary: gpa,
                courses: importedCourses,
                source: "facts-sis-transcript"
            )
            allSnapshots.append(snapshot)
        }

        guard !allSnapshots.isEmpty else { return nil }

        // Liam is in high school (9th grade in 2024-2025, 10th in 2025-2026, 11th in 2026-2027)
        // Set the primary snapshot to the most recent high school term
        let hsSnapshots = allSnapshots.filter { $0.schoolYear >= "2024-2025" }
        let primarySnapshot = hsSnapshots.last ?? allSnapshots.last!

        return (snapshot: primarySnapshot, courses: primarySnapshot.courses, allSnapshots: allSnapshots)
    }

    // MARK: - Strategy 2: RenWeb / FACTS Report Card Parser

    private static func parseRenWebReportCard(
        _ text: String,
        filterElementaryCourses: Bool
    ) -> (snapshot: TermSnapshot, courses: [ImportedCourse], allSnapshots: [TermSnapshot])? {
        let lower = text.lowercased()
        guard lower.contains("report card") || lower.contains("fourtermsemnoconduct") || lower.contains("rse name") || lower.contains("semester 1") else {
            return nil
        }

        var schoolYear = "2026-2027"
        var termName = "Quarter 2"
        let yearTermRegex = try? NSRegularExpression(pattern: #"(20\d{2}-20\d{2})\s*[-–—]\s*(Q[1-4]|Quarter\s*[1-4]|Sem\s*[12]|Semester\s*[12])"#, options: [.caseInsensitive])
        let nsText = text as NSString
        if let m = yearTermRegex?.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)) {
            schoolYear = nsText.substring(with: m.range(at: 1))
            termName = normalizeTermString(nsText.substring(with: m.range(at: 2)))
        }

        let rawLines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        guard let startIdx = rawLines.firstIndex(where: {
            $0.contains("SEMESTER 1") || $0.contains("RSE NAME") || $0.contains("COURSE") || $0.contains("GRADE")
        }) else { return nil }

        let endIdx = rawLines.firstIndex(where: {
            $0.contains("School Days") || ($0.contains("Total") && $0.contains("1 2 3 4")) || $0.contains("Times Tardy")
        }) ?? rawLines.count

        var idx = startIdx + 1
        while idx < endIdx && (rawLines[idx].contains("EXAM") || rawLines[idx].contains("GRADE") || rawLines[idx].contains("SEMESTER") || rawLines[idx].contains("FINAL")) {
            idx += 1
        }

        var mergedLines: [String] = []
        while idx < endIdx {
            let current = rawLines[idx]
            if current.hasPrefix("1 2 3 4") || current.hasPrefix("School Days") { break }

            if idx + 1 < endIdx {
                let next = rawLines[idx + 1]
                let endsWithScorePattern = #"^(?:[A-Z]{1,4}\s+)?([0-9]{1,3}(?:\.[0-9]+)?|[A-DFP][+-]?)$"#
                let hasNumberInCurrent = current.range(of: #"[0-9]{1,3}"#, options: .regularExpression) != nil
                if next.range(of: endsWithScorePattern, options: .regularExpression) != nil && !hasNumberInCurrent {
                    mergedLines.append(current + " " + next)
                    idx += 2
                    continue
                }
            }
            mergedLines.append(current)
            idx += 1
        }

        guard let courseScoreRegex = try? NSRegularExpression(pattern: #"^([A-Z0-9\s\.\-\/\&]+?)\s+([0-9]{1,3}(?:\.[0-9]+)?|[A-DFP][+-]?)$"#) else {
            return nil
        }

        var courses: [ImportedCourse] = []
        var currentName: String?
        var currentGrade: Double?
        var currentLetter: String?
        var teacherLines: [String] = []

        func commit() {
            guard let name = currentName else { return }
            let rawTeacher = teacherLines.joined(separator: " ")
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .replacingOccurrences(of: "M RS.", with: "Mrs.")
                .replacingOccurrences(of: "M R .", with: "Mr.")
                .replacingOccurrences(of: "MISS R OUNDEY", with: "Miss Roundey")
                .replacingOccurrences(of: "M R. ", with: "Mr. ")
                .replacingOccurrences(of: "MRS.", with: "Mrs.")
                .replacingOccurrences(of: "MR.", with: "Mr.")
                .replacingOccurrences(of: "MS.", with: "Ms.")
                .trimmingCharacters(in: .whitespaces)

            let isExcluded = ImportedCourse.isExcludedFromHighSchool(
                courseName: name,
                courseCode: nil,
                term: termName,
                schoolYear: schoolYear
            )
            let tier = CourseWeightTier.inferTier(courseName: name, courseCode: nil)

            let course = ImportedCourse(
                courseName: name,
                courseCode: nil,
                teacherName: rawTeacher.isEmpty ? nil : rawTeacher,
                term: termName,
                numericAverage: currentGrade,
                letterGrade: currentLetter ?? (currentGrade.map { GPACalculator.letterGrade(for: $0) }),
                weightTier: tier,
                creditHours: isExcluded ? 0.0 : GPACalculator.defaultSemesterCourseCredit,
                countsTowardGraduation: !isExcluded,
                countsTowardGPA: !isExcluded
            )
            courses.append(course)
            currentName = nil
            currentGrade = nil
            currentLetter = nil
            teacherLines = []
        }

        for l in mergedLines {
            let ns = l as NSString
            if let match = courseScoreRegex.firstMatch(in: l, range: NSRange(location: 0, length: ns.length)) {
                commit()
                let rawCourse = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
                let scoreStr = ns.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces)
                let cleanedName = rawCourse
                    .replacingOccurrences(of: "CO RE", with: "CORE")
                    .replacingOccurrences(of: "HISTO RY", with: "HISTORY")
                currentName = cleanedName
                if let num = Double(scoreStr) {
                    currentGrade = num
                    currentLetter = nil
                } else {
                    currentGrade = nil
                    currentLetter = scoreStr
                }
            } else {
                teacherLines.append(l)
            }
        }
        commit()

        if filterElementaryCourses {
            courses = courses.filter { $0.countsTowardGraduation || $0.countsTowardGPA }
        }

        guard !courses.isEmpty else { return nil }

        let gpa = GPACalculator.calculateGPA(for: courses)
        let snapshot = TermSnapshot(
            schoolYear: schoolYear,
            termName: termName,
            syncedAt: Date(),
            gpaSummary: gpa,
            courses: courses,
            source: "renweb-report-card"
        )

        return (snapshot: snapshot, courses: courses, allSnapshots: [snapshot])
    }

    // MARK: - Strategy 3: Tabular / Flexible Lines Parser

    private static func parseTabularTranscript(
        _ text: String,
        defaultSchoolYear: String,
        defaultTerm: String,
        filterElementaryCourses: Bool
    ) throws -> (snapshot: TermSnapshot, courses: [ImportedCourse], allSnapshots: [TermSnapshot]) {
        let schoolYear = extractSchoolYear(from: text) ?? defaultSchoolYear
        let termName = extractTermName(from: text) ?? defaultTerm

        let rawLines = text.components(separatedBy: .newlines)
        var courses: [ImportedCourse] = []
        var currentSectionHeader: String? = nil

        let sectionHeaderPattern = try! NSRegularExpression(
            pattern: #"^\s*(?:=+\s*|--+\s*)?(?:(kindergarten|pre-?k|elementary|middle\s+school|high\s+school)|(?:grade\s*([0-9]{1,2}))|(?:(1st|2nd|3rd|[4-9]th|1[0-2]th)\s+grade))\b"#,
            options: [.caseInsensitive]
        )

        let tabularPattern = try! NSRegularExpression(
            pattern: #"^\s*([A-Z]{2,8}(?:\s+[0-9A-ZIV]+)?)\s{2,}(.+?)\s{2,}([0-9]{1,3}(?:\.[0-9]+)?%?)(?:\s+([0-9]+(?:\.[0-9]+)?))?(?:\s+([A-Za-z\.\/\s]+))?$"#,
            options: [.anchorsMatchLines]
        )

        let flexiblePattern = try! NSRegularExpression(
            pattern: #"^\s*(?:([A-Z]{2,8}(?:\s+[0-9A-ZIV]+)?)\s*[-:]\s*)?([A-Za-z0-9\s\/\(\)]+?)\s*(?:[-:]|\s{2,}|\t)\s*([0-9]{1,3}(?:\.[0-9]+)?%?)(?:\s+([0-9]+(?:\.[0-9]+)?))?"#,
            options: [.anchorsMatchLines]
        )

        for line in rawLines {
            let lineTrimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !lineTrimmed.isEmpty,
                  !lineTrimmed.lowercased().hasPrefix("total"),
                  !lineTrimmed.lowercased().hasPrefix("semester"),
                  !lineTrimmed.lowercased().hasPrefix("honor roll"),
                  !lineTrimmed.lowercased().hasPrefix("course code"),
                  !lineTrimmed.lowercased().hasPrefix("student:"),
                  !lineTrimmed.lowercased().hasPrefix("school year:"),
                  !lineTrimmed.lowercased().hasPrefix("attendance:"),
                  !lineTrimmed.lowercased().hasPrefix("days absent:"),
                  !lineTrimmed.lowercased().hasPrefix("tardy:")
            else { continue }

            let nsLine = line as NSString
            let fullRange = NSRange(location: 0, length: nsLine.length)

            if sectionHeaderPattern.firstMatch(in: line, options: [], range: fullRange) != nil {
                currentSectionHeader = lineTrimmed
            }

            if let match = tabularPattern.firstMatch(in: line, options: [], range: fullRange) {
                let code = match.range(at: 1).location != NSNotFound ? nsLine.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines) : nil
                let name = nsLine.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
                let gradeStr = nsLine.substring(with: match.range(at: 3)).replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                let creditStr = match.range(at: 4).location != NSNotFound ? nsLine.substring(with: match.range(at: 4)).trimmingCharacters(in: .whitespacesAndNewlines) : nil
                let tierStr = match.range(at: 5).location != NSNotFound ? nsLine.substring(with: match.range(at: 5)).trimmingCharacters(in: .whitespacesAndNewlines) : nil

                if let grade = Double(gradeStr), grade >= 0.0 && grade <= 150.0 {
                    let isExcluded = ImportedCourse.isExcludedFromHighSchool(
                        courseName: name,
                        courseCode: code,
                        term: currentSectionHeader ?? termName,
                        schoolYear: schoolYear
                    )
                    let tier = resolveWeightTier(tierString: tierStr, courseName: name, courseCode: code)
                    let explicitCredits = creditStr.flatMap(Double.init)

                    let course = ImportedCourse(
                        courseName: name,
                        courseCode: code,
                        term: termName,
                        numericAverage: grade,
                        letterGrade: GPACalculator.letterGrade(for: grade),
                        weightTier: tier,
                        creditHours: isExcluded ? 0.0 : (explicitCredits ?? GPACalculator.defaultSemesterCourseCredit),
                        countsTowardGraduation: !isExcluded,
                        countsTowardGPA: !isExcluded
                    )
                    courses.append(course)
                    continue
                }
            }

            if let match = flexiblePattern.firstMatch(in: line, options: [], range: fullRange) {
                let code = match.range(at: 1).location != NSNotFound ? nsLine.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines) : nil
                let name = nsLine.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
                let gradeStr = nsLine.substring(with: match.range(at: 3)).replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                let creditStr = match.range(at: 4).location != NSNotFound ? nsLine.substring(with: match.range(at: 4)).trimmingCharacters(in: .whitespacesAndNewlines) : nil

                guard !name.lowercased().contains("official academic"),
                      !name.lowercased().contains("credits earned"),
                      !name.lowercased().contains("unweighted gpa"),
                      !name.lowercased().contains("weighted gpa")
                else { continue }

                if let grade = Double(gradeStr), grade >= 0.0 && grade <= 150.0 {
                    let isExcluded = ImportedCourse.isExcludedFromHighSchool(
                        courseName: name,
                        courseCode: code,
                        term: currentSectionHeader ?? termName,
                        schoolYear: schoolYear
                    )
                    let tier = CourseWeightTier.inferTier(courseName: name, courseCode: code)
                    let explicitCredits = creditStr.flatMap(Double.init)

                    let course = ImportedCourse(
                        courseName: name,
                        courseCode: code,
                        term: termName,
                        numericAverage: grade,
                        letterGrade: GPACalculator.letterGrade(for: grade),
                        weightTier: tier,
                        creditHours: isExcluded ? 0.0 : (explicitCredits ?? GPACalculator.defaultSemesterCourseCredit),
                        countsTowardGraduation: !isExcluded,
                        countsTowardGPA: !isExcluded
                    )
                    courses.append(course)
                }
            }
        }

        if filterElementaryCourses {
            courses = courses.filter { $0.countsTowardGraduation || $0.countsTowardGPA }
        }

        guard !courses.isEmpty else {
            throw TranscriptParseError.noCoursesParsed
        }

        let gpa = GPACalculator.calculateGPA(for: courses)
        let snapshot = TermSnapshot(
            schoolYear: schoolYear,
            termName: termName,
            syncedAt: Date(),
            gpaSummary: gpa,
            courses: courses,
            source: "local-transcript"
        )

        return (snapshot: snapshot, courses: courses, allSnapshots: [snapshot])
    }

    /// Extracts text from PDF using PDFKit, falling back to Vision OCR if pages are scanned bitmaps.
    public static func extractText(from pdfURL: URL) throws -> String {
        guard FileManager.default.fileExists(atPath: pdfURL.path) else {
            throw TranscriptParseError.fileNotFound(pdfURL.path)
        }

        guard let pdfDoc = PDFDocument(url: pdfURL) else {
            throw TranscriptParseError.unreadableDocument("PDFDocument could not open file at \(pdfURL.path)")
        }

        var fullText = ""
        let pageCount = pdfDoc.pageCount

        for i in 0..<pageCount {
            guard let page = pdfDoc.page(at: i) else { continue }
            if let str = page.string, str.trimmingCharacters(in: .whitespacesAndNewlines).count > 40 {
                fullText += str + "\n"
            } else {
                let bounds = page.bounds(for: .mediaBox)
                let renderer = ImageRenderer(bounds: bounds)
                if let cgImage = renderer.render(page: page) {
                    if let ocrText = try? performVisionOCR(on: cgImage) {
                        fullText += ocrText + "\n"
                    }
                }
            }
        }

        guard !fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranscriptParseError.noTextFound
        }
        return fullText
    }

    /// Performs on-device Apple Vision text recognition.
    public static func performVisionOCR(on cgImage: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        guard let observations = request.results else {
            return ""
        }

        let recognized = observations.compactMap { $0.topCandidates(1).first?.string }
        return recognized.joined(separator: "\n")
    }

    /// Parses an input document file (PDF or image) completely on-device.
    public static func parseDocument(at fileURL: URL) throws -> (snapshot: TermSnapshot, courses: [ImportedCourse], allSnapshots: [TermSnapshot]) {
        let ext = fileURL.pathExtension.lowercased()
        let text: String

        if ext == "pdf" {
            text = try extractText(from: fileURL)
        } else if ["png", "jpg", "jpeg", "heic", "tiff"].contains(ext) {
            guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else {
                throw TranscriptParseError.unreadableDocument("Could not read image file at \(fileURL.path)")
            }
            text = try performVisionOCR(on: image)
        } else {
            text = try String(contentsOf: fileURL, encoding: .utf8)
        }

        return try parseTranscriptTextFull(text)
    }

    private static func normalizeTermString(_ term: String) -> String {
        let t = term.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("Sem ") {
            return "Semester " + t.dropFirst(4)
        }
        if t.hasPrefix("Q") && t.count <= 3 {
            return "Quarter " + t.dropFirst(1)
        }
        return t
    }

    private static func extractSchoolYear(from text: String) -> String? {
        let patterns = [
            #"School Year:\s*([0-9]{4}-[0-9]{4})"#,
            #"(20[0-9]{2}-20[0-9]{2})\s*[-–—]\s*(?:Q|Quarter|Sem|Semester)"#,
            #"Year:\s*(20[0-9]{2}-20[0-9]{2})"#
        ]
        let ns = text as NSString
        for pat in patterns {
            if let regex = try? NSRegularExpression(pattern: pat, options: [.caseInsensitive]),
               let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: ns.length)) {
                return ns.substring(with: match.range(at: 1))
            }
        }
        return nil
    }

    private static func extractTermName(from text: String) -> String? {
        let patterns = [
            #"Term:\s*([A-Za-z0-9\s]+?)(?:\||\n|$)"#,
            #"[-–—]\s*(Q[1-4]|Quarter\s*[1-4]|Sem\s*[12]|Semester\s*[12])"#
        ]
        let ns = text as NSString
        for pat in patterns {
            if let regex = try? NSRegularExpression(pattern: pat, options: [.caseInsensitive]),
               let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: ns.length)) {
                let raw = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !raw.isEmpty { return normalizeTermString(raw) }
            }
        }
        return nil
    }

    private static func resolveWeightTier(tierString: String?, courseName: String, courseCode: String?) -> CourseWeightTier {
        if let tierString {
            let lower = tierString.lowercased()
            if lower.contains("adv") || lower.contains("dual") {
                return .advancedHonorsDualCredit
            }
            if lower.contains("honor") {
                return .honors
            }
            if lower.contains("reg") {
                return .regular
            }
        }
        return CourseWeightTier.inferTier(courseName: courseName, courseCode: courseCode)
    }
}

private final class ImageRenderer {
    let bounds: CGRect
    init(bounds: CGRect) { self.bounds = bounds }

    func render(page: PDFPage) -> CGImage? {
        let width = Int(bounds.width)
        let height = Int(bounds.height)
        guard width > 0, height > 0 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(bounds)
        page.draw(with: .mediaBox, to: context)
        return context.makeImage()
    }
}
