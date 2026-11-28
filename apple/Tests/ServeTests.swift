import XCTest
@testable import TennisCore

final class ServeTests: XCTestCase {
  private func humanServer(_ side: Int = 0, ad: Bool = false) -> PracticeEngine {
    var engine = PracticeEngine(settings: .init(local: true))
    if side == 0 { for _ in 0..<4 { engine.scoring.award(0) } }
    if ad { engine.scoring.award(0) }
    engine.start()
    return engine
  }

  private func advance(_ engine: inout PracticeEngine, _ seconds: Double) {
    for _ in 0..<Int(seconds * 120) { engine.step(1 / 120, random: { 0.5 }) }
  }

  func testHumanServeWaitsForTapAndDoesNotCountAimingAsRallyOrPoint() {
    for side in 0...1 {
      var engine = humanServer(side)
      let points = engine.scoring.points
      advance(&engine, 15)
      XCTAssertEqual(engine.phase, .serving)
      XCTAssertNil(engine.flight)
      XCTAssertEqual(engine.rally, 0)
      XCTAssertEqual(engine.contactSerial, 0)
      XCTAssertEqual(engine.scoring.points, points)
      XCTAssertTrue(engine.canBeginServe(side))
      engine.beginServe(1 - side)
      XCTAssertFalse(engine.servePreparation!.isTossing)
      engine.beginServe(side)
      advance(&engine, 0.5)
      XCTAssertEqual(engine.phase, .serving)
      XCTAssertEqual(engine.contactSerial, 0)
      advance(&engine, 0.45)
      XCTAssertEqual(engine.phase, .live)
      XCTAssertEqual(engine.flight?.hitter, side)
      XCTAssertTrue(engine.flight!.serve)
      XCTAssertEqual(engine.contactSerial, 1)
    }
  }

  func testAllPresetsUseCorrectServiceBoxForBothServersAndBothCourts() {
    for side in 0...1 {
      for ad in [false, true] {
        var engine = humanServer(side, ad: ad)
        var targets: [Vec] = []
        for placement in ServePlacement.allCases {
          engine.chooseServe(placement, side: side)
          advance(&engine, 2)
          let target = engine.servePreparation!.target
          targets.append(target)
          XCTAssertEqual(target.x < PracticeEngine.width / 2, (side == 0) == !ad)
          XCTAssertTrue(side == 0 ? target.y > 5.485 && target.y < PracticeEngine.net
            : target.y < 18.285 && target.y > PracticeEngine.net)
        }
        XCTAssertGreaterThan(targets[0].distance(to: targets[1]), 2)
        XCTAssertGreaterThan(targets[2].distance(to: targets[0]), 0.5)
        XCTAssertGreaterThan(targets[2].distance(to: targets[1]), 0.5)
      }
    }
  }

  func testBodyIsAimedAtReceiverAndDoesNotChaseLaterMovement() {
    var engine = humanServer()
    engine.chooseServe(.body, side: 0)
    let target = engine.servePreparation!.destination
    let origin = serviceImpact(at: engine.players[0].pos, side: 0, explosive: false).courtPosition
    let contact = target.projected(from: origin, toDepth: 0)
    XCTAssertEqual(contact.x, engine.players[1].pos.x, accuracy: 0.00001)
    engine.move(1, to: Vec(x: 8, y: -0.5))
    advance(&engine, 1)
    XCTAssertEqual(engine.servePreparation!.destination, target)
  }

  func testBlueMovesSmoothlyAndYellowTracksEveryFrameThenMatchesRealFlight() {
    for side in 0...1 {
      var engine = humanServer(side)
      engine.chooseServe(.wide, side: side)
      let origin = engine.servePreparation!.target
      engine.step(1 / 120)
      XCTAssertGreaterThan(engine.servePreparation!.target.distance(to: origin), 0)
      XCTAssertLessThanOrEqual(engine.servePreparation!.target.distance(to: origin), 3.2 / 120 + 0.00001)
      let impact = serviceImpact(at: engine.players[side].pos, side: side, explosive: false).courtPosition
      let baseline = side == 0 ? 0.0 : PracticeEngine.length
      for _ in 0..<250 {
        engine.step(1 / 120)
        XCTAssertEqual(engine.contactGuide(1 - side), engine.servePreparation!.target.projected(from: impact, toDepth: baseline))
      }
      let yellow = engine.contactGuide(1 - side)
      let blue = engine.servePreparation!.target
      XCTAssertEqual(yellow!.y, baseline)
      XCTAssertEqual(yellow!.x, blue.projected(from: impact, toDepth: baseline).x, accuracy: 0.000001)
      engine.beginServe(side)
      advance(&engine, 0.95)
      XCTAssertEqual(engine.flight?.landing, blue)
      XCTAssertEqual(engine.flight?.contact, yellow)
    }
  }

