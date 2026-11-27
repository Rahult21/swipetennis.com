import XCTest
@testable import TennisCore

final class CoachabilityTests: XCTestCase {
  private func incoming(at point: Vec, serve: Int? = nil, difficulty: Difficulty = .easy,
    training: Bool = false) -> PracticeEngine {
    var engine = PracticeEngine(settings: .init(difficulty: difficulty, allCourtTraining: training))
    engine.phase = .live
    engine.players[0].pos = point
    engine.players[0].destination = point
    engine.players[1].pos = Vec(x: 6.5, y: 0.7)
    engine.launch(1, aim: Vec(x: point.x, y: point.y - 1.1), kind: .cross,
      serve: serve != nil, serveNumber: serve ?? 1)
    engine.flight!.contact = point
    engine.flight!.elapsed = engine.flight!.duration * 0.87
    engine.ball = point
    engine.registerCoachFlight()
    return engine
  }

  func testBehindBaselineCenterLobAndMissedChoiceScoreOnce() {
    for success in [true, false] {
      var engine = incoming(at: Vec(x: 1.4, y: 24.5))
      engine.selectShotSwipe(Vec(x: success ? 0 : 40, y: success ? 40 : -40), side: 0)
      if success { XCTAssertEqual(engine.players[0].aim!.x, PracticeEngine.width / 2) }
      engine.returnBall(0, volley: false, random: { 0.5 })
      XCTAssertEqual(engine.coach.events.filter { $0.rule == .deepCenterLob }.map(\.points), [success ? 2 : -1])
      engine.end(0, reason: "Done", tip: "")
      engine.end(1, reason: "Duplicate", tip: "")
      XCTAssertEqual(engine.coach.records.count, 1)
    }
  }

  func testShortBallAndDirectionChangeCanBothScoreInOneApproach() {
    var engine = incoming(at: Vec(x: 1.4, y: 19))
    engine.selectShotSwipe(Vec(x: 0, y: -40), side: 0)
    engine.returnBall(0, volley: false, random: { 0.5 })
    XCTAssertEqual(Set(engine.coach.approaches.map(\.rule)), [.shortBallApproach, .changeDirectionApproach])
    XCTAssertEqual(engine.coach.pointScore, 0) // Selecting a shot alone earns no approach reward.
    XCTAssertEqual(engine.movementGuide(0)?.kind, .approach)
    guard case .move(_, .approach) = engine.coachCue else { return XCTFail("Coach must show the forward swipe") }
    engine.followShot(0)
    for _ in 0..<55 { engine.step(1 / 120, random: { 0.5 }) }
    XCTAssertEqual(engine.coach.pointScore, 4)
    XCTAssertTrue(engine.coach.approaches.isEmpty)
    engine.followShot(0)
    for _ in 0..<10 { engine.step(1 / 120, random: { 0.5 }) }
    XCTAssertEqual(engine.coach.pointScore, 4)
  }

  func testMissedApproachCostsOneForEachRuleButNotAnImpossibleWindow() {
    var engine = incoming(at: Vec(x: 1.4, y: 19))
    engine.selectShotSwipe(Vec(x: 0, y: -40), side: 0)
    engine.returnBall(0, volley: false, random: { 0.5 })
    engine.time += 0.4
    engine.end(0, reason: "Point", tip: "")
    XCTAssertEqual(engine.coach.pointScore, -2)
    var quick = incoming(at: Vec(x: 1.4, y: 19))
    quick.selectShotSwipe(Vec(x: 0, y: -40), side: 0)
    quick.returnBall(0, volley: false, random: { 0.5 })
    quick.time += 0.1
    quick.end(0, reason: "Instant winner", tip: "")
    XCTAssertEqual(quick.coach.pointScore, 0)
  }

  func testFiveMetreBounceThresholdDoesNotPenalizeOrdinaryDeepBall() {
    // Fixture contact is 1.1 m behind the bounce.
    let threshold = PracticeEngine.length - 5 + 1.1
    XCTAssertTrue(incoming(at: Vec(x: 3, y: threshold - 0.01)).coach.receiving!.shortBall)
    XCTAssertFalse(incoming(at: Vec(x: 3, y: threshold + 0.01)).coach.receiving!.shortBall)
  }

