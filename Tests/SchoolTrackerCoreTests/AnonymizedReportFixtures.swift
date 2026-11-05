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

    /// Synthetic ColdFusion GetReport.cfm multi-table layout with unclosed `</td`, `Weight =` categories,
    /// `Category Average`, and `Term Grade` rows (zero PII).
    public static let coldFusionMultiTableReportHTML = """
    <!DOCTYPE html>
    <html>
    <head><title>Gradebook Progress Report</title></head>
    <body>
      <table>
        <tr><td colspan="3">Gradebook Progress Report</td></tr>
        <tr><td>Student, Test</td><td>2026-2027</td><td>Instructor, Demo A</td></tr>
        <tr><td>MAT-401</td><td>Q2</td><td>WEIGHTED</td></tr>
        <tr><td colspan="3">AP Calculus BC</td</tr>
      </table>
      <table>
        <tr><td>Homework</td><td></td><td>Weight = 30.0</td></tr>
        <tr><td>Assignment</td><td>Pts</td><td>Max</td><td>Avg</td><td>Status</td><td>Due</td></tr>
        <tr><td>5.2 Day 1</td><td>91.0</td><td>100.0</td><td>91.0%</td><td>Valid</td><td>10/13</td></tr>
        <tr><td>5.3 Practice</td><td>--</td><td>100.0</td><td></td><td>Pending</td><td>11/06</td></tr>
        <tr><td>Category Average</td><td>91.00</td><td></td></tr>
        <tr><td>Quizzes</td><td></td><td>Weight = 70.0</td></tr>
        <tr><td>Assignment</td><td>Pts</td><td>Max</td><td>Avg</td><td>Status</td><td>Due</td></tr>
        <tr><td>Unit 5 Quiz</td><td>95.0</td><td>100.0</td><td>95.0%</td><td>Valid</td><td>10/20</td></tr>
        <tr><td>Category Average</td><td>95.00</td><td></td></tr>
        <tr><td>Term Grade</td><td>94</td><td>A</td></tr>
      </table>
      <table>
        <tr><td colspan="3">Gradebook Progress Report</td></tr>
        <tr><td>Student, Test</td><td>2026-2027</td><td>Instructor, Demo B</td></tr>
        <tr><td>SCI-302</td><td>Q2</td><td>PERCENT</td></tr>
        <tr><td colspan="3">Honors Chemistry</td</tr>
      </table>
      <table>
        <tr><td>Labs</td><td></td><td>Weight = 100.0</td></tr>
        <tr><td>Assignment</td><td>Pts</td><td>Max</td><td>Avg</td><td>Status</td><td>Due</td></tr>
        <tr><td>Titration Lab &amp; Report</td><td>88.0</td><td>100.0</td><td>88.0%</td><td>Valid</td><td>10/25</td></tr>
        <tr><td>Category Average</td><td>88.00</td><td></td></tr>
      </table>
    </body>
    </html>
    """

    /// Synthetic RFC 5545 iCalendar (.ics) feeds for School, My Classrooms, and My Homework spaces (zero PII).
    public static let validWebcalFeedURL =
        "webcal://test-xx.client.factsmgt.com/renweb/calendar/feed.ics?District=TEST-XX&token=00000000-0000-0000-0000-000000000000"

    public static let schoolCalendarICS = """
    BEGIN:VCALENDAR
    VERSION:2.0
    PRODID:-//FACTS Family Portal//School Calendar//EN
    BEGIN:VEVENT
    UID:school-evt-001@test-xx.factsmgt.com
    DTSTART;VALUE=DATE:20261123
    DTEND;VALUE=DATE:20261128
    SUMMARY:Thanksgiving Break - Campus Closed
    LOCATION:All Campuses
    DESCRIPTION:No classes in session for Thanksgiving Break.
    END:VEVENT
    BEGIN:VEVENT
    UID:school-evt-002@test-xx.factsmgt.com
    DTSTART:20261110T003000Z
    DTEND:20261110T020000Z
    SUMMARY:Fall Academic Showcase &
      Family Night
    LOCATION:Main Auditorium\\, Building A
    END:VEVENT
    END:VCALENDAR
    """

    public static let classroomsCalendarICS = """
    BEGIN:VCALENDAR
    VERSION:2.0
    PRODID:-//FACTS Family Portal//My Classrooms//EN
    BEGIN:VEVENT
    UID:classroom-evt-001@test-xx.factsmgt.com
    DTSTART:20261112T150000Z
    DTEND:20261112T160000Z
    SUMMARY:AP Calculus BC - Taylor Series Seminar
    LOCATION:Room 204
    DESCRIPTION:Bring graphing calculator and practice packet.
    END:VEVENT
    END:VCALENDAR
    """

    public static let homeworkCalendarICS = """
    BEGIN:VCALENDAR
    VERSION:2.0
    PRODID:-//FACTS Family Portal//My Homework//EN
    BEGIN:VEVENT
    UID:homework-evt-001@test-xx.factsmgt.com
    DTSTART;VALUE=DATE:20261115
    SUMMARY:Honors Chemistry - Titration Lab Post-Lab Questions
    DESCRIPTION:Submit via Family Portal before 8:00 AM.
    END:VEVENT
    END:VCALENDAR
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
