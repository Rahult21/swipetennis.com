import XCTest
@testable import TennisCore

final class TouchShotTests: XCTestCase {
  private func receiving() -> PracticeEngine {
    var engine = PracticeEngine(settings: .init())
    engine.phase = .live
    engine.launch(1, aim: Vec(x: 2, y: 22), kind: .cross)
    return engine
  }

  private func circle(clockwise: Bool = true, duration: Double = 0.5, armed: Bool = true) -> PracticeGestureAction? {
    var gesture = PracticeGesture(side: 0, allowsDrop: armed)
    var action: PracticeGestureAction?
    for i in 0...32 {
      let angle = Double(i) / 32 * 2 * .pi * (clockwise ? 1 : -1)
      let point = Vec(x: 100 + 30 * cos(angle), y: 200 + 30 * sin(angle))
      action = gesture.update(at: Vec(x: point.x / 30, y: point.y / 30 + 15),
        screenPoint: point, ended: i == 32, timestamp: Double(i) / 32 * duration)
      if i < 32 { XCTAssertNil(action) }
    }
    return action
  }

  func testQuickCircleBothDirectionsRequiresYellowAndCompletesBeforeContact() throws {
    XCTAssertEqual(circle(), .shot(.drop))
    XCTAssertEqual(circle(clockwise: false), .shot(.drop))
    XCTAssertNotEqual(circle(duration: 1.5), .shot(.drop))
    XCTAssertNotEqual(circle(armed: false), .shot(.drop))
    var engine = receiving()
    let epoch = engine.shotGestureEpoch(0)
    engine.selectTouchShot(.drop, side: 0, epoch: epoch)
    XCTAssertNotEqual(engine.players[0].kind, .drop)
    engine.apply(.guidedMove(.receive), side: 0)
    let destination = engine.players[0].destination
    XCTAssertTrue(engine.canDrawDrop(0))
    engine.apply(try XCTUnwrap(circle()), side: 0, shotEpoch: epoch)
    XCTAssertEqual(engine.players[0].kind, .drop)
    XCTAssertEqual(engine.players[0].destination, destination)
    XCTAssertFalse(engine.canDrawDrop(0))
    engine.players[0].pos = destination
    engine.ball = destination
    engine.returnBall(0, volley: false, random: { 0.99 })
    XCTAssertEqual(engine.flight?.kind, .drop)
    XCTAssertNil(engine.flight?.fault)
    XCTAssertEqual(engine.players[0].kind, .cross)
    engine.selectTouchShot(.slice, side: 0, epoch: epoch)
    XCTAssertEqual(engine.players[0].kind, .cross)
  }

  func testStraightIncompleteAndTinyCirclesAreNotDropShots() {
    XCTAssertFalse(QuickCircle.matches((0...20).map { Vec(x: Double($0) * 3, y: 0) }, duration: 0.4))
    for radius in [5.0, 30.0] {
      let points = (0...20).map { i in
        let angle = Double(i) / 20 * (radius == 5 ? 2 : 1) * Double.pi
        return Vec(x: radius * cos(angle), y: radius * sin(angle))
      }
      XCTAssertFalse(QuickCircle.matches(points, duration: 0.4))
    }
  }

  func testSliceStartsAtEitherActualNetPostAndEndsAtOppositeOwnBaseline() {
    for side in 0...1 {
      for left in [true, false] {
        let start = Vec(x: left ? -1.65 : 9.88, y: PracticeEngine.net)
        let end = Vec(x: left ? 8.23 : 0, y: side == 0 ? 23.77 : 0)
        var gesture = PracticeGesture(side: side, intent: .slice)
        XCTAssertNil(gesture.update(at: start))
        XCTAssertNil(gesture.update(at: Vec(x: 4, y: side == 0 ? 18 : 5)))
        XCTAssertEqual(gesture.update(at: end, ended: true), .shot(.slice))
        XCTAssertFalse(SlicePath.matches(from: Vec(x: 4, y: PracticeEngine.net), to: end, side: side))
        XCTAssertFalse(SlicePath.matches(from: start, to: Vec(x: start.x, y: end.y), side: side))
        XCTAssertFalse(SlicePath.matches(from: start, to: Vec(x: end.x, y: 23.77 - end.y), side: side))
      }
    }
  }

