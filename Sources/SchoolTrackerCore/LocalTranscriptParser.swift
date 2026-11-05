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
    /// Parses transcript or report card text on-device into a TermSnapshot and list of ImportedCourse.
    public static func parseTranscriptText(
        _ text: String,
        defaultSchoolYear: String = "2026-2027",
        defaultTerm: String = "Semester 1"
    ) throws -> (snapshot: TermSnapshot, courses: [ImportedCourse]) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TranscriptParseError.noTextFound
        }

        let schoolYear = extractSchoolYear(from: trimmed) ?? defaultSchoolYear
        let termName = extractTermName(from: trimmed) ?? defaultTerm

        let rawLines = trimmed.components(separatedBy: .newlines)
        var courses: [ImportedCourse] = []

        // Pattern 1: Tabular format: Code (optional) | Name | Grade | Credits (optional) | Tier (optional)
        // e.g. "THEO 11      Christian Doctrine III          94.0   0.50     Regular"
        let tabularPattern = try! NSRegularExpression(
            pattern: #"^\s*([A-Z]{2,8}(?:\s+[0-9A-ZIV]+)?)\s{2,}(.+?)\s{2,}([0-9]{1,3}(?:\.[0-9]+)?%?)(?:\s+([0-9]+(?:\.[0-9]+)?))?(?:\s+([A-Za-z\.\/\s]+))?$"#,
            options: [.anchorsMatchLines]
        )

        // Pattern 2: Flexible code/name + grade e.g. "Math 184 - Calculus I: 95.0%" or "Biology H 88.0"
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
                  !lineTrimmed.lowercased().hasPrefix("school year:")
            else { continue }

            let nsLine = line as NSString
            let fullRange = NSRange(location: 0, length: nsLine.length)

            if let match = tabularPattern.firstMatch(in: line, options: [], range: fullRange) {
                let code = match.range(at: 1).location != NSNotFound ? nsLine.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines) : nil
                let name = nsLine.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
                let gradeStr = nsLine.substring(with: match.range(at: 3)).replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                let tierStr = match.range(at: 5).location != NSNotFound ? nsLine.substring(with: match.range(at: 5)).trimmingCharacters(in: .whitespacesAndNewlines) : nil

                if let grade = Double(gradeStr), grade >= 0.0 && grade <= 150.0 {
                    let tier = resolveWeightTier(tierString: tierStr, courseName: name, courseCode: code)
                    let course = ImportedCourse(
                        courseName: name,
                        courseCode: code,
                        term: termName,
                        numericAverage: grade,
                        letterGrade: GPACalculator.letterGrade(for: grade),
                        weightTier: tier
                    )
                    courses.append(course)
                    continue
                }
            }

            if let match = flexiblePattern.firstMatch(in: line, options: [], range: fullRange) {
                let code = match.range(at: 1).location != NSNotFound ? nsLine.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines) : nil
                let name = nsLine.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
                let gradeStr = nsLine.substring(with: match.range(at: 3)).replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespacesAndNewlines)

                guard !name.lowercased().contains("official academic"),
                      !name.lowercased().contains("credits earned"),
                      !name.lowercased().contains("unweighted gpa"),
                      !name.lowercased().contains("weighted gpa")
                else { continue }

                if let grade = Double(gradeStr), grade >= 0.0 && grade <= 150.0 {
                    let tier = CourseWeightTier.inferTier(courseName: name, courseCode: code)
                    let course = ImportedCourse(
                        courseName: name,
                        courseCode: code,
                        term: termName,
                        numericAverage: grade,
                        letterGrade: GPACalculator.letterGrade(for: grade),
                        weightTier: tier
                    )
                    courses.append(course)
                }
            }
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

        return (snapshot, courses)
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
                // Scanned page: render to image and use Vision OCR
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
    public static func parseDocument(at fileURL: URL) throws -> (snapshot: TermSnapshot, courses: [ImportedCourse]) {
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

        return try parseTranscriptText(text)
    }

    private static func extractSchoolYear(from text: String) -> String? {
        let pattern = try! NSRegularExpression(pattern: #"School Year:\s*([0-9]{4}-[0-9]{4})"#, options: [.caseInsensitive])
        let ns = text as NSString
        if let match = pattern.firstMatch(in: text, options: [], range: NSRange(location: 0, length: ns.length)) {
            return ns.substring(with: match.range(at: 1))
        }
        return nil
    }

    private static func extractTermName(from text: String) -> String? {
        let pattern = try! NSRegularExpression(pattern: #"Term:\s*([A-Za-z0-9\s]+?)(?:\||\n|$)"#, options: [.caseInsensitive])
        let ns = text as NSString
        if let match = pattern.firstMatch(in: text, options: [], range: NSRange(location: 0, length: ns.length)) {
            let raw = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !raw.isEmpty { return raw }
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
