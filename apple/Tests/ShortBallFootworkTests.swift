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

  func testForwardGestureCommitsTheDiagonalApproachAndTheNextFlickCanHit() throws {
    for side in 0...1 {
      for duration in [0.055,0.20] {
        var game = incoming(side:side, local:true, depth:5.1)
        game.players[side].pos.x = 0.1
        let feet = game.players[side].pos
        let forward = side == 0 ? -1.0 : 1.0
        game.step(1/120, interactiveRally:true,random:{0.99})
        let guide = try XCTUnwrap(game.swipeMovementGuide(side))
        XCTAssertLessThan(abs(guide.to.y-guide.from.y)/guide.from.distance(to:guide.to),0.65)
        XCTAssertEqual(game.players[side].destination,PracticeEngine.own(side,guide.to))
        var gesture = PracticeGesture(side:side,intent:.rally,movementEpoch:game.contactSerial,
          shotEpoch:game.shotGestureEpoch(side),targetGuide:guide,movementOrigin:feet,
          incomingShortBall:game.showsGoldenContact(side))
        _ = gesture.update(at:feet,screenPoint:.zero,timestamp:0)
        let end = Vec(x:feet.x,y:feet.y+forward*0.35)
        let stroke = try XCTUnwrap(gesture.update(at:end,screenPoint:Vec(x:0,y:forward*18),
          ended:true,timestamp:duration))
        XCTAssertEqual(stroke,.guidedMove(.receive))
        game.apply(stroke,side:side,shotEpoch:gesture.shotEpoch,movementEpoch:gesture.movementEpoch)
        XCTAssertEqual(game.players[side].destination,PracticeEngine.own(side,guide.to))
        XCTAssertNil(game.players[side].swingStrength)
        XCTAssertNil(game.swipeMovementGuide(side))
        var swing = PracticeGesture(side:side,intent:.rally,shotEpoch:game.shotGestureEpoch(side),
          targetGuide:game.swipeMovementGuide(side),movementOrigin:feet,incomingShortBall:true)
        _ = swing.update(at:feet,screenPoint:.zero,timestamp:0.4)
        let shot = try XCTUnwrap(swing.update(at:end,screenPoint:Vec(x:0,y:forward*70),ended:true,timestamp:0.47))
        XCTAssertEqual(shot,.shotSwipe(Vec(x:0,y:-70)))
        game.apply(shot,side:side,shotEpoch:swing.shotEpoch)
        XCTAssertNotNil(game.players[side].swingStrength)
      }
    }
  }

  func testCourtVisualAidsCanBeHiddenIndependentlyAndRememberPreviousChoice() throws {
    let suite = "court-aids-" + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName:suite))
    defer { defaults.removePersistentDomain(forName:suite) }
    CourtVisualAids.register(in:defaults)
    for mask in 0..<8 {
      for (bit,key) in [CourtVisualAids.yellowKey,CourtVisualAids.whiteKey,CourtVisualAids.blueKey].enumerated() {
        if mask != 0 { defaults.set(mask & (1 << bit) == 0,forKey:key) }
      }
      let aids = CourtVisualAids(defaults)
      XCTAssertEqual(aids.shows(.receive),mask & 1 == 0)
      XCTAssertEqual(aids.shows(.approach),mask & 1 == 0)
      XCTAssertEqual(aids.shows(.recover),mask & 2 == 0)
      XCTAssertEqual(aids.blue,mask & 4 == 0)
    }
    defaults.removePersistentDomain(forName:suite)
    defaults.set(false,forKey:"guides")
    CourtVisualAids.register(in:defaults)
    XCTAssertFalse(CourtVisualAids(defaults).yellow)
    XCTAssertFalse(CourtVisualAids(defaults).white)
    XCTAssertTrue(CourtVisualAids(defaults).blue)
    defaults.set(true,forKey:CourtVisualAids.yellowKey)
    CourtVisualAids.register(in:defaults)
    XCTAssertTrue(CourtVisualAids(defaults).yellow)
    XCTAssertFalse(CourtVisualAids(defaults).white)
  }

  func testDeepIncomingBallStopsForwardMomentumAndCanBeReturnedFromHeldDepth() throws {
    for side in 0...1 {
      var game = incoming(side: side, local: true, depth: 4.99)
      let feet = game.players[side].pos
      let forward = side == 0 ? -1.0 : 1.0
      game.players[side].velocity.y = 4 * forward
      let original = try XCTUnwrap(game.flight)
      for _ in 0..<300 where !game.promptsReturnSwipe {
        game.step(1/120, interactiveRally: true, random: { 0.99 })
        XCTAssertEqual(game.players[side].pos.y, feet.y, accuracy: 0.000001)
      }
      let incoming = try XCTUnwrap(game.flight)
      XCTAssertTrue(game.promptsReturnSwipe)
      XCTAssertEqual(incoming.landing, original.landing)
      XCTAssertEqual(incoming.contact.y, feet.y, accuracy: 0.000001)
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
      let expected = mode == "gold" ? 9.0 : mode == "bot" ? engine.settings.opponentRunSpeed() : 6.0
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
