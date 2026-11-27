import XCTest

@testable import TennisCore

final class PracticeDifficultyTests: XCTestCase {
  private func incomingBall(
    _ engine: inout PracticeEngine, receiver: Int = 1, x: Double = 2,
    balanced: Bool = true
  ) {
    let contact = Vec(x: x, y: receiver == 1 ? 1 : PracticeEngine.length - 1)
    engine.phase = .live
    engine.players[receiver].pos = contact
    engine.players[receiver].destination = contact
    engine.players[receiver].velocity = balanced ? .zero : Vec(x: 4, y: 0)
    engine.players[receiver].settled = balanced ? 0.25 : 0
    engine.ball = contact
    engine.flight = BallFlight(
      from: Vec(x: 4, y: receiver == 1 ? 23 : 1), landing: contact, contact: contact,
      duration: 2, hitter: 1 - receiver, fault: nil, explanation: "", loft: 1)
  }

  func testRecoveryKeepsCourtPlusFourFeetAndThreeFootCrosscourtOffset() {
    let center = PracticeEngine.width / 2
    for side in 0...1 {
      for x in [-0.5, 0, 2, center, 6, PracticeEngine.width, 9] {
        let opponent = Vec(x: x, y: side == 0 ? 1 : 23)
        let destination = PracticeEngine.recovery(side, opponent)
        XCTAssertEqual(destination.distance(to: opponent), 23.77 + 1.2192, accuracy: 0.000001)
        XCTAssertLessThanOrEqual(abs(destination.x-center), 0.9144 + 0.000001)
        if x < center { XCTAssertGreaterThan(destination.x, center) }
        if x > center { XCTAssertLessThan(destination.x, center) }
        if x == center { XCTAssertEqual(destination.x, center) }
      }
      let nearby = PracticeEngine.recovery(side, Vec(x: center + 0.3, y: 12))
      XCTAssertEqual(nearby.x, center - 0.3, accuracy: 0.000001)
      let wide = PracticeEngine.recovery(side, Vec(x: 0, y: 12))
      XCTAssertEqual(abs(wide.x-center), 0.9144, accuracy: 0.000001)
    }
  }

  func testRecoverControlUsesBaselineGuideLocation() {
    var engine = PracticeEngine(settings: PracticeSettings())
    incomingBall(&engine, x: 7)
    engine.recover(0)
    XCTAssertEqual(engine.players[0].destination.distance(to: engine.players[1].pos), PracticeEngine.recoveryDistance, accuracy: 0.00001)
    XCTAssertEqual(
      engine.players[0].destination.x, PracticeEngine.width / 2 - 0.9144, accuracy: 0.000001)
  }

  func testWhiteTracksOpponentDepthAndOnlyAnExplicitRecoveryFollowsIt() throws {
    for side in 0...1 {
      var game = PracticeEngine(settings: .init(local: true))
      game.phase = .live
      let center = PracticeEngine.width/2
      func atDepth(_ depth: Double) -> Vec {
        Vec(x: center, y: side == 0 ? depth : PracticeEngine.length-depth)
      }
      game.players[1-side].pos = atDepth(0)
      game.launch(side, aim: atDepth(2), kind: .cross)
      game.recover(side)
      for depth in [-3.5, -1.2192, 0, 4.0] {
        game.players[1-side].pos = atDepth(depth)
        game.players[1-side].destination = atDepth(depth)
        game.updateFootwork(1/120)
        let white = try XCTUnwrap(game.recoveryGuide(side))
        XCTAssertEqual(white, game.players[side].destination)
        XCTAssertEqual(white.distance(to: atDepth(depth)), 24.9892, accuracy: 0.000001)
        XCTAssertEqual(white.y, atDepth(PracticeEngine.length+depth+1.2192).y, accuracy: 0.000001)
        if side == 0 {
          game.updateCoachRecovery()
          XCTAssertEqual(game.coach.recovery?.white, white)
        }
      }
      let manual = atDepth(PracticeEngine.length-2)
      game.move(side,to:manual)
      game.updateFootwork(1/120)
      XCTAssertEqual(game.players[side].destination, manual)
      XCTAssertEqual(PracticeEngine.recovery(side, atDepth(11)).y,
        side == 0 ? CourtRunoff.depth.upperBound-1 : CourtRunoff.depth.lowerBound+1)
    }
  }

  func testEasyAlwaysAimsCrosscourtAcrossAllStylesAndOpponentPositions() {
    for style in BotStyle.allCases {
      var engine = PracticeEngine(settings: PracticeSettings(difficulty: .easy, style: style))
      for botX in [1.0, 3, 5, 7] {
        for humanX in [1.0, 7] {
          incomingBall(&engine, x: botX)
          engine.players[0].pos.x = humanX
          engine.players[1].aim = Vec(x: botX, y: 23)  // A same-side aim must not override Easy.
          engine.players[1].kind = .line
          engine.returnBall(1, volley: false, random: { 0.99 })
          let flight = engine.flight!
          XCTAssertLessThan((flight.from.x - 4.115) * (flight.landing.x - 4.115), 0)
          XCTAssertLessThan(flight.loft, 2)  // Retriever still sends a crosscourt drive, not a lob.
        }
      }
    }
  }