  func testCoachShowsLobSwipeWhileRunningAfterYellowTap() {
    var engine = incoming(at: Vec(x: 1.4, y: 24.5))
    engine.players[0].pos = Vec(x: 4.1, y: 24.5)
    engine.players[0].destination = engine.players[0].pos
    guard case .move(_, .receive) = engine.coachCue else { return XCTFail("First show how to reach yellow") }
    engine.apply(.guidedMove(.receive), side: 0)
    XCTAssertEqual(engine.coachCue, .shot(.lob, 0))
    engine.selectShotSwipe(Vec(x: 0, y: 40), side: 0)
    XCTAssertEqual(engine.coachCue, .ready)
    XCTAssertEqual(engine.players[0].destination, engine.contactGuide(0))
  }

  func testFirstServeUpGoesBackAtServerWithoutConflictingLobRule() {
    var engine = incoming(at: Vec(x: 1.4, y: 24.22), serve: 1)
    XCTAssertFalse(engine.coach.receiving!.deepBall)
    engine.selectShotSwipe(Vec(x: 0, y: -40), side: 0)
    let serverX = engine.players[1].pos.x
    engine.returnBall(0, volley: false, random: { 0.5 })
    XCTAssertEqual(engine.flight!.landing.x, serverX)
    XCTAssertEqual(engine.coach.events.map(\.rule), [.firstServeBody])
    XCTAssertEqual(engine.coach.pointScore, 2)
    XCTAssertFalse(engine.flight!.trainingApproach)
  }

  func testEveryOpponentLevelRecordsCoachabilityWithOrWithoutTraining() throws {
    for difficulty in Difficulty.allCases {
      for training in [false, true] {
        var engine = incoming(at: Vec(x: 1.4, y: 24.22), serve: 1,
          difficulty: difficulty, training: training)
        engine.selectShotSwipe(Vec(x: 0, y: -40), side: 0)
        // Advance the real contact window: a timely arrival executes the chosen return.
        for _ in 0..<120 where engine.flight?.hitter == 1 {
          engine.step(1 / 120, random: { 0.5 })
        }
        XCTAssertEqual(engine.flight?.hitter, 0, "\(difficulty), training: \(training)")
        XCTAssertEqual(engine.coach.pointScore, 2)
        engine.end(0, reason: "Point", tip: "")
        let record = try XCTUnwrap(engine.coach.records.last)
        // This is the same Codable record queued by the game for /points.
        let uploaded = try JSONDecoder().decode(CoachPointRecord.self,
          from: JSONEncoder().encode(record))
        XCTAssertEqual(uploaded.events.map(\.rule), [.firstServeBody])
        XCTAssertEqual(uploaded.points, 2)
        XCTAssertEqual(uploaded.pointIndex, 1)
      }
    }
  }

  func testSecondServeYellowArrivalCountsThroughoutContactWindowButNotOutsideBaseline() {
    for (y, progress, expected) in [(22.67, 0.87, 2), (24.22, 0.87, -1), (22.67, 0.97, 2)] {
      var engine = incoming(at: Vec(x: 3, y: y), serve: 2)
      engine.flight!.elapsed = engine.flight!.duration * progress
      engine.returnBall(0, volley: false, random: { 0.5 })
      XCTAssertEqual(engine.coach.events.filter { $0.rule == .secondServeRise }.map(\.points), [expected])
    }
  }

  func testSecondServeYellowTapAndAutomaticReturnEarnOnRiseForEveryLevel() {
    for difficulty in Difficulty.allCases {
      var engine = PracticeEngine(settings: .init(difficulty: difficulty))
      engine.start(random: { 0.5 })
      engine.prepareSecondServe()
      engine.apply(.guidedMove(.receive), side: 0)
      XCTAssertTrue(engine.coach.events.isEmpty) // A command alone is not an arrival.
      for _ in 0..<1200 where engine.flight?.hitter != 0 && engine.phase.isPlaying {
        engine.step(1 / 120, random: { 0.5 })
      }
      XCTAssertEqual(engine.flight?.hitter, 0)
      XCTAssertNil(engine.flight?.fault)
      XCTAssertEqual(engine.coach.events.filter { $0.rule == .secondServeRise }.map(\.points), [2])
    }
  }

