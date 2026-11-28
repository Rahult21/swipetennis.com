import XCTest
@testable import TennisCore

final class ShotRiskAndServeTests: XCTestCase {
  private func serving(number: Int = 1) -> PracticeEngine {
    var game = PracticeEngine(settings: .init())
    game.scoring = PracticeScore(format: .tennis, firstServer: 0)
    game.start()
    if number == 2 { game.prepareSecondServe() }
    return game
  }

  func testLandingRatesOnActualPlayerAndOpponentStrokes() {
    // One sample per percentile bin. Targets and tactical choices stay fixed for each stroke.
    for bot in [false, true] {
      for (kind, redirect, expected) in [(ShotKind.cross, false, 210), (.line, false, 192),
        (.cross, true, 192), (.angle, false, 160)] {
        var clean = 0
        for index in 0..<240 {
          let side = bot ? 1 : 0
          var game = PracticeEngine(settings: .init(difficulty: .medium, allCourtTraining: false))
          game.phase = .live
          let contact = Vec(x: 1.4, y: bot ? 1 : PracticeEngine.length - 1)
          game.players[side].pos = contact
          game.players[side].destination = contact
          let originX = redirect || kind == .line ? 1.4 : 7.7
          game.players[1-side].pos = Vec(x: originX, y: bot ? 23 : 1)
          game.launch(1-side, aim: contact, kind: .cross)
          game.flight!.contact = contact
          game.flight!.opponentReplyPrepared = true
          game.ball = contact
          game.choose(side, kind)
          var rolls: [Double] = []
          if bot {
            // Send a line ball up the near sideline, a short angle into the open corner,
            // or use the ordinary crosscourt target. Keep the incoming line independent.
            game.players[1].kind = .cross
            game.players[0].pos.x = kind == .line ? 7.6 : 1.2
            rolls = [kind == .cross ? 0.99 : 0, 0.5, kind == .angle ? 0 : 0.99]
            if kind == .angle { rolls.append(0.5) }
          }
          rolls.append((Double(index) + 0.5) / 240)
          game.returnBall(side, volley: false, random: { rolls.isEmpty ? 0.5 : rolls.removeFirst() })
          XCTAssertEqual(game.flight?.kind, kind)
          if game.flight?.fault == nil { clean += 1 }
        }
        XCTAssertEqual(clean, expected, "bot=\(bot), kind=\(kind), redirect=\(redirect)")
      }
    }
  }

  func testHittingBehindCapsOpponentChaseForOnlyThatFlight() {
    for direction in [-1.0, 1.0] {
      var game = PracticeEngine(settings: .init(difficulty: .medium))
      game.phase = .live
      game.players[1].pos = Vec(x: 4, y: 0)
      game.players[1].velocity = Vec(x: 3.5 * direction, y: 0)
      let ahead = Vec(x: 4 + 3 * direction, y: 1.1)
      let behind = Vec(x: 4 - 3 * direction, y: 1.1)
      game.launch(0, aim: ahead, kind: .cross)
      XCTAssertEqual(game.flight?.receiverWrongFooted, false)
      game.launch(0, aim: behind, kind: .cross)
      XCTAssertEqual(game.flight?.receiverWrongFooted, true)
      game.players[1].destination = Vec(x: 4 - 5 * direction, y: 0)
      for _ in 0..<90 { game.updateFootwork(1 / 120) }
      XCTAssertEqual(game.players[1].velocity.length, 0.6 * BotStyle.baseline.speed, accuracy: 0.05)
      game.launch(0, aim: behind, kind: .cross)
      XCTAssertEqual(game.flight?.receiverWrongFooted, false)
      game.players[1].velocity = .zero
      game.launch(0, aim: ahead, kind: .cross)
      XCTAssertEqual(game.flight?.receiverWrongFooted, false)
    }
  }