  func testSpecialShotGestureSizeControlsCarryAndGuideLength() throws {
    for kind in [ShotKind.drop, .slice] {
      var previous = 0.0
      for length in [16.0, 82, 148] {
        var game = receiving()
        game.apply(.guidedMove(.receive), side: 0)
        let epoch = game.shotGestureEpoch(0)
        let cue = try XCTUnwrap(ShotDirection(action: .shot(kind), side: 0, epoch: epoch,
          game: game, time: 0, gestureDistance: length))
        let packet = CupInput(.shot(kind), shotEpoch: epoch, movementEpoch: nil, shotDistance: length)
        try JSONDecoder().decode(CupInput.self, from: JSONEncoder().encode(packet)).apply(to: &game, side: 0)
        let target = try XCTUnwrap(game.players[0].aim)
        XCTAssertEqual(cue.origin.distance(to: cue.target), 3 + 6 * (length - 16) / 132, accuracy: 0.001)
        game.players[0].pos = game.players[0].destination
        game.returnBall(0, volley: false, random: { 0.99 })
        let bounce = try XCTUnwrap(game.flight).landing
        XCTAssertEqual(bounce.y, target.y, accuracy: 0.001)
        let carry = PracticeEngine.net - bounce.y
        XCTAssertGreaterThan(carry, previous)
        if kind == .drop { XCTAssertLessThan(carry, 2.5) }
        previous = carry
      }
    }
  }

  func testDropIsShortWithLowSecondBounceAndSliceIsSlower() throws {
    for side in 0...1 {
      var engine = PracticeEngine(settings: .init(local: true))
      engine.phase = .live
      let position = engine.players[side].pos
      engine.launch(side, aim: PracticeEngine.preset(side, .drop, position), kind: .drop)
      var drop = try XCTUnwrap(engine.flight)
      XCTAssertEqual(abs(drop.landing.y - PracticeEngine.net), 1.6, accuracy: 0.00001)
      XCTAssertNil(BallContactWindow.overheadTarget(flight: drop, side: 1 - side))
      drop.elapsed = drop.duration * 0.9
      XCTAssertEqual(drop.height, 0.28, accuracy: 0.00001)
      drop.elapsed = drop.duration
      XCTAssertEqual(drop.height, 0, accuracy: 0.00001)
      let aim = PracticeEngine.preset(side, .cross, position)
      engine.launch(side, aim: aim, kind: .cross)
      let drive = try XCTUnwrap(engine.flight)
      engine.launch(side, aim: aim, kind: .slice)
      XCTAssertGreaterThan(engine.flight!.duration, drive.duration)
      XCTAssertLessThan(engine.flight!.loft, drive.loft)
      XCTAssertEqual(engine.flight?.stroke, .slice)
    }
  }

  func testEveryOpponentChasesDropsWithRequestedRatioAndReturnsDeepLob() throws {
    for difficulty in Difficulty.allCases {
      for style in BotStyle.allCases {
        var engine = PracticeEngine(settings: .init(difficulty: difficulty, style: style))
        let group = difficulty == .easy ? 3 : difficulty == .medium ? 4 : 5
        var reached = 0
        for _ in 0..<group * 2 {
          engine.phase = .live
          engine.pointResolution = nil
          engine.players[0].pos = Vec(x: 2, y: 22)
          engine.players[1].pos = Vec(x: 2, y: -1)
          engine.players[1].destination = engine.players[1].pos
          engine.players[1].velocity = .zero
          let start = engine.players[1].pos
          engine.launch(0, aim: PracticeEngine.preset(0, .drop, engine.players[0].pos), kind: .drop)
          let target = engine.flight!.contact
          for _ in 0..<1200 where engine.phase == .live && engine.flight?.hitter == 0 {
            engine.step(1 / 120, random: { 0.6 })
          }
          XCTAssertLessThan(engine.players[1].pos.distance(to: target), start.distance(to: target) - 0.5)
          if engine.flight?.hitter == 1 {
            reached += 1
            XCTAssertEqual(engine.flight?.kind, .lob)
            XCTAssertNil(engine.flight?.fault)
            XCTAssertGreaterThan(engine.flight!.landing.y, PracticeEngine.length - 1)
          } else {
            XCTAssertEqual(engine.phase, .point)
            XCTAssertEqual(engine.flight?.dropReachable, false, "Unexpected missed chase: \(difficulty)/\(style)")
          }
        }
        XCTAssertEqual(reached, (group - 1) * 2, "\(difficulty)/\(style)")
      }
    }
  }

  func testSlowSliceCanBeReturnedByEveryOpponent() {
    for difficulty in Difficulty.allCases {
      for style in BotStyle.allCases {
        var engine = PracticeEngine(settings: .init(difficulty: difficulty, style: style))
        engine.phase = .live
        engine.players[1].pos = Vec(x: -0.8, y: 8)
        engine.players[1].destination = engine.players[1].pos
        engine.launch(0, aim: Vec(x: 6.83, y: 1.8), kind: .slice)
        for _ in 0..<1200 where engine.phase == .live && engine.flight?.hitter == 0 {
          engine.step(1 / 120, random: { 0.6 })
        }
        XCTAssertEqual(engine.flight?.hitter, 1, "\(difficulty)/\(style)")
        XCTAssertNil(engine.flight?.fault)
      }
    }
  }
}
