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

  func testOneSecondStartsOnReleaseAndFirstChangeKeepsBothMetersOpen() throws {
    var game = serving()
    XCTAssertFalse(game.servePreparation!.canTune)
    let blue = game.servePreparation!.target
    game.aimServe(at: blue, side: 0, finished: false)
    for _ in 0..<240 { game.step(1 / 120) }
    XCTAssertFalse(game.servePreparation!.canTune)
    game.aimServe(at: blue, side: 0)
    for _ in 0..<119 { game.step(1 / 120) }
    game.adjustServe(speed: .medium, side: 0)
    for _ in 0..<240 { game.step(1 / 120) }
    game.adjustServe(spin: .high, side: 0)
    XCTAssertEqual(game.servePreparation!.profile, ServeProfile(speed: .medium, spin: .high))
    let restored = try JSONDecoder().decode(PracticeEngine.self, from: JSONEncoder().encode(game))
    XCTAssertEqual(restored.servePreparation!.profile, game.servePreparation!.profile)
    XCTAssertTrue(restored.servePreparation!.canTune)
    game.requestServe(0)
    game.adjustServe(spin: .low, side: 0)
    XCTAssertEqual(game.servePreparation!.profile.spin, .high)
  }

  func testExpiredWindowUsesDefaultsUntilANewPlacement() {
    for number in 1...2 {
      var game = serving(number: number)
      let target = game.servePreparation!.target
      game.aimServe(at: target, side: 0)
      for _ in 0..<121 { game.step(1 / 120) }
      game.aimServe(at: target, side: 0)
      game.adjustServe(speed: .medium, spin: .medium, side: 0)
      XCTAssertFalse(game.servePreparation!.canTune)
      XCTAssertNil(game.servePreparation!.customProfile)
      XCTAssertEqual(game.servePreparation!.profile, .standard(number))
      XCTAssertFalse(game.servePreparation!.isTossing)
      game.chooseServe(.wide, side: 0)
      XCTAssertTrue(game.servePreparation!.canTune)
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
          XCTAssertEqual(game.servePreparation?.isTossing, false)
          if server == 0 { XCTAssertEqual(game.coachCue, .watch) }
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
      var durations: [Double] = [], kicks: [Double] = [], risks: [Double] = []
      for spin in ServeLevel.allCases {
        let profile = ServeProfile(speed: speed, spin: spin)
        game.launch(0, aim: blue, kind: .cross, serve: true, serveProfile: profile)
        var flight = game.flight!
        flight.elapsed = flight.duration * 0.94
        durations.append(flight.duration)
        kicks.append(flight.height)
        risks.append(profile.faultChance(number: 2))
      }
      XCTAssertTrue(durations[0] < durations[1] && durations[1] < durations[2])
      XCTAssertTrue(kicks[0] < kicks[1] && kicks[1] < kicks[2])
      XCTAssertTrue(risks[0] > risks[1] && risks[1] > risks[2])
    }
    for spin in ServeLevel.allCases {
      let profiles = ServeLevel.allCases.map { ServeProfile(speed: $0, spin: spin) }
      XCTAssertGreaterThan(profiles[2].pace, profiles[1].pace)
      XCTAssertGreaterThan(profiles[1].pace, profiles[0].pace)
      XCTAssertGreaterThan(profiles[2].faultChance(number: 2), profiles[1].faultChance(number: 2))
      XCTAssertGreaterThan(profiles[2].faultChance(number: 2), profiles[2].faultChance(number: 1))
    }
  }

  func testFirstFaultResetsMetersAndSecondFaultAwardsExactlyOnePoint() {
    var game = serving()
    for number in 1...2 {
      XCTAssertEqual(game.servePreparation?.profile, .standard(number))
      game.chooseServe(.wide, side: 0)
      game.adjustServe(speed: .high, spin: .low, side: 0)
      game.requestServe(0)
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