  func testTimedSplitImprovesOnlyTheNextReturnAndExplainsTheDecidingShot() throws {
    let near = Vec(x: 1.1, y: 22.5), far = Vec(x: 7.6, y: 1)
    for timed in [false, true] {
      var game = PracticeEngine(settings: .init(allCourtTraining: false))
      game.phase = .live
      game.players[0].pos = near
      game.players[1].pos = far
      game.launch(0, aim: far, kind: .cross)
      game.flight!.elapsed = game.flight!.duration * (timed ? 0.8 : 0.2)
      game.beginSplit(0)
      game.beginSplit(0)
      func receive(_ game: inout PracticeEngine) {
        game.launch(1, aim: near, kind: .cross)
        game.flight!.contact = near
        game.ball = near
        game.choose(0, .line)
        var rolls = [0.08, 0.5]
        game.returnBall(0, volley: false, random: { rolls.isEmpty ? 0.5 : rolls.removeFirst() })
      }
      receive(&game)
      let shot = try XCTUnwrap(game.players[0].lastReturn)
      XCTAssertTrue(shot.redirected && shot.shorterSide)
      XCTAssertEqual(shot.accuracy, timed ? 0.96 : 0.8, accuracy: 0.00001)
      XCTAssertEqual(game.flight?.fault, timed ? nil : "wide")
      if timed {
        XCTAssertTrue(game.pointSplitSummary.contains("80% → 96%"))
        receive(&game)
        XCTAssertEqual(game.flight?.fault, "wide", "A split cannot carry over two returns")
      }
      game.flight!.elapsed = game.flight!.duration * 0.8
      game.step(1/60, random: { 0.5 })
      XCTAssertTrue(game.feedback.reason.contains("landed wide"))
      XCTAssertTrue(game.feedback.reason.contains("shorter side"))
      XCTAssertTrue(game.feedback.reason.contains("lower-percentage"))
      XCTAssertTrue(game.feedback.reason.contains("crosscourt"))
      XCTAssertTrue(game.pointSplitSummary.contains("No timed split"))
      let change = try XCTUnwrap(game.coach.events.last { $0.rule == .changeDirectionApproach })
      XCTAssertEqual(change.compactReason, "Changed direction and missed the target")
      XCTAssertEqual(change.points, -1)
    }
  }

  func testRelativePlacementBoostCapsAtOneAndShorterSideUsesActualGeometry() {
    for (base, expected) in [(7.0/8, 1.0), (4.0/5, 0.96), (2.0/3, 0.8)] {
      let decision = ReturnDecision(shot: .angle, redirected: false, shorterSide: false,
        split: true, baseAccuracy: base)
      XCTAssertEqual(decision.accuracy, expected, accuracy: 0.00001)
    }
    let near = Vec(x: 1, y: 23), diagonal = Vec(x: 7, y: 1), line = Vec(x: 1, y: 1)
    XCTAssertGreaterThan(CourtTactics.courtLength(from: near, toward: diagonal, side: 0),
      CourtTactics.courtLength(from: near, toward: line, side: 0) + 0.35)
    let farther = ReturnDecision(shot: .cross, redirected: true, shorterSide: false, split: false, baseAccuracy: 0.8)
    XCTAssertFalse(farther.lesson.contains("shorter side"))
    XCTAssertTrue(farther.lesson.contains("lower-percentage"))
  }

  func testAimAndMeterChangesRestartHalfSecondClockEvenWithFingerHeld() throws {
    var game = serving()
    let blue = try XCTUnwrap(game.servePreparation?.target)
    game.aimServe(at: blue, side: 0, finished: false)
    for _ in 0..<48 { game.step(1/120) }
    game.aimServe(at: Vec(x: blue.x, y: 8.4), side: 0, finished: false)
    for _ in 0..<48 { game.step(1/120) }
    game.adjustServe(speed: .low, spin: .high, side: 0)
    for _ in 0..<59 { game.step(1/120) }
    XCTAssertFalse(game.servePreparation!.isTossing)
    game.step(1/120)
    XCTAssertTrue(game.servePreparation!.isTossing)
    XCTAssertFalse(game.servePreparation!.canTune)
    let copy = try JSONDecoder().decode(PracticeEngine.self, from: JSONEncoder().encode(game))
    XCTAssertEqual(copy.servePreparation?.tossID, game.servePreparation?.tossID)
  }

