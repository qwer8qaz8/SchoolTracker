import Foundation

public enum AnonymizedReportFixtures {
    public static let validDistrict = "TEST-XX"
    public static let validSessionID = "00000000-0000-0000-0000-000000000000"
    public static let validReportURL =
        "https://test-xx.client.factsmgt.com/renweb/email/GetReport.cfm?District=TEST-XX&SessionID=00000000-0000-0000-0000-000000000000"

    /// Synthetic HTML matching FACTS/RenWeb GetReport.cfm gradebook progress report structure with zero PII.
    public static let validMultiCourseReportHTML = """
    <!DOCTYPE html>
    <html>
    <head><title>Gradebook Progress Report</title></head>
    <body>
      <div class="report-header">
        <h2>Student Progress Report</h2>
        <p>Student: Student, Test | Term: Q2</p>
      </div>
      <div class="course-section" data-course="AP Calculus BC">
        <table class="course-header">
          <tr>
            <td class="course-title">AP Calculus BC</td>
            <td class="course-teacher">Instructor, Demo A</td>
            <td class="course-grade">94.5% (A)</td>
          </tr>
        </table>
        <table class="assignments">
          <thead>
            <tr><th>Category</th><th>Assignment</th><th>Date</th><th>Pts</th><th>Max</th><th>Grade</th></tr>
          </thead>
          <tbody>
            <tr><td>Homework</td><td>Series Convergence Set 1</td><td>10/28/2026</td><td>19</td><td>20</td><td>95.0%</td></tr>
            <tr><td>Quiz</td><td>Taylor Polynomials Quiz</td><td>11/01/2026</td><td>47</td><td>50</td><td>94.0%</td></tr>
          </tbody>
        </table>
      </div>
      <div class="course-section" data-course="Honors Chemistry">
        <table class="course-header">
          <tr>
            <td class="course-title">Honors Chemistry</td>
            <td class="course-teacher">Instructor, Demo B</td>
            <td class="course-grade">88.0% (B+)</td>
          </tr>
        </table>
        <table class="assignments">
          <thead>
            <tr><th>Category</th><th>Assignment</th><th>Date</th><th>Pts</th><th>Max</th><th>Grade</th></tr>
          </thead>
          <tbody>
            <tr><td>Lab</td><td>Stoichiometry Lab &amp; Write-up</td><td>10/30/2026</td><td>44</td><td>50</td><td>88.0%</td></tr>
          </tbody>
        </table>
      </div>
    </body>
    </html>
    """

    /// Synthetic HTML representing an expired or invalid FACTS/RenWeb temporary email session.
    public static let expiredSessionHTML = """
    <!DOCTYPE html>
    <html>
    <head><title>Report Unavailable</title></head>
    <body>
      <div class="error-message">
        Your session has expired or the link is no longer valid. Please request a new report link from RenWeb/FACTS.
      </div>
    </body>
    </html>
    """

    /// Synthetic HTML with boundary conditions: 0%, >100% extra credit, pending/ungraded items, and HTML entities.
    public static let boundaryGradesReportHTML = """
    <!DOCTYPE html>
    <html>
    <body>
      <div class="course-section" data-course="Physics &amp; Engineering — Sec &lt;1&gt;">
        <table class="course-header">
          <tr>
            <td class="course-title">Physics &amp; Engineering — Sec &lt;1&gt;</td>
            <td class="course-teacher">O&#39;Connor, Pat</td>
            <td class="course-grade">102.5% (A+)</td>
          </tr>
        </table>
        <table class="assignments">
          <tbody>
            <tr><td>Test</td><td>Kinematics Exam (with Bonus)</td><td>10/15/2026</td><td>105</td><td>100</td><td>105.0%</td></tr>
            <tr><td>Homework</td><td>Missed Reading Check</td><td>10/18/2026</td><td>0</td><td>10</td><td>0.0%</td></tr>
            <tr><td>Project</td><td>Bridge Stress Analysis (Pending)</td><td>11/04/2026</td><td>--</td><td>100</td><td></td></tr>
          </tbody>
        </table>
      </div>
    </body>
    </html>
    """

    /// Generates a huge report with `courseCount` courses and `assignmentsPerCourse` rows to probe parser scaling.
    public static func makeLargeReportHTML(courseCount: Int, assignmentsPerCourse: Int) -> String {
        var sections = [String]()
        sections.reserveCapacity(courseCount)
        for c in 1...courseCount {
            var rows = [String]()
            rows.reserveCapacity(assignmentsPerCourse)
            for a in 1...assignmentsPerCourse {
                rows.append(
                    "<tr><td>HW</td><td>Assignment \(c)-\(a)</td><td>11/01/2026</td><td>9</td><td>10</td><td>90.0%</td></tr>"
                )
            }
            sections.append("""
            <div class="course-section" data-course="Course \(c)">
              <table class="course-header">
                <tr>
                  <td class="course-title">Course \(c)</td>
                  <td class="course-teacher">Teacher \(c)</td>
                  <td class="course-grade">90.0% (A-)</td>
                </tr>
              </table>
              <table class="assignments">
                <tbody>
                  \(rows.joined(separator: "\n"))
                </tbody>
              </table>
            </div>
            """)
        }
        return "<!DOCTYPE html><html><body>\(sections.joined(separator: "\n"))</body></html>"
    }
}
