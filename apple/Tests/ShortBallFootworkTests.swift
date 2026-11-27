import XCTest
@testable import TennisCore

final class ShortBallFootworkTests: XCTestCase {
  private func incoming(side: Int = 0, local: Bool = false, depth: Double = 6) -> PracticeEngine {
    var engine = PracticeEngine(settings: .init(local: local))
    engine.phase = .live
    engine.players[side].pos = Vec(x: 1, y: side == 0 ? 25 : -1.23)
    engine.players[1-side].pos = Vec(x: 6, y: side == 0 ? 0 : 23.77)
    engine.launch(1-side, aim: Vec(x: 6, y: side == 0 ? 23.77-depth : depth), kind: .cross)
    engine.move(side, to: Vec(x: 6, y: side == 0 ? 13 : 10.77))
    return engine
  }

  func testShortBallChaseReachesOneAndHalfNormalSpeedForEitherHuman() {
    for side in 0...1 {
      var short = incoming(side: side, local: side == 1)
      var deep = incoming(side: side, local: side == 1, depth: 4.99)
      for _ in 0..<72 { short.updateFootwork(1/120); deep.updateFootwork(1/120) }
      XCTAssertEqual(short.players[side].velocity.length, 9, accuracy: 0.001)
      XCTAssertEqual(deep.players[side].velocity.length, 6, accuracy: 0.001)
      XCTAssertEqual(short.players[side].velocity.length / deep.players[side].velocity.length, 1.5, accuracy: 0.001)
    }
  }

  func testShortBallBonusAppliesAtTheSameSwipeTempoIncludingSprint() {
    for tempo in [0.75, 1.0, 1.5] {
      var short = incoming(), deep = incoming(depth: 4.99)
      short.players[0].runPace = tempo
      deep.players[0].runPace = tempo
      for _ in 0..<24 { short.updateFootwork(1/120); deep.updateFootwork(1/120) }
      XCTAssertEqual(short.players[0].velocity.length/deep.players[0].velocity.length,1.5,accuracy:0.01)
    }
  }

  func testBoostCoversGoldThresholdButExcludesServeFaultRecoveryAndOpponent() {
    for mode in ["gold", "serve", "fault", "outgoing", "bot"] {
      let side = mode == "bot" ? 1 : 0
      var engine = incoming(side: side, depth: 5)
      if mode == "serve" { engine.flight!.serve = true }
      if mode == "fault" { engine.flight!.fault = "wide" }
      if mode == "outgoing" { engine.flight!.hitter = side }
      for _ in 0..<120 { engine.updateFootwork(1/120) }
      let expected = mode == "gold" ? 9.0 : mode == "bot" ? engine.settings.style.speed * engine.settings.difficulty.speed : 6.0
      XCTAssertEqual(engine.players[side].velocity.length, expected, accuracy: 0.001, mode)
    }
  }

  func testEarlySwipeReachesShortBallAndMakesActualReturnAcrossFrameRates() throws {
    for dt in [1.0/30, 1.0/60, 1.0/120] {
      var engine = incoming(depth: 7)
      engine.apply(.guidedMove(.receive), side: 0)
      for _ in 0..<400 where engine.phase == .live && engine.flight?.hitter == 1 { engine.step(dt, random: { 0.5 }) }
      XCTAssertEqual(engine.flight?.hitter, 0, "Failed to reach at \(dt)")
      XCTAssertNil(engine.flight?.fault)
      XCTAssertFalse(engine.showsGoldenContact(0))
    }
  }
}
