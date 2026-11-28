import XCTest
@testable import TennisCore

extension PracticeEngine {
  mutating func swingAtTestToss(_ side: Int, length: Double = 82) {
    swingServe(Vec(x: 0, y: length), side: side, tossID: servePreparation?.tossID)
  }

  mutating func setUpTestServe(_ side: Int) {
    requestServe(side)
    for _ in 0..<360 where servePreparation?.acceptsSwing == false { step(1/120, random: { 0.9 }) }
    swingAtTestToss(side)
  }

  /// Rally/scoring regressions advance through the real aim/toss rather than bypassing serve setup.
  mutating func startRally() {
    start(random: { 0.5 })
    for _ in 0..<720 where phase == .serving {
      if humanServing { requestServe(scoring.server); swingAtTestToss(scoring.server) }
      step(1 / 120, random: { 0.9 })
    }
  }
}
