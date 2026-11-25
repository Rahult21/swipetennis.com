import XCTest

@testable import TennisCore

final class MovementGuideTests: XCTestCase {
  func testLineContactDoesNotMovePlayerUntilFollowSwipe() {
    var engine = PracticeEngine(settings: .init())
    engine.phase = .live
    engine.players[0].pos = Vec(x: 2, y: 23.4)
    engine.players[0].destination = engine.players[0].pos
    engine.flight = BallFlight(from: Vec(x: 6, y: 1), landing: Vec(x: 2, y: 22.3),
      contact: engine.players[0].pos, duration: 2, hitter: 1, fault: nil, explanation: "", loft: 1)
    engine.choose(0, .line)
    engine.returnBall(0, volley: false, random: { 0.99 })
    let position = engine.players[0].pos
    for _ in 0..<20 { engine.step(1 / 120, random: { 0.99 }) }
    XCTAssertEqual(engine.players[0].pos, position)
    XCTAssertFalse(engine.attacking[0])
    XCTAssertEqual(engine.tactics[0].approaches, 0)
    let guide = engine.movementGuide(0)!
    var gesture = PracticeGesture(side: 0)
    _ = gesture.update(at: guide.from, timestamp: 1)
    let action = gesture.update(at: Vec(x: guide.from.x, y: guide.from.y - 2), ended: true, timestamp: 1.2)!
    engine.apply(action, side: 0)
    engine.step(0.04)
    XCTAssertTrue(engine.attacking[0])
    XCTAssertLessThan(engine.players[0].pos.y, position.y)
    XCTAssertEqual(engine.tactics[0].approaches, 1)
  }

  func testLobDoesNotAutomaticallyRetargetHumanAndRecoveryIsExplicit() {
    var engine = PracticeEngine(settings: .init())
    engine.phase = .live
    engine.attacking[0] = true
    engine.followingApproach[0] = true
    engine.players[0].pos = Vec(x: 2, y: 16)
    engine.players[0].destination = engine.players[0].pos
    let original = engine.players[0].destination
    engine.launch(1, aim: Vec(x: 5, y: 20), kind: .lob)
    for _ in 0..<20 { engine.step(1 / 120) }
    XCTAssertEqual(engine.players[0].destination, original)
    XCTAssertFalse(engine.followingApproach[0])
    XCTAssertEqual(engine.movementGuide(0)?.kind, .receive)
    engine.apply(.guidedMove(.receive), side: 0)
    XCTAssertEqual(engine.players[0].destination, PracticeEngine.own(0, engine.intercept(0)))
    engine.recover(0)
    XCTAssertFalse(engine.attacking[0])
    XCTAssertEqual(engine.players[0].destination.y, PracticeEngine.length)
  }

  func testCoachShowsEachMovementOnceAndNeverMoreThanThreeTimes() {
    var coach = SwipeCoach()
    for kind in [MovementGuideKind.receive, .approach, .recover] {
      let guide = MovementGuide(kind: kind, from: Vec(x: 3, y: 23), to: Vec(x: 5, y: 16))
      coach.update(guide: guide, delta: 0)
      XCTAssertEqual(coach.active?.kind, kind)
      coach.update(guide: guide, delta: 2.5)
      XCTAssertNil(coach.active)
      for _ in 0..<10 { coach.update(guide: guide, delta: 1) }
      XCTAssertNil(coach.active)
      coach.update(guide: nil, delta: 0)
    }
    XCTAssertEqual(coach.shown.count, 3)
    coach.dismiss() // Also used between points and rematches; history is retained.
    coach.update(guide: MovementGuide(kind: .receive, from: .zero, to: Vec(x: 4, y: 20)), delta: 0)
    XCTAssertNil(coach.active)
  }

  func testInterruptedCoachAndHiddenGuidesDoNotReplayTheLesson() {
    var coach = SwipeCoach()
    coach.update(guide: nil, delta: 5)
    XCTAssertTrue(coach.shown.isEmpty)
    let guide = MovementGuide(kind: .receive, from: .zero, to: Vec(x: 4, y: 20))
    coach.update(guide: guide, delta: 0)
    coach.dismiss()
    coach.update(guide: guide, delta: 0.1)
    XCTAssertNil(coach.active)
    XCTAssertEqual(coach.shown.count, 1)
  }
}