  func testSecondServeTracksBlueOneMetreInThroughTossFlightAndRestore() throws {
    for side in 0...1 {
      var game = humanServer(side)
      game.prepareSecondServe()
      let depth = side == 0 ? 1.0 : PracticeEngine.length-1
      let impact = serviceImpact(at:game.players[side].pos,side:side,explosive:false).courtPosition
      game.chooseServe(.wide,side:side)
      for _ in 0..<250 {
        game.step(1/120,random:{0.9})
        let blue = try XCTUnwrap(game.servePreparation?.target)
        XCTAssertEqual(game.contactGuide(1-side),blue.projected(from:impact,toDepth:depth))
      }
      let yellow = try XCTUnwrap(game.contactGuide(1-side))
      game.beginServe(side)
      advance(&game,0.95)
      XCTAssertEqual(game.flight?.contact,yellow)
      let previous = yellow.projected(from:impact,toDepth:ServeGeometry.receivingBaseline(server:side))
      game.flight?.contact = previous
      game.players[1-side].destination = previous
      game.restoreReceiveMark()
      XCTAssertEqual(game.flight?.contact,yellow)
      XCTAssertEqual(game.players[1-side].destination,yellow)
    }
  }

  func testWideServeIsPlayableAtYellowOrDeeperButCannotBeHitAfterItPasses() throws {
    for side in 0...1 {
      var setup = humanServer(side)
      setup.chooseServe(.wide, side: side)
      let blue = try XCTUnwrap(setup.servePreparation?.destination)
      setup.phase = .live
      setup.servePreparation = nil
      setup.launch(side, aim: blue, kind: .cross, serve: true)
      let flight = try XCTUnwrap(setup.flight)
      let yellow = flight.contact
      let receiver = 1-side
      for feet in [yellow, flight.courtPosition(at: 0.88), flight.reboundEnd] {
        var game = setup
        game.players[receiver].pos = feet
        game.players[receiver].destination = feet
        let window = try XCTUnwrap(game.contactWindow(receiver))
        game.flight?.elapsed = flight.time(at: window.entry)-0.001
        game.step(1/120,random:{0.7})
        XCTAssertEqual(game.flight?.hitter,receiver)
        XCTAssertLessThan(try XCTUnwrap(game.flight?.strikeOrigin).courtPosition.distance(to:feet),1.3)
      }
      var late = setup
      let early = flight.courtPosition(at: 0.88)
      late.players[receiver].pos = early
      late.players[receiver].destination = early
      late.flight?.elapsed = flight.time(at: 0.998)
      let serial = late.contactSerial
      late.step(1/30,random:{0.7})
      XCTAssertEqual(late.contactSerial,serial)
      XCTAssertEqual(late.scoring.points[side],1)
    }
  }

  func testAdjustmentsStayLegalAndReachableEvenAtExtremes() {
    for side in 0...1 {
      for ad in [false, true] {
        var engine = humanServer(side, ad: ad)
        for point in [Vec(x: -100, y: -100), Vec(x: 100, y: 100), Vec(x: -100, y: 100), Vec(x: 100, y: -100)] {
          engine.aimServe(at: point, side: side)
          advance(&engine, 3)
          let blue = engine.servePreparation!.target
          let yellow = engine.contactGuide(1 - side)!
          XCTAssertEqual(blue.x < PracticeEngine.width / 2, (side == 0) == !ad)
          XCTAssertEqual(PracticeEngine.own(1 - side, yellow), yellow)
        }
      }
    }
  }

  func testCannotServeWhileMovingTargetOrChangeItDuringToss() {
    var engine = humanServer()
    advance(&engine, 1)
    engine.chooseServe(.wide, side: 0)
    engine.beginServe(0)
    XCTAssertFalse(engine.servePreparation!.isTossing)
    advance(&engine, 2)
    engine.beginServe(0)
    let blue = engine.servePreparation!.target
    engine.chooseServe(.center, side: 0)
    engine.nudgeServe(Vec(x: 100, y: 100), side: 0)
    XCTAssertEqual(engine.servePreparation!.destination, blue)
    advance(&engine, 0.95)
    XCTAssertEqual(engine.flight!.landing, blue)
  }

