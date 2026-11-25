import XCTest
@testable import TennisCore

final class RecoveryCoachTests: XCTestCase {
  private func outgoing() -> PracticeEngine {
    var engine = PracticeEngine(settings: .init(allCourtTraining: false))
    engine.phase = .live
    engine.players[0].pos = Vec(x: 1.4, y: 24.5)
    engine.players[0].destination = engine.players[0].pos
    engine.launch(0, aim: Vec(x: 6, y: 2), kind: .cross)
    return engine
  }

  private func completeCycle(_ engine: inout PracticeEngine, recover: Bool = true, split: Bool = true) {
    if recover {
      engine.players[0].pos = engine.coach.recovery!.white
      engine.updateCoachRecovery()
    }
    engine.flight!.elapsed = engine.flight!.duration * 0.8
    if split { engine.beginSplit(0) }
    engine.launch(1, aim: Vec(x: 2, y: 22.5), kind: .cross)
    engine.coach.finishRecoveryCycle()
  }

  private func result(_ engine: PracticeEngine) -> [CoachEvent] {
    engine.coach.events.filter { $0.rule == .recoveryAndSplit }
  }

  func testEveryBaselineExchangeEarnsTwoOnceAtPointEnd() {
    var engine = outgoing()
    completeCycle(&engine)
    XCTAssertTrue(result(engine).isEmpty)
    engine.time += 1
    engine.launch(0, aim: Vec(x: 6, y: 2), kind: .cross)
    completeCycle(&engine)
    XCTAssertEqual(engine.coach.recoveryCycles, 2)
    engine.end(0, reason: "Point", tip: "")
    XCTAssertEqual(result(engine).map(\.points), [2])
    XCTAssertEqual(result(engine).first?.opportunity, 0)
    engine.end(1, reason: "Duplicate", tip: "")
    XCTAssertEqual(result(engine).count, 1)
  }

  func testOneMissedSequenceCostsOneEvenAfterLaterGoodRecovery() {
    for missedRecovery in [true, false] {
      var engine = outgoing()
      completeCycle(&engine, recover: !missedRecovery, split: missedRecovery)
      engine.time += 1
      engine.launch(0, aim: Vec(x: 6, y: 2), kind: .cross)
      completeCycle(&engine)
      engine.end(0, reason: "Point", tip: "")
      XCTAssertEqual(result(engine).map(\.points), [-1])
    }
  }

  func testTappingWhiteDoesNotCountUntilThePlayerArrives() {
    var engine = outgoing()
    engine.tapCourt(0, at: engine.recoveryGuide(0)!)
    XCTAssertFalse(engine.coach.recovery!.reachedWhite)
    for _ in 0..<150 { engine.updateFootwork(1 / 120); engine.updateCoachRecovery() }
    XCTAssertTrue(engine.coach.recovery!.reachedWhite)
  }

  func testSplitRequiresArrivalAndFarBounceEvenDuringTapCooldown() {
    var engine = outgoing()
    engine.tapCourt(0, at: engine.coach.recovery!.white)
    XCTAssertFalse(engine.coach.recovery!.splitAfterRecovery)
    engine.players[0].pos = engine.coach.recovery!.white
    engine.updateCoachRecovery()
    XCTAssertFalse(engine.coach.recovery!.splitAfterRecovery)
    engine.flight!.elapsed = engine.flight!.duration * 0.8
    // Even during the animation cooldown, the new tap after arrival must qualify.
    engine.tapCourt(0, at: engine.coach.recovery!.white)
    XCTAssertTrue(engine.coach.recovery!.splitAfterRecovery)
    XCTAssertEqual(engine.tactics[0].splitSteps, 1)
    engine.launch(1, aim: Vec(x: 2, y: 22.5), kind: .cross)
    engine.end(0, reason: "Point", tip: "")
    XCTAssertEqual(result(engine).map(\.points), [2])
  }

  func testAnyTapLocationCountsAtFarBounceAndIsTooLateOnIncomingBall() {
    for incoming in [false, true] {
      for location in 0..<4 {
        var engine = outgoing()
        let white = engine.coach.recovery!.white
        engine.players[0].pos = white
        engine.players[0].destination = white
        engine.flight!.elapsed = engine.flight!.duration * 0.8
        if incoming {
          engine.launch(1, aim: Vec(x: 2, y: 22.5), kind: .cross)
          engine.flight!.elapsed = engine.flight!.duration * 0.6
        }
        let target = [white, engine.contactGuide(0) ?? Vec(x: 2, y: 22),
          Vec(x: 1, y: 14), Vec(x: -1.65, y: PracticeEngine.net)][location]
        engine.tapCourt(0, at: target)
        XCTAssertEqual(engine.coach.recovery!.splitAfterRecovery, !incoming)
        XCTAssertEqual(engine.tactics[0].splitSteps, 1)
        if !incoming { engine.launch(1, aim: Vec(x: 2, y: 22.5), kind: .cross) }
        engine.end(0, reason: "Point", tip: "")
        XCTAssertEqual(result(engine).map(\.points), [incoming ? -1 : 2])
        XCTAssertEqual(engine.coach.misses.isEmpty, !incoming)
      }
    }
  }

  func testNoReturnNoBonusAndOpponentFaultHasNoRecoveryPenalty() {
    var winner = outgoing()
    winner.end(0, reason: "Winner", tip: "")
    XCTAssertTrue(result(winner).isEmpty)
    var fault = outgoing()
    fault.launch(1, aim: Vec(x: 2, y: 22), kind: .cross, fault: "long")
    fault.end(0, reason: "Out", tip: "")
    XCTAssertTrue(result(fault).isEmpty)
  }

  func testGenuineApproachesAndNetShotsAreExemptButAStationarySwipeIsNot() {
    var engine = outgoing()
    engine.followShot(0)
    engine.updateCoachRecovery()
    XCTAssertFalse(engine.coach.recovery!.exempt)
    engine.players[0].pos.y -= 0.6
    engine.updateCoachRecovery()
    XCTAssertTrue(engine.coach.recovery!.exempt)
    engine.launch(1, aim: Vec(x: 2, y: 18), kind: .lob)
    engine.coach.finishRecoveryCycle()
    XCTAssertEqual(engine.coach.recoveryCycles, 0)
    engine.launch(0, aim: Vec(x: 6, y: 2), kind: .line, stroke: .volley)
    XCTAssertTrue(engine.coach.recovery!.exempt)
    engine.launch(1, aim: Vec(x: 2, y: 18), kind: .lob)
    engine.end(0, reason: "Net point", tip: "")
    XCTAssertTrue(result(engine).isEmpty)
  }

  func testNewPointResetsConsistencyAndUnfinishedIncomingCycleIsAssessed() {
    var engine = outgoing()
    completeCycle(&engine, recover: false, split: false)
    engine.end(0, reason: "Point", tip: "")
    XCTAssertEqual(result(engine).map(\.points), [-1])
    engine.coach.startPoint()
    XCTAssertEqual(engine.coach.recoveryCycles, 0)
    XCTAssertTrue(engine.coach.consistentRecovery)
    engine.phase = .live
    engine.launch(0, aim: Vec(x: 6, y: 2), kind: .cross)
    engine.players[0].pos = engine.coach.recovery!.white
    engine.updateCoachRecovery()
    engine.time += 1
    engine.flight!.elapsed = engine.flight!.duration * 0.8
    engine.beginSplit(0)
    engine.launch(1, aim: Vec(x: 2, y: 22.5), kind: .cross)
    engine.end(1, reason: "Missed yellow despite good recovery", tip: "")
    XCTAssertEqual(result(engine).map(\.points), [2])
  }
}