  func testServeRiskExtremesOnBothEndsAndActualPointExplanation() throws {
    for side in 0...1 {
      for safe in [true, false] {
        var setup = PracticeEngine(settings: .init(local: true))
        setup.scoring = PracticeScore(format: .tennis, firstServer: side)
        setup.start()
        let depth = safe ? 4.0 : 5.8
        setup.aimServe(at: Vec(x: 3, y: PracticeEngine.net + (side == 0 ? -depth : depth)), side: side)
        setup.adjustServe(speed: safe ? .low : .high, spin: safe ? .high : .low, side: side)
        for _ in 0..<60 { setup.step(1/120) }
        let id = try XCTUnwrap(setup.servePreparation?.tossID)
        var swiped = setup
        swiped.swingServe(Vec(x: 130, y: 1), side: side, tossID: id)
        swiped.swingServe(Vec(x: 0, y: -130), side: side, tossID: id)
        swiped.swingServe(Vec(x: 0, y: 12), side: side, tossID: id)
        swiped.swingServe(Vec(x: 0, y: 120), side: 1-side, tossID: id)
        XCTAssertNil(swiped.servePreparation?.swingCommitted)
        for _ in 0..<310 { swiped.step(1/120) }
        XCTAssertNil(swiped.flight)
        XCTAssertEqual(swiped.contactSerial, 0)
        swiped.swingServe(Vec(x: 0, y: 120), side: side, tossID: id)
        XCTAssertNil(swiped.servePreparation?.swingCommitted)

        var faults = 0
        for bin in 0..<30 {
          var game = setup
          var swing = CupInput(kind: "serveSwing", point: Vec(x: 0, y: safe ? 82 : 148))
          swing.tossID = id
          swing.apply(to: &game, side: side)
          for _ in 0..<115 where game.phase == .serving { game.step(1/120, random: { (Double(bin)+0.5)/30 }) }
          let flight = try XCTUnwrap(game.flight)
          if flight.fault != nil { faults += 1 }
          if bin == 29 {
            game.launch(1-side, aim: setup.players[side].pos, kind: .cross)
            game.end(side, reason: "Won the rally.", tip: "")
            XCTAssertTrue(game.feedback.reason.contains(safe ? "9 in 10 land in" : "2 in 3 fault risk"))
          }
        }
        XCTAssertEqual(faults, safe ? 3 : 20)
        func flight(_ length: Double) throws -> BallFlight {
          var game = setup
          game.swingAtTestToss(side, length: length)
          for _ in 0..<115 where game.phase == .serving { game.step(1/120,random:{0.99}) }
          return try XCTUnwrap(game.flight)
        }
        let short = try flight(16), middle = try flight(82), long = try flight(148)
        XCTAssertLessThan(abs(short.landing.y - PracticeEngine.net), abs(middle.landing.y - PracticeEngine.net))
        XCTAssertLessThan(abs(middle.landing.y - PracticeEngine.net), abs(long.landing.y - PracticeEngine.net))
        XCTAssertEqual(short.launchSpeedKPH, middle.launchSpeedKPH)
        XCTAssertEqual(long.launchSpeedKPH, middle.launchSpeedKPH)
        XCTAssertEqual(short.contact.x, long.contact.x, accuracy: 0.00001)
        for serve in [short, middle, long] {
          let from = serve.launchPosition.y
          let net = 0.8 * (PracticeEngine.net - from) / (serve.landing.y - from)
          XCTAssertGreaterThan(serve.altitude(at: net), 1.0)
        }
      }
    }
  }

