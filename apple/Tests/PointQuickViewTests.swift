import XCTest
@testable import TennisCore

final class PointQuickViewTests: XCTestCase {
  func testLongRalliesStayAtSevenRowsAndPreserveEveryGainAndLoss() {
    let events = CoachRule.allCases.flatMap { rule in
      (0..<20).map { CoachEvent(rule: rule, opportunity: $0, success: $0 % 3 != 0) }
    }
    let rows = CoachPointSummary.rows(for: events)
    XCTAssertEqual(rows.count, 7)
    XCTAssertEqual(rows.reduce(0) { $0 + $1.points }, events.reduce(0) { $0 + $1.points })
    for row in rows {
      XCTAssertEqual(row.successes, 13)
      XCTAssertEqual(row.misses, 7)
      XCTAssertEqual(row.score, "+26 / −7")
      XCTAssertEqual(row.tally, "13 followed · 7 missed")
      XCTAssertFalse(row.reason.isEmpty)
    }
    XCTAssertTrue(CoachPointSummary.rows(for: []).isEmpty)
  }

  func testQuickViewKeepsSpecificRecoveryFailureAndUnreturnedBallReason() throws {
    let detail = "You reached white, but did not tap to split before the next ball."
    let row = try XCTUnwrap(CoachPointSummary.rows(for: [CoachEvent(rule: .recoveryAndSplit, opportunity: 0, success: false, detail: detail)]).first)
    XCTAssertEqual(row.reason, "Reached white; missed the split step")
    XCTAssertEqual(row.score, "−1")
    XCTAssertNil(row.tally)
    let missed = CoachEvent(rule: .shortBallApproach, opportunity: 0, success: false,
      detail: "You did not return the ball to complete: follow a short ball in.")
    XCTAssertTrue(missed.compactReason.hasPrefix("Missed return:"))
    XCTAssertFalse(missed.compactReason.contains("stayed back"))
  }
}
