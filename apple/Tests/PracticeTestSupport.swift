import XCTest
@testable import TennisCore

extension PracticeEngine {
  /// Rally/scoring regressions advance through the real aim/toss rather than bypassing serve setup.
  mutating func startRally() {
    start(random: { 0.5 })
    for _ in 0..<720 where phase == .serving {
      if canBeginServe(scoring.server) { beginServe(scoring.server) }
      step(1 / 120, random: { 0.5 })
    }
  }
}