  func testInteractiveRallyMovesWaitsAndHitsOnceWithSwipeDepthAndPace() throws {
    for side in 0...1 {
      var game = PracticeEngine(settings: .init(local: true, allCourtTraining: false))
      game.phase = .live
      game.players[side].pos = Vec(x: 1, y: side == 0 ? 22 : 2)
      game.players[side].destination = game.players[side].pos
      game.players[1-side].pos = Vec(x: 4, y: side == 0 ? 1 : 23)
      game.launch(1-side, aim: Vec(x: 6, y: side == 0 ? 20 : 3.77), kind: .cross)
      let initial = game.players[side].pos
      for _ in 0..<500 { game.step(1/120, interactiveRally: true, random: { 0.99 }) }
      XCTAssertGreaterThan(game.players[side].pos.distance(to: initial), 3)
      XCTAssertLessThan(game.players[side].pos.distance(to: game.players[side].destination), 0.1)
      XCTAssertEqual(game.flight?.waitingForSwipe, true)
      let held = try XCTUnwrap(game.flight).elapsed
      game.tapCourt(side, at: Vec(x: 4, y: side == 0 ? 2 : 22))
      for _ in 0..<120 { game.step(1/120, interactiveRally: true, random: { 0.99 }) }
      XCTAssertEqual(game.phase, .live)
      XCTAssertEqual(game.flight?.elapsed, held)
      XCTAssertEqual(game.contactSerial, 1)
      let saved = try JSONEncoder().encode(game)
      var strikes: [BallFlight] = []
      for length in [16.0, 82, 148] {
        var resumed = try JSONDecoder().decode(PracticeEngine.self, from: saved)
        let epoch = try XCTUnwrap(resumed.shotGestureEpoch(side))
        let swipe = Vec(x: 0, y: -length)
        let expected = try XCTUnwrap(resumed.swipeLanding(swipe, side: side))
        resumed.apply(.shotSwipe(swipe), side: side, shotEpoch: epoch)
        for _ in 0..<300 where resumed.contactSerial == 1 {
          resumed.step(1/120, interactiveRally: true, random: { 0.99 })
        }
        let outgoing = try XCTUnwrap(resumed.flight)
        XCTAssertEqual(outgoing.hitter, side)
        XCTAssertEqual(outgoing.landing, expected)
        XCTAssertEqual(outgoing.swingStrength, ShotSwipe.strength(length))
        strikes.append(outgoing)
        resumed.apply(.shotSwipe(swipe), side: side, shotEpoch: epoch)
        for _ in 0..<400 { resumed.step(1/120, interactiveRally: true, random: { 0.99 }) }
        XCTAssertEqual(resumed.contactSerial, 2)
        XCTAssertEqual(resumed.flight?.waitingForSwipe, true)
      }
      for (flight, expected) in zip(strikes, [55.0, 82.5, 110]) {
        XCTAssertEqual(Double(flight.launchSpeedKPH), expected, accuracy: 0.5)
      }
      let depths = strikes.map { abs($0.landing.y - PracticeEngine.net) }
      XCTAssertTrue(depths[0] < depths[1] && depths[1] < depths[2])
    }
  }

  func testBounceKeepsExistingRunAndPlantedPlayerUntilNextStrike() throws {
    for receiver in 0...1 {
      let hitter = 1 - receiver
      var game = PracticeEngine(settings: .init(local: true))
      game.phase = .live
      let y = receiver == 0 ? 22.0 : 1.77
      let still = Vec(x: 4, y: PracticeEngine.length - y)
      game.players[hitter].pos = still
      game.launch(hitter, aim: Vec(x: 7, y: receiver == 0 ? 18 : 5.77), kind: .cross)
      let route = Vec(x: 3, y: y)
      game.players[receiver].pos = Vec(x: 1, y: y)
      game.players[receiver].velocity = Vec(x: 2.5, y: 0)
      game.move(receiver, to: route)
      game.players[hitter].destination = still
      game.players[hitter].velocity = .zero
      let f = try XCTUnwrap(game.flight)
      game.flight?.swipeHoldTime = f.duration
      game.flight?.elapsed = f.time(at: 0.8) - 0.001
      game.step(1/120, interactiveRally: true)
      XCTAssertEqual(game.bounceSerial, 1)
      XCTAssertEqual(game.committedRun(receiver), route)
      XCTAssertEqual(game.committedRun(hitter), still)
      game = try JSONDecoder().decode(PracticeEngine.self, from: JSONEncoder().encode(game))
      game.apply(.move(Vec(x: 0.5, y: y)), side: receiver, movementEpoch: game.contactSerial)
      game.recover(receiver)
      game.steer(hitter, to: Vec(x: 1, y: still.y))
      XCTAssertEqual(game.players[receiver].destination, route)
      var lastX = game.players[receiver].pos.x
      for _ in 0..<200 {
        game.updateFootwork(1/120)
        XCTAssertGreaterThanOrEqual(game.players[receiver].pos.x, lastX)
        XCTAssertLessThanOrEqual(game.players[receiver].pos.x, route.x)
        XCTAssertEqual(game.players[hitter].pos, still)
        lastX = game.players[receiver].pos.x
      }
      XCTAssertEqual(game.players[receiver].pos, route)
      game.selectShotSwipe(Vec(x: 0, y: -100), side: receiver)
      XCTAssertNotNil(game.players[receiver].swingStrength)
      game.launch(receiver, aim: still, kind: .line)
      XCTAssertNil(game.committedRun(receiver))
      game.move(receiver, to: Vec(x: 1, y: y))
      XCTAssertEqual(game.players[receiver].destination.x, 1)
    }
  }

