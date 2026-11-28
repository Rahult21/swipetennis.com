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

  func testDeepIncomingBallStopsForwardMomentumAndCanBeReturnedFromHeldDepth() throws {
    for side in 0...1 {
      var game = incoming(side: side, local: true, depth: 4.99)
      let feet = game.players[side].pos
      let forward = side == 0 ? -1.0 : 1.0
      game.players[side].velocity.y = 4 * forward
      let original = try XCTUnwrap(game.flight)
      for _ in 0..<300 {
        game.step(1/120, interactiveRally: true, random: { 0.99 })
        XCTAssertEqual(game.players[side].pos.y, feet.y, accuracy: 0.000001)
      }
      let waiting = try XCTUnwrap(game.flight)
      XCTAssertEqual(waiting.waitingForSwipe, true)
      XCTAssertEqual(waiting.landing, original.landing)
      XCTAssertEqual(waiting.contact.y, feet.y, accuracy: 0.000001)
      XCTAssertGreaterThan(game.players[side].pos.x, feet.x)
      game.apply(.shotSwipe(Vec(x: 0, y: -100)), side: side, shotEpoch: game.shotGestureEpoch(side))
      for _ in 0..<300 where game.flight?.hitter != side {
        game.step(1/120, interactiveRally: true, random: { 0.99 })
      }
      XCTAssertEqual(game.flight?.hitter, side)
    }
  }

  func testIncomingPositionDragCanAdvanceOnlyToCalledShortBall() throws {
    for side in 0...1 {
      for depth in [4.99, 5.0] {
        var game = incoming(side: side, local: true, depth: depth)
        let feet = game.players[side].pos
        let forward = side == 0 ? -1.0 : 1.0
        game.step(1/120, interactiveRally: true, random: { 0.99 })
        let ring = try XCTUnwrap(game.flight).contact
        let target = Vec(x: 2, y: feet.y + 11 * forward)
        CupInput(.position(target), shotEpoch: nil, movementEpoch: game.contactSerial).apply(to: &game, side: side)
        XCTAssertEqual(game.players[side].destination.x, target.x)
        XCTAssertEqual(game.players[side].destination.y, depth == 5 ? ring.y : feet.y, accuracy: 0.001)
        let retreat = Vec(x: 3, y: feet.y - forward)
        game.apply(.position(retreat), side: side, movementEpoch: game.contactSerial)
        XCTAssertEqual(game.players[side].destination, retreat)
      }
    }
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
