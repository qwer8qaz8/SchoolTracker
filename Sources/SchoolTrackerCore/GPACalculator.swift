import Foundation

// MARK: - Faith Lutheran High School (FLHS) GPA & Honor Roll Calculator

public enum GPACalculator {
    /// Total academic credits required for FLHS graduation.
    public static let graduationCreditsRequired: Double = 32.0

    /// Default credit awarded per passing semester course (>= 70).
    public static let defaultSemesterCourseCredit: Double = 0.50

    /// Converts a numeric grade into unweighted GPA points according to the FLHS handbook scale.
    public static func unweightedPoints(for score: Double) -> Double {
        switch score {
        case 97.0...:
            return 4.0
        case 93.0..<97.0:
            return 3.8
        case 90.0..<93.0:
            return 3.6
        case 87.0..<90.0:
            return 3.4
        case 83.0..<87.0:
            return 3.2
        case 80.0..<83.0:
            return 3.0
        case 77.0..<80.0:
            return 2.8
        case 73.0..<77.0:
            return 2.6
        case 71.0..<73.0:
            return 2.4
        case 70.0..<71.0:
            return 2.0
        default:
            return 0.0
        }
    }

    /// Converts a numeric grade and weight tier into weighted GPA points.
    public static func weightedPoints(for score: Double, tier: CourseWeightTier) -> Double {
        guard score >= 70.0 else { return 0.0 }
        let base = unweightedPoints(for: score)
        return base + tier.weightBonus
    }

    /// Infers handbook letter grade for a numeric score.
    public static func letterGrade(for score: Double) -> String {
        switch score {
        case 90.0...:
            return "A"
        case 80.0..<90.0:
            return "B"
        case 71.0..<80.0:
            return "C"
        case 70.0..<71.0:
            return "D"
        default:
            return "F"
        }
    }

    /// Computes full GPASummary (unweighted GPA, weighted GPA, credits, Honor Roll) for a list of courses.
    public static func calculateGPA(
        for courses: [ImportedCourse],
        creditPerCourse: Double = defaultSemesterCourseCredit
    ) -> GPASummary {
        let gradedCourses = courses.filter { $0.numericAverage != nil }
        guard !gradedCourses.isEmpty else {
            return GPASummary()
        }

        var totalUnweightedPoints: Double = 0.0
        var totalWeightedPoints: Double = 0.0
        var earnedCredits: Double = 0.0
        let totalAttempted = Double(gradedCourses.count) * creditPerCourse

        for course in gradedCourses {
            let score = course.numericAverage ?? 0.0
            let tier = course.effectiveWeightTier
            let unweighted = unweightedPoints(for: score)
            let weighted = weightedPoints(for: score, tier: tier)

            totalUnweightedPoints += unweighted
            totalWeightedPoints += weighted

            if score >= 70.0 {
                earnedCredits += creditPerCourse
            }
        }

        let count = Double(gradedCourses.count)
        let unweightedGPA = (totalUnweightedPoints / count * 100.0).rounded() / 100.0
        let weightedGPA = (totalWeightedPoints / count * 100.0).rounded() / 100.0

        let honorRoll = evaluateHonorRoll(courses: gradedCourses, weightedGPA: weightedGPA)

        return GPASummary(
            unweightedGPA: unweightedGPA,
            weightedGPA: weightedGPA,
            earnedCredits: earnedCredits,
            totalCreditsAttempted: totalAttempted,
            honorRollStatus: honorRoll
        )
    }

    /// Evaluates Honor Roll recognition per handbook rules:
    /// - Passing grades (>= 70) in ALL courses required.
    /// - Principal's Honor Roll: All A's (>= 90) AND weighted GPA >= 4.00.
    /// - Honor Roll: All A's and B's (>= 80) AND weighted GPA >= 3.75.
    /// - Merit Roll: All A's and B's (>= 80) AND weighted GPA >= 3.25.
    public static func evaluateHonorRoll(
        courses: [ImportedCourse],
        weightedGPA: Double
    ) -> HonorRollStatus {
        let scores = courses.compactMap(\.numericAverage)
        guard !scores.isEmpty else { return .none }

        // Must have passing grades in all courses
        guard scores.allSatisfy({ $0 >= 70.0 }) else {
            return .none
        }

        let allAs = scores.allSatisfy { $0 >= 90.0 }
        let allAsAndBs = scores.allSatisfy { $0 >= 80.0 }

        if allAs && weightedGPA >= 4.00 {
            return .principalsHonorRoll
        }
        if allAsAndBs && weightedGPA >= 3.75 {
            return .honorRoll
        }
        if allAsAndBs && weightedGPA >= 3.25 {
            return .meritRoll
        }

        return .none
    }

    /// Computes semester grades by averaging two grading periods (quarters) per FLHS handbook.
    public static func computeSemesterCourses(
        quarter1: [ImportedCourse],
        quarter2: [ImportedCourse],
        semesterTermName: String = "Semester 1"
    ) -> [ImportedCourse] {
        var merged: [ImportedCourse] = []
        var usedQ2IDs = Set<UUID>()

        for q1Course in quarter1 {
            let matchedQ2 = quarter2.first { q2 in
                !usedQ2IDs.contains(q2.id)
                    && (
                        (q1Course.courseCode?.isEmpty == false && q1Course.courseCode?.caseInsensitiveCompare(q2.courseCode ?? "") == .orderedSame)
                        || q1Course.courseName.caseInsensitiveCompare(q2.courseName) == .orderedSame
                    )
            }

            var semesterCourse = q1Course
            semesterCourse.id = UUID()
            semesterCourse.term = semesterTermName

            if let q2 = matchedQ2 {
                usedQ2IDs.insert(q2.id)
                if let score1 = q1Course.numericAverage, let score2 = q2.numericAverage {
                    let avg = ((score1 + score2) / 2.0 * 10.0).rounded() / 10.0
                    semesterCourse.numericAverage = avg
                    semesterCourse.letterGrade = letterGrade(for: avg)
                } else {
                    semesterCourse.numericAverage = q1Course.numericAverage ?? q2.numericAverage
                    if let avg = semesterCourse.numericAverage {
                        semesterCourse.letterGrade = letterGrade(for: avg)
                    }
                }
                semesterCourse.assignments = q1Course.assignments + q2.assignments
            } else {
                semesterCourse.numericAverage = q1Course.numericAverage
                if let avg = semesterCourse.numericAverage {
                    semesterCourse.letterGrade = letterGrade(for: avg)
                }
            }

            merged.append(semesterCourse)
        }

        // Add any Q2 courses that were not in Q1
        for q2Course in quarter2 where !usedQ2IDs.contains(q2Course.id) {
            var semCourse = q2Course
            semCourse.id = UUID()
            semCourse.term = semesterTermName
            merged.append(semCourse)
        }

        return merged
    }
}
