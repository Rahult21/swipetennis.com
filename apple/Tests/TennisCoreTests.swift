import XCTest

@testable import TennisCore

final class TennisCoreTests: XCTestCase {
  func match() -> TennisMatch { TennisMatch(players: [.init(name: "Alex"), .init(name: "Sam")]) }
  func game(_ m: inout TennisMatch, _ p: Int) {
    for _ in 0..<4 { m.record(winner: p, outcome: "Winner") }
  }
  func testDeuceAdvantageAndUndo() {
    var m = match()
    for _ in 0..<3 {
      m.record(winner: 0, outcome: "Winner")
      m.record(winner: 1, outcome: "Winner")
    }
    XCTAssertEqual(m.pointLabel(0), "40")
    m.record(winner: 0, outcome: "Ace")
    XCTAssertEqual(m.pointLabel(0), "AD")
    m.record(winner: 0, outcome: "Winner")
    XCTAssertEqual(m.games, [1, 0])
    XCTAssertEqual(m.server, 1)
    m.undo()
    XCTAssertEqual(m.games, [0, 0])
    XCTAssertEqual(m.pointLabel(0), "AD")
    XCTAssertEqual(m.server, 0)
  }
  func testFaultAndUndo() {
    var m = match()
    m.fault()
    XCTAssertEqual(m.serveAttempt, 2)
    XCTAssertEqual(m.log.count, 0)
    m.undo()
    XCTAssertEqual(m.serveAttempt, 1)
    m.fault()
    m.fault()
    XCTAssertEqual(m.points, [0, 1])
    XCTAssertEqual(m.log.last?.serve, 2)
    XCTAssertEqual(m.stats(0)["Double faults"], 1)
    m.undo()
    XCTAssertEqual(m.points, [0, 0])
  }
  func testSetTiebreakServingAndNextSet() {
    var m = match()
    m.useSetTiebreak = true
    m.gamesPerSet = 4
    for _ in 0..<4 {
      game(&m, 0)
      game(&m, 1)
    }
    XCTAssertNotNil(m.tiebreak)
    let first = m.server
    m.advance(0)
    XCTAssertEqual(m.server, 1 - first)
    m.advance(1)
    XCTAssertEqual(m.server, 1 - first)
    m.advance(0)
    XCTAssertEqual(m.server, first)
    for _ in 0..<5 { m.advance(0) }
    XCTAssertEqual(m.sets, [[5, 4]])
    XCTAssertEqual(m.server, 1 - first)
  }
  func testSplitSetsMatchTiebreakWinByTwo() {
    var m = match()
    m.bestOfThree = false
    m.gamesPerSet = 4
    for _ in 0..<4 { game(&m, 0) }
    for _ in 0..<4 { game(&m, 1) }
    XCTAssertEqual(m.tiebreak?.isMatch, true)
    for _ in 0..<9 {
      m.record(winner: 0, outcome: "Winner")
      m.record(winner: 1, outcome: "Winner")
    }
    m.record(winner: 0, outcome: "Winner")
    XCTAssertNil(m.winner)
    m.record(winner: 0, outcome: "Winner")
    XCTAssertEqual(m.winner, 0)
    m.undo()
    XCTAssertNil(m.winner)
    XCTAssertEqual(m.tiebreak?.points, [10, 9])
  }
  func testBestOfThreeAndCompletedGuard() {
    var m = match()
    m.gamesPerSet = 4
    m.bestOfThree = true
    for _ in 0..<4 { game(&m, 0) }
    for _ in 0..<4 { game(&m, 1) }
    XCTAssertNil(m.tiebreak)
    XCTAssertNil(m.winner)
    for _ in 0..<4 { game(&m, 1) }
    XCTAssertEqual(m.winner, 1)
    let count = m.log.count
    m.record(winner: 0, outcome: "Ace")
    XCTAssertEqual(m.log.count, count)
  }
  func testLongMatchUndoIsLosslessAndCodable() throws {
    var m = match()
    for _ in 0..<260 {
      m.record(winner: 0, outcome: "Winner")
      m.record(winner: 1, outcome: "Winner")
    }
    XCTAssertEqual(m.log.count, 520)
    let data = try JSONEncoder().encode(m)
    var decoded = try JSONDecoder().decode(TennisMatch.self, from: data)
    decoded.undo()
    XCTAssertEqual(decoded.points, [260, 259])
    XCTAssertEqual(decoded.log.count, 519)
  }
  func testTraceServiceBoxesAndLineTolerance() {
    let m = match()
    let start = CourtPoint(x: 65, y: 148)
    let legal = CourtPoint(x: 25, y: 55)
    if case .point(0, "Ace") = TraceRules.analyze(
      match: m, path: [start, legal], landings: [legal])
    {
    } else {
      XCTFail("Legal ace")
    }
    let wrong = CourtPoint(x: 75, y: 55)
    if case .fault = TraceRules.analyze(match: m, path: [start, wrong], landings: [wrong]) {
    } else {
      XCTFail("Wrong box")
    }
    XCTAssertTrue(TraceRules.inCourt(.init(x: 11, y: 8)))
    XCTAssertFalse(TraceRules.inCourt(.init(x: 9, y: 8)))
    let out = CourtPoint(x: 95, y: 140)
    if case .point(0, "Return error") = TraceRules.analyze(
      match: m, path: [start, legal, out], landings: [legal, out])
    {
    } else {
      XCTFail("Return error")
    }
  }
  func testContactProbabilitiesAndBoundaries() {
    XCTAssertEqual(
      PracticeEngine.contactChance(.easy, settled: 0.2, gap: 0.5, speed: 1, risky: false), 1)
    XCTAssertEqual(
      PracticeEngine.contactChance(.tough, settled: 0.2, gap: 0.5, speed: 1, risky: false), 0.8)
    XCTAssertEqual(
      PracticeEngine.contactChance(.easy, settled: 1, gap: 1.36, speed: 0, risky: false), 0)
    XCTAssertLessThan(
      PracticeEngine.contactChance(.easy, settled: 0, gap: 1, speed: 4, risky: true), 0.7)
    XCTAssertEqual(PracticeEngine.own(0, .init(x: 100, y: 0)).y, 12.585)
    XCTAssertEqual(PracticeEngine.aim(0, .init(x: 100, y: 100)), Vec(x: 8.08, y: 11.385))
  }
  func testPracticeFinishesAndCannotAwardTwice() {
    var e = PracticeEngine(settings: .init(scoring: .tiebreak))
    for _ in 0..<7 {
      e.startRally()
      e.end(0, reason: "", tip: "")
    }
    XCTAssertEqual(e.phase, .finished)
    e.end(0, reason: "", tip: "")
    e.startRally()
    e.step(1)
    XCTAssertEqual(e.scoring.points, [7, 0])
  }
  func testMovementAndAllStylesStayFinite() {
    for style in BotStyle.allCases {
      var e = PracticeEngine(settings: PracticeSettings(style: style))
      e.startRally()
      for _ in 0..<1200 {
        if e.phase == .point { e.startRally() }
        if e.phase == .live { e.players[0].destination = PracticeEngine.own(0, e.intercept(0)) }
        let speedLimit = max(e.players[0].velocity.length, e.showsGoldenContact(0) ? 9 : 6)
        e.step(1 / 120, random: { 0.3 })
        XCTAssertTrue(e.ball.x.isFinite && e.ball.y.isFinite)
        XCTAssertLessThanOrEqual(e.players[0].velocity.length, speedLimit + 0.0001)
        XCTAssertLessThanOrEqual(e.players[0].velocity.length, 9.0001)
      }
      XCTAssertGreaterThan(e.contactSerial, 1)
    }
  }
  func testSurfacePaceAndBounce() {
    var grass = PracticeEngine(settings: PracticeSettings(surface: .grass))
    var clay = PracticeEngine(settings: PracticeSettings(surface: .clay))
    grass.startRally()
    clay.startRally()
    XCTAssertLessThan(grass.flight!.duration, clay.flight!.duration)
    XCTAssertLessThan(CourtSurface.grass.bounce, CourtSurface.clay.bounce)
  }
}
