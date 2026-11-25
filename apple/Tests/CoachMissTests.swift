import XCTest
@testable import TennisCore

final class CoachMissTests: XCTestCase {
  private func receiving(recovered: Bool, splitAtBounce: Bool = false) -> PracticeEngine {
    var engine = PracticeEngine(settings: .init(allCourtTraining: false))
    engine.phase = .live
    engine.players[0].pos = Vec(x: 1.4, y: 24.5)
    engine.players[0].destination = engine.players[0].pos
    engine.launch(0, aim: Vec(x: 6, y: 2), kind: .cross)
    if recovered {
      engine.players[0].pos = engine.coach.recovery!.white
      engine.updateCoachRecovery()
    }
    if splitAtBounce {
      engine.flight!.elapsed = engine.flight!.duration * 0.8
      engine.beginSplit(0)
    }
    engine.launch(1, aim: Vec(x: 2, y: 22.5), kind: .cross)
    return engine
  }

  func testRecoveryWarnsAtReturnDeadlineWithoutDeductingEarlyOrRepeating() {
    for recovered in [false, true] {
      var engine = receiving(recovered: recovered)
      engine.flight!.elapsed = engine.flight!.duration * 0.7
      engine.updateCoachRecovery()
      XCTAssertTrue(engine.coach.misses.isEmpty)
      engine.coach.finishRecoveryCycle()
      let miss = engine.coach.misses.first
      XCTAssertEqual(miss?.rule, .recoveryAndSplit)
      XCTAssertNil(miss?.points)
      XCTAssertEqual(miss?.correction, recovered ? "Tap at white as your shot bounces on the far court." : "Reach white, then tap to split.")
      XCTAssertEqual(engine.coach.pointScore, 0)
      for _ in 0..<120 { engine.updateCoachRecovery() }
      engine.end(0, reason: "Point", tip: "")
      XCTAssertEqual(engine.coach.pointScore, -1)
      XCTAssertEqual(engine.coach.misses.filter { $0.rule == .recoveryAndSplit }.count, 1)
    }
  }

  func testEveryFailedBaselineCycleWarnsButRuleSevenScoresOnce() {
    var engine = receiving(recovered: false)
    engine.coach.finishRecoveryCycle()
    engine.launch(0, aim: Vec(x: 6, y: 2), kind: .cross)
    engine.launch(1, aim: Vec(x: 2, y: 22.5), kind: .cross)
    engine.coach.finishRecoveryCycle()
    XCTAssertEqual(engine.coach.misses.count, 2)
    engine.end(0, reason: "Point", tip: "")
    XCTAssertEqual(engine.coach.events.filter { $0.rule == .recoveryAndSplit }.map(\.points), [-1])
  }

  func testCorrectRecoveryAndActualNetApproachDoNotWarn() {
    var correct = receiving(recovered: true, splitAtBounce: true)
    correct.flight!.elapsed = 0.2
    correct.updateCoachRecovery()
    correct.coach.finishRecoveryCycle()
    XCTAssertTrue(correct.coach.misses.isEmpty)
    var approach = receiving(recovered: false)
    approach.followingApproach[0] = true
    approach.players[0].pos.y -= 0.6
    approach.flight!.elapsed = 0.2
    approach.updateCoachRecovery()
    approach.coach.finishRecoveryCycle()
    XCTAssertTrue(approach.coach.misses.isEmpty)
    XCTAssertEqual(approach.coach.recoveryCycles, 0)
  }

  func testAllOtherMissedRulesQueueOnceAndSurvivePointTransition() {
    var coach = Coachability()
    for rule in CoachRule.allCases where rule != .recoveryAndSplit {
      coach.record(rule, opportunity: 1, success: false, time: 0)
      coach.record(rule, opportunity: 1, success: false, time: 0)
    }
    XCTAssertEqual(coach.misses.count, 6)
    XCTAssertTrue(coach.misses.allSatisfy { $0.points == -1 })
    var presentation = CoachMissPresentation()
    presentation.update(coach: coach, delta: 0)
    coach.finishPoint(award: .point, winner: 1, format: .tennis, time: 1)
    coach.startPoint()
    var shown: [CoachRule] = []
    for _ in 0..<6 {
      shown.append(presentation.current!.rule)
      presentation.update(coach: coach, delta: CoachMissPresentation.duration)
    }
    XCTAssertEqual(shown, Array(CoachRule.allCases.prefix(6)))
    XCTAssertNil(presentation.current)
    presentation.update(coach: coach, delta: 3)
    XCTAssertNil(presentation.current)
  }

  func testRingFadesBeforeCaptionAndRestartClearsPresentation() {
    var coach = Coachability()
    coach.record(.deepCenterLob, opportunity: 2, success: false, time: 0)
    var presentation = CoachMissPresentation()
    presentation.update(coach: coach, delta: 0)
    XCTAssertEqual(presentation.ringProgress, 0)
    presentation.update(coach: coach, delta: 0.9)
    XCTAssertNil(presentation.ringProgress)
    XCTAssertNotNil(presentation.current)
    presentation.update(coach: Coachability(), delta: 0)
    XCTAssertNil(presentation.current)
  }

  func testNewMissImmediatelyPulsesFeetWhileEarlierCaptionRemains() {
    var coach = Coachability()
    coach.record(.deepCenterLob, opportunity: 1, success: false, time: 0)
    var presentation = CoachMissPresentation()
    presentation.update(coach: coach, delta: 0)
    presentation.update(coach: coach, delta: 1)
    XCTAssertNil(presentation.ringProgress)
    coach.record(.shortBallApproach, opportunity: 2, success: false, time: 1)
    presentation.update(coach: coach, delta: 0)
    XCTAssertEqual(presentation.ringProgress, 0)
    XCTAssertEqual(presentation.current?.rule, .deepCenterLob)
    presentation.update(coach: coach, delta: 1.4)
    XCTAssertEqual(presentation.current?.rule, .shortBallApproach)
    XCTAssertNil(presentation.ringProgress)
  }
}
