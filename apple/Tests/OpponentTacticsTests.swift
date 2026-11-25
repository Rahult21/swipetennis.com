import XCTest
@testable import TennisCore

final class OpponentTacticsTests: XCTestCase {
  private func randomSource() -> () -> Double {
    var seed: UInt64 = 73
    return { seed = seed &* 6364136223846793005 &+ 1442695040888963407
      return Double(seed >> 11) / 9007199254740992.0 }
  }
  private func incoming(_ level: Difficulty) -> PracticeEngine {
    var engine = PracticeEngine(settings: .init(difficulty: level))
    engine.phase = .live
    engine.players[0].pos = Vec(x: 2, y: 24)
    engine.players[1].pos = Vec(x: 6, y: 1)
    engine.players[1].destination = engine.players[1].pos
    engine.launch(0, aim: Vec(x: 6, y: 1), kind: .cross)
    engine.flight!.contact = engine.players[1].pos
    engine.ball = engine.players[1].pos
    return engine
  }
  func testShortBallAndGoldUseBounceDepthOnBothCourtEnds() {
    for side in 0...1 {
      for depth in [4.99, 5.0, 5.01, 8] {
        var engine = incoming(.easy)
        engine.launch(1-side, aim: Vec(x: 3, y: side == 0 ? 23.77-depth : depth), kind: .cross)
        engine.players[side].pos.y = side == 0 ? 14 : 9 // Near-net intercept cannot redefine a deep ball.
        XCTAssertEqual(engine.showsGoldenContact(side), depth >= 5)
        if side == 0 { XCTAssertEqual(engine.coach.receiving?.shortBall, depth >= 5) }
        engine.flight!.serve = true
        XCTAssertFalse(engine.showsGoldenContact(side))
        engine.flight!.serve = false; engine.flight!.fault = "net"
        XCTAssertFalse(engine.showsGoldenContact(side))
      }
    }
  }
  func testBaselineShortBallsHaveRequestedAveragesAndNonRepeatingIntervals() {
    for level in Difficulty.allCases {
      let random = randomSource()
      var shorts = 0, clean = 0, since = 0
      var intervals = Set<Int>()
      var engine = incoming(level)
      for _ in 0..<6000 {
        engine.phase = .live
        engine.launch(0, aim: Vec(x: 6, y: 1), kind: .cross)
        engine.flight!.contact = engine.players[1].pos
        engine.returnBall(1, volley: false, random: random)
        guard engine.flight?.fault == nil else { continue }
        clean += 1; since += 1
        if engine.showsGoldenContact(0) {
          shorts += 1; intervals.insert(since); since = 0
          XCTAssertGreaterThanOrEqual(23.77-engine.flight!.contact.y, 5)
        }
      }
      XCTAssertEqual(Double(shorts)/Double(clean), level.shortBallChance, accuracy: 0.025)
      XCTAssertGreaterThan(intervals.count, 5)
    }
  }
  func testApproachReplyRatesAreRandomAndScaleWithDifficulty() {
    for level in Difficulty.allCases {
      let random = randomSource()
      var counts: [ApproachReply: Int] = [:]
      for _ in 0..<15000 { counts[level.approachReply(random: random), default: 0] += 1 }
      let challenge = Double((counts[.lob] ?? 0) + (counts[.passing] ?? 0))/15000
      let misses = Double(counts[.miss] ?? 0)/15000
      XCTAssertEqual(challenge, level == .easy ? 0 : level == .medium ? 0.5 : 0.75, accuracy: 0.02)
      XCTAssertEqual(misses, level == .easy ? 1/3 : level == .medium ? 0.15 : 0.05, accuracy: 0.02)
      if level != .easy { XCTAssertGreaterThan(counts[.lob] ?? 0, 0); XCTAssertGreaterThan(counts[.passing] ?? 0, 0) }
    }
  }
  func testApproachOverridesOldErrorOnceAndProducesActualLobPassOrSoftFeed() {
    for (level, roll, reply) in [(Difficulty.easy, 0.8, ApproachReply.volley),
      (.medium, 0.6, .lob), (.tough, 0.9, .passing)] {
      var engine = incoming(level)
      engine.flight!.opponentReplyPrepared = true
      engine.flight!.opponentError = .unreachable
      engine.flight!.missedChaseTarget = Vec(x: 4, y: 1)
      engine.followShot(0)
      engine.prepareOpponentReply(random: { roll })
      XCTAssertEqual(engine.flight?.approachReply, reply)
      XCTAssertNil(engine.flight?.opponentError)
      XCTAssertNil(engine.flight?.missedChaseTarget)
      for _ in 0..<10 { engine.prepareOpponentReply(random: { 0 }) }
      XCTAssertEqual(engine.flight?.approachReply, reply)
      engine.returnBall(1, volley: false, random: { 0.5 })
      XCTAssertNil(engine.flight?.fault)
      XCTAssertEqual(engine.flight?.hitter, 1)
      if reply == .volley { XCTAssertGreaterThanOrEqual(engine.flight!.duration, 2.5); XCTAssertLessThan(engine.flight!.loft, 1) }
      if reply == .lob { XCTAssertEqual(engine.flight?.kind, .lob); XCTAssertGreaterThan(engine.flight!.landing.y, 22.5) }
      if reply == .passing { XCTAssertGreaterThan(engine.flight!.landing.x, 7); XCTAssertLessThan(engine.flight!.loft, 1) }
    }
  }
  func testPressureMissTypesRemainVariedAndCannotBeRerolledEachFrame() {
    var errors = Set<OpponentError>()
    for roll in [0.01, 0.3, 0.6, 0.95] {
      var engine = incoming(.easy)
      engine.players[1].pos = Vec(x: 1, y: 1)
      engine.followShot(0)
      var draws = 0
      engine.prepareOpponentReply(random: { draws += 1; return draws == 1 ? 0.1 : roll })
      errors.insert(engine.flight!.opponentError!)
      for _ in 0..<20 { engine.prepareOpponentReply(random: { XCTFail("Reply rerolled"); return 0.9 }) }
      if engine.flight?.opponentError == .unreachable { XCTAssertNotNil(engine.flight?.missedChaseTarget) }
    }
    XCTAssertEqual(errors, Set(OpponentError.allCases))
  }
  func testPointReasonsExplainEveryAwardAndKeepRecoveryFailureSpecific() throws {
    for rule in CoachRule.allCases {
      for success in [true,false] {
        let event = CoachEvent(rule: rule, opportunity: 1, success: success)
        XCTAssertFalse(event.reason.isEmpty)
        XCTAssertEqual(event.points, success ? 2 : -1)
      }
    }
    var coach = Coachability()
    coach.recovery = CoachRecovery(white: .zero, from: .zero, reachedWhite: true, receivedReply: true)
    coach.finishPoint(award: .point, winner: 1, format: .tennis, time: 1)
    XCTAssertTrue(try XCTUnwrap(coach.events.last).reason.contains("missed the split at the far bounce"))
    let restored = try JSONDecoder().decode(CoachPointRecord.self, from: JSONEncoder().encode(coach.records[0]))
    XCTAssertEqual(restored.events[0].reason, coach.events[0].reason)
  }
  func testAppleNameShowsOnlyFirstFiveAndNeverInventsMissingLegacyCharacters() {
    XCTAssertEqual(ApplePlayerName.display("rahulmore@example.com"), "rahul")
    XCTAssertEqual(ApplePlayerName.display("ab"), "ab")
    XCTAssertEqual(ApplePlayerName.display("ra•••l"), "You")
    XCTAssertEqual(ApplePlayerName.display(nil), "You")
  }
}