  func testDifficultyLapseScheduleCarriesAcrossPointsIndependentlyOfPlacementRolls() {
    for difficulty in Difficulty.allCases {
      for roll in [0.0, 0.49, 0.999] {
        var engine = PracticeEngine(settings: .init(difficulty: difficulty))
        let range = difficulty.errorInterval
        let expected = range.lowerBound + Int(roll * Double(range.count))
        for attempt in 1...(expected * 3) {
          incomingBall(&engine)
          engine.prepareOpponentReply(random: { roll })
          XCTAssertEqual(engine.flight?.opponentError != nil, attempt.isMultiple(of: expected))
          engine.returnBall(1, volley: false, random: { 0.9 })
          XCTAssertEqual(engine.flight?.fault != nil, attempt.isMultiple(of: expected),
            "An accurate placement roll still respects a scheduled forced error")
          engine.phase = .point
          engine.startRally() // Points and opening serves do not reset or consume the interval.
        }
      }
    }
  }

  func testAllScheduledErrorsAndIntervalsAreRandomized() {
    var seed: UInt64 = 57
    func random() -> Double {
      seed = seed &* 6364136223846793005 &+ 1442695040888963407
      return Double(seed >> 11) / Double(UInt64.max >> 11)
    }
    for difficulty in Difficulty.allCases {
      var plan = OpponentErrors()
      var seen: Set<String> = []
      var intervals: Set<Int> = []
      var sinceError = 0
      for _ in 0..<3000 {
        sinceError += 1
        if let fault = plan.next(difficulty: difficulty, canMissByFootwork: true, random: random) {
          XCTAssertTrue(difficulty.errorInterval.contains(sinceError))
          intervals.insert(sinceError)
          seen.insert(fault.rawValue)
          sinceError = 0
        }
      }
      XCTAssertEqual(seen, Set(OpponentError.allCases.map(\.rawValue)))
      XCTAssertEqual(intervals, Set(difficulty.errorInterval))
    }
  }

  func testNetWideAndLongErrorsAwardExactlyOnePoint() {
    for (roll, fault) in [(0.0, "net"), (0.4, "wide"), (0.99, "long")] {
      var engine = PracticeEngine(settings: .init())
      for _ in 0..<3 {
        incomingBall(&engine)
        engine.returnBall(1, volley: false, random: { 0 })
      }
      incomingBall(&engine)
      engine.prepareOpponentReply(random: { roll })
      engine.returnBall(1, volley: false, random: { 0 })
      XCTAssertEqual(engine.flight?.fault, fault)
      XCTAssertEqual(engine.contactGuide(0) == nil, fault == "net")
      XCTAssertNil(engine.contactWindow(0))
      for _ in 0..<500 { engine.step(1 / 120, random: { 0 }) }
      XCTAssertEqual(engine.scoring.points, [1, 0])
      XCTAssertEqual(engine.phase, .point)
    }
  }

  func testMissedChaseKeepsARealGapAndHasNoFakeReturn() {
    var engine = PracticeEngine(settings: .init())
    for _ in 0..<3 {
      incomingBall(&engine)
      engine.returnBall(1, volley: false, random: { 0 })
    }
    incomingBall(&engine, x: 7)
    engine.players[1].pos = Vec(x: 1, y: 1)
    engine.players[1].destination = engine.players[1].pos
    let serial = engine.contactSerial
    engine.step(1 / 120, random: { 0.6 })
    XCTAssertEqual(engine.flight?.opponentError, .unreachable)
    XCTAssertNil(engine.contactWindow(1))
    XCTAssertNil(engine.flight?.fault)
    for _ in 0..<400 { engine.step(1 / 120, random: { 0.6 }) }
    XCTAssertGreaterThan(engine.players[1].pos.distance(to: engine.flight!.contact), 1.35)
    XCTAssertEqual(engine.contactSerial, serial)
    XCTAssertEqual(engine.scoring.points, [1, 0])
    XCTAssertEqual(engine.feedback.reason, "Opponent didn't reach the ball in time.")
  }

  func testRepeatedFramesOnlyCountOneReturnOpportunityAndApproachControlsFeed() {
    var engine = PracticeEngine(settings: .init())
    incomingBall(&engine)
    for _ in 0..<10 { engine.prepareOpponentReply(random: { 0 }) }
    XCTAssertEqual(engine.opponentErrors.remaining, 3)
    incomingBall(&engine)
    engine.flight!.trainingApproach = true
    engine.followShot(0)
    engine.returnBall(1, volley: false, random: { 0.99 })
    XCTAssertTrue(engine.flight!.trainingReply)
    XCTAssertNil(engine.flight!.fault)
    XCTAssertEqual(engine.opponentErrors.remaining, 3)
    incomingBall(&engine)
    engine.flight!.fault = "long"
    engine.prepareOpponentReply(random: { 0 })
    XCTAssertEqual(engine.opponentErrors.remaining, 3)
  }

  func testScheduledErrorsDoNotApplyToHumanOrLocalOpponent() {
    for (local, side) in [(false, 0), (true, 1)] {
      var engine = PracticeEngine(settings: PracticeSettings(local: local))
      for _ in 0..<8 {
        incomingBall(&engine, receiver: side)
        engine.returnBall(side, volley: false, random: { 0.99 })
        XCTAssertNil(engine.flight?.fault)
      }
    }
  }

}