  func testGaugesFollowServerAndDisappearWhenServeIsCommitted() {
    for local in [false, true] {
      for server in 0...1 {
        var game = PracticeEngine(settings: .init(local: local))
        game.scoring = PracticeScore(format: .tennis, firstServer: server)
        game.start()
        XCTAssertEqual(game.displayedServeGauges?.server, server)
        if game.humanServing {
          game.requestServe(server)
          for _ in 0..<60 { game.step(1/120) }
          XCTAssertEqual(game.servePreparation?.isTossing, true)
          if server == 0 { XCTAssertEqual(game.coachCue, .hitServe) }
        } else {
          for _ in 0..<600 where game.servePreparation?.isTossing == false {
            game.step(1 / 120)
          }
          XCTAssertEqual(game.servePreparation?.isTossing, true)
        }
        XCTAssertNil(game.displayedServeGauges)
        game.prepareSecondServe()
        XCTAssertEqual(game.displayedServeGauges?.profile, .standard(2))
        XCTAssertEqual(game.displayedServeGauges?.server, server)
      }
    }
  }

  func testServePhysicsAndFaultOddsFollowBothMeters() {
    var game = serving()
    let blue = game.servePreparation!.target
    for speed in ServeLevel.allCases {
      var speeds: [Int] = [], kicks: [Double] = [], risks: [Double] = []
      for spin in ServeLevel.allCases {
        let profile = ServeProfile(speed: speed, spin: spin)
        game.launch(0, aim: blue, kind: .cross, serve: true, serveProfile: profile)
        var flight = game.flight!
        flight.elapsed = flight.duration * 0.94
        speeds.append(flight.launchSpeedKPH)
        kicks.append(flight.height)
        risks.append(ServeDepth.moderate.faultChance(profile: profile))
      }
      XCTAssertEqual(speeds, Array(repeating: Int(ServeProfile(speed: speed, spin: .low).launchSpeedKPH), count: 3))
      XCTAssertTrue(kicks[0] < kicks[1] && kicks[1] < kicks[2])
      XCTAssertTrue(risks[0] > risks[1] && risks[1] > risks[2])
    }
    for spin in ServeLevel.allCases {
      let profiles = ServeLevel.allCases.map { ServeProfile(speed: $0, spin: spin) }
      XCTAssertGreaterThan(profiles[2].launchSpeedKPH, profiles[1].launchSpeedKPH)
      XCTAssertGreaterThan(profiles[1].launchSpeedKPH, profiles[0].launchSpeedKPH)
      XCTAssertGreaterThan(ServeDepth.moderate.faultChance(profile: profiles[2]), ServeDepth.moderate.faultChance(profile: profiles[1]))
    }
  }

  func testFirstFaultResetsMetersAndSecondFaultAwardsExactlyOnePoint() {
    var game = serving()
    for number in 1...2 {
      XCTAssertEqual(game.servePreparation?.profile, .standard(number))
      game.chooseServe(.wide, side: 0)
      game.adjustServe(speed: .high, spin: .low, side: 0)
      game.setUpTestServe(0)
      for _ in 0..<1000 {
        game.step(1 / 120, random: { 0.1 })
        if number == 1 && game.servePreparation?.number == 2 || game.phase == .point { break }
      }
      XCTAssertEqual(game.scoring.points, [0, number == 1 ? 0 : 1])
    }
    XCTAssertTrue(game.feedback.reason.contains("Double fault"))
    for _ in 0..<200 { game.step(1 / 120) }
    XCTAssertEqual(game.coach.records.count, 1)
  }

  func testOlderSavedServeAndFlightDecodeWithDefaults() throws {
    var game = serving(number: 2)
    game.aimServe(at: game.servePreparation!.target, side: 0)
    game.adjustServe(speed: .high, side: 0)
    var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(game.servePreparation!)) as? [String: Any])
    json.removeValue(forKey: "customProfile"); json.removeValue(forKey: "tuningDeadline")
    let saved = try JSONDecoder().decode(ServePreparation.self, from: JSONSerialization.data(withJSONObject: json))
    XCTAssertEqual(saved.profile, .standard(2))
    game.launch(0, aim: saved.target, kind: .cross, serve: true)
    var flight = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(game.flight!)) as? [String: Any])
    flight.removeValue(forKey: "receiverWrongFooted"); flight.removeValue(forKey: "serveProfile")
    let restored = try JSONDecoder().decode(BallFlight.self, from: JSONSerialization.data(withJSONObject: flight))
    XCTAssertNil(restored.receiverWrongFooted)
    XCTAssertGreaterThan(restored.duration, 0)
  }
}