  func testOpponentVariesPlacementAndAllowsPreparationBeforeToss() {
    for (index, placement) in ServePlacement.allCases.enumerated() {
      var engine = PracticeEngine(settings: .init())
      engine.start(random: { (Double(index) + 0.2) / 3 })
      XCTAssertEqual(engine.servePreparation!.placement, placement)
      let originalDestination = engine.servePreparation!.destination
      engine.chooseServe(.center, side: 0)
      engine.aimServe(at: .zero, side: 1)
      XCTAssertEqual(engine.servePreparation!.destination, originalDestination)
      advance(&engine, 2.9)
      XCTAssertFalse(engine.servePreparation!.isTossing)
      XCTAssertNil(engine.flight)
      advance(&engine, 1.1)
      XCTAssertEqual(engine.phase, .live)
      XCTAssertTrue(engine.flight!.serve)
    }
  }

  func testReceiverCanMoveSelectReturnAndSplitDuringServeSetup() {
    var engine = PracticeEngine(settings: .init())
    engine.start(random: { 0 })
    advance(&engine, 2)
    let yellow = engine.contactGuide(0)!
    engine.apply(.guidedMove(.receive), side: 0)
    engine.selectShotSwipe(Vec(x: 0, y: -40), side: 0)
    XCTAssertEqual(engine.players[0].destination, yellow)
    XCTAssertEqual(engine.players[0].kind, .line)
    let start = engine.players[0].pos
    advance(&engine, 0.5)
    XCTAssertLessThan(engine.players[0].pos.distance(to: yellow), start.distance(to: yellow))
    advance(&engine, 1.2)
    engine.beginSplit(0)
    XCTAssertTrue(engine.splitTimed[0])
    XCTAssertEqual(engine.tactics[0].timedSplits, 1)
  }

  func testServingPlayerCannotWalkOffBaselineOrSelectARallyShotBeforeContact() {
    var engine = humanServer()
    let server = engine.players[0].pos
    engine.move(0, to: Vec(x: 8, y: 15))
    engine.swipeCourt(0, delta: Vec(x: 0, y: -5))
    engine.selectShotSwipe(Vec(x: 0, y: 40), side: 0)
    advance(&engine, 2)
    XCTAssertEqual(engine.players[0].pos, server)
    XCTAssertEqual(engine.players[0].destination, server)
    XCTAssertEqual(engine.players[0].kind, .cross)
  }

  func testOnTimeServeReturnIsCleanForEveryPlacementAndCannotBeVolleyed() {
    for side in 0...1 {
      for placement in ServePlacement.allCases {
        var engine = humanServer(side)
        engine.chooseServe(placement, side: side)
        advance(&engine, 2)
        let receiver = 1 - side
        let yellow = engine.contactGuide(receiver)!
        engine.players[receiver].pos = yellow
        engine.players[receiver].destination = yellow
        engine.beginServe(side)
        advance(&engine, 0.95)
        XCTAssertNil(BallContactWindow.volley(flight: engine.flight!, player: yellow, side: receiver))
        for _ in 0..<300 where engine.contactSerial == 1 { engine.step(1 / 120, random: { 0.99 }) }
        XCTAssertEqual(engine.contactSerial, 2)
        XCTAssertEqual(engine.flight!.hitter, receiver)
        XCTAssertNil(engine.flight!.fault)
        XCTAssertEqual(engine.flight!.stroke, .groundstroke)
      }
    }
  }

  func testServeJumpJoinsContactContinuouslyAndLandingFinishesInsideBothBaselines() {
    XCTAssertEqual(ServeMotion.jumpHeight(tossProgress: 0.5, landingProgress: nil), 0)
    XCTAssertEqual(ServeMotion.jumpHeight(tossProgress: 1, landingProgress: nil),
      ServeMotion.jumpHeight(tossProgress: nil, landingProgress: 0))
    XCTAssertEqual(ServeMotion.jumpHeight(tossProgress: nil, landingProgress: 1), 0)
    for side in 0...1 {
      var engine = humanServer(side)
      advance(&engine, 1)
      engine.beginServe(side)
      advance(&engine, 0.95)
      let start = engine.players[side].pos
      advance(&engine, 0.2)
      XCTAssertNotEqual(engine.players[side].pos, start)
      XCTAssertNotNil(engine.serveLanding)
      advance(&engine, 0.23)
      XCTAssertNil(engine.serveLanding)
      XCTAssertTrue(side == 0 ? engine.players[side].pos.y < PracticeEngine.length : engine.players[side].pos.y > 0)
      XCTAssertEqual(engine.landingSerial, 1)
      XCTAssertFalse(engine.followingApproach[side])
    }
  }
}