  func testSecondServeBackEdgeOfYellowStillEarnsOnRiseWithRealContactClock() {
    var engine = incoming(at: Vec(x: 3, y: PracticeEngine.length - 1.1), serve: 2)
    let yellow = engine.flight!.contact
    engine.players[0].pos.y += PracticeEngine.contactRadius
    engine.players[0].destination = engine.players[0].pos
    engine.flight!.elapsed = engine.flight!.duration * 0.8
    for _ in 0..<120 where engine.flight?.hitter == 1 && engine.phase == .live {
      engine.step(1 / 120, random: { 0.999 })
    }
    XCTAssertEqual(engine.flight?.hitter, 0)
    XCTAssertNil(engine.flight?.fault)
    XCTAssertEqual(engine.players[0].pos.distance(to: yellow), PracticeEngine.contactRadius, accuracy: 0.000001)
    XCTAssertEqual(engine.coach.events.filter { $0.rule == .secondServeRise }.map(\.points), [2])
  }

  func testSecondServeSwipeWithoutReachingYellowDoesNotEarnOnRise() {
    var engine = incoming(at: Vec(x: 3, y: 22.67), serve: 2)
    engine.players[0].pos = Vec(x: 7, y: 24.5)
    engine.apply(.guidedMove(.receive), side: 0)
    engine.end(1, reason: "Late to the serve", tip: "")
    XCTAssertEqual(engine.coach.events.filter { $0.rule == .secondServeRise }.map(\.points), [-1])
  }

  func testWideServeThenCrosscourtCombinationAndMissedAlternative() {
    for (wide, cross, expected) in [(true, true, 2), (false, true, -1), (true, false, -1)] {
      var engine = incoming(at: Vec(x: 2, y: 23))
      engine.coach.firstServeWasWide = wide
      engine.registerCoachFlight()
      engine.selectShotSwipe(Vec(x: cross ? 40 : 0, y: -40), side: 0)
      engine.returnBall(0, volley: false, random: { 0.5 })
      XCTAssertEqual(engine.coach.events.filter { $0.rule == .wideServeCross }.map(\.points), [expected])
    }
  }

  func testRepeatedOpportunitiesSamePointStackButDuplicateEventsDoNot() {
    var coach = Coachability()
    coach.record(.deepCenterLob, opportunity: 1, success: true, time: 1)
    coach.record(.deepCenterLob, opportunity: 1, success: false, time: 1)
    coach.record(.deepCenterLob, opportunity: 3, success: true, time: 3)
    coach.record(.firstServeBody, opportunity: 0, success: false, time: 0)
    XCTAssertEqual(coach.pointScore, 3)
    coach.finishPoint(award: .point, winner: 0, format: .tennis, time: 5)
    XCTAssertEqual(coach.gameScore, 3)
    coach.startPoint()
    coach.record(.secondServeRise, opportunity: 4, success: true, time: 7)
    coach.finishPoint(award: .game, winner: 0, format: .tennis, time: 9)
    XCTAssertEqual(coach.setScore, 5)
    XCTAssertEqual(coach.records.map(\.points), [3, 2])
    XCTAssertEqual(coach.gameScore, 0)
    XCTAssertEqual(coach.gameIndex, 2)
  }

  func testFirstFaultDoesNotAwardPointAndSecondServeShowsYellowOnBaseline() {
    var engine = PracticeEngine(settings: .init(local: true))
    engine.start(random: { 0.5 })
    for _ in 0..<120 { engine.step(1 / 120, random: { 0.5 }) }
    engine.requestServe(1)
    for _ in 0..<120 where engine.phase == .serving { engine.step(1 / 120, random: { 0 }) }
    XCTAssertEqual(engine.flight?.fault, "net")
    for _ in 0..<500 where engine.phase != .serveFault { engine.step(1 / 120, random: { 0.5 }) }
    XCTAssertEqual(engine.phase, .serveFault)
    XCTAssertEqual(engine.scoring.points, [0, 0])
    XCTAssertTrue(engine.coach.records.isEmpty)
    for _ in 0..<90 { engine.step(1 / 120, random: { 0.5 }) }
    XCTAssertEqual(engine.phase, .serving)
    XCTAssertEqual(engine.servePreparation?.number, 2)
    XCTAssertEqual(engine.contactGuide(0)!.y, PracticeEngine.length)
  }
}
