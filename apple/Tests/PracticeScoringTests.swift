import XCTest

@testable import TennisCore

final class PracticeScoringTests: XCTestCase {
  private func game(_ score: inout PracticeScore, _ winner: Int) {
    for _ in 0..<4 { score.award(winner) }
  }

  func testDefaultNamesAndCustomNamesAcrossOpponentStylesAndLocalPlay() {
    for local in [false, true] {
      for style in BotStyle.allCases {
        var settings = PracticeSettings(local: local, style: style)
        XCTAssertEqual(settings.name(0), "You")
        XCTAssertEqual(settings.name(1), "Opponent")
        settings.playerName = "  Rahul  "
        settings.opponentName = "  Alex\n"
        let engine = PracticeEngine(settings: settings)
        XCTAssertEqual(engine.name(0), "Rahul")
        XCTAssertEqual(engine.name(1), "Alex")
        settings.playerName = " \n "
        XCTAssertEqual(settings.name(0), "You")
      }
    }
  }

  func testOldPracticeSettingsDefaultToTennisAndNewChoicesRoundTrip() throws {
    let old = Data(#"{"local":false,"difficulty":"Easy","style":"Baseline","surface":"Grass"}"#.utf8)
    let decoded = try JSONDecoder().decode(PracticeSettings.self, from: old)
    XCTAssertEqual(decoded.scoring, .tennis)
    XCTAssertEqual(decoded.name(0), "You")
    XCTAssertEqual(decoded.name(1), "Opponent")
    let custom = PracticeSettings(scoring: .tiebreak, playerName: "Alex", opponentName: "Sam")
    let roundTrip = try JSONDecoder().decode(PracticeSettings.self, from: JSONEncoder().encode(custom))
    XCTAssertEqual(roundTrip.scoring, .tiebreak)
    XCTAssertEqual(roundTrip.name(0), "Alex")
    XCTAssertEqual(roundTrip.name(1), "Sam")
  }

  func testTennisPointsDeuceAdvantageAndGame() {
    var score = PracticeScore(format: .tennis)
    XCTAssertEqual(score.pointLabel(0), "0")
    for expected in ["15", "30", "40"] {
      score.award(0)
      XCTAssertEqual(score.pointLabel(0), expected)
    }
    for _ in 0..<3 { score.award(1) }
    XCTAssertTrue(score.deuce)
    score.award(0)
    XCTAssertEqual(score.advantage, 0)
    XCTAssertEqual(score.pointLabel(0), "AD")
    XCTAssertEqual(score.pointLabel(1), "40")
    score.award(1)
    XCTAssertTrue(score.deuce)
    score.award(1)
    score.award(1)
    XCTAssertEqual(score.lastAward, .game)
    XCTAssertEqual(score.games, [0, 1])
    XCTAssertEqual(score.points, [0, 0])
    XCTAssertEqual(score.server, 0)
    XCTAssertNil(score.winner)
  }

  func testSixAllContinuesInGamesUntilTwoGameLead() {
    var score = PracticeScore(format: .tennis)
    for _ in 0..<6 { game(&score, 0); game(&score, 1) }
    XCTAssertEqual(score.games, [6, 6])
    XCTAssertEqual(score.pointLabel(0), "0")
    XCTAssertNil(score.winner)
    game(&score, 0)
    XCTAssertNil(score.winner)
    game(&score, 0)
    XCTAssertEqual(score.games, [8, 6])
    XCTAssertEqual(score.winner, 0)
    XCTAssertEqual(score.lastAward, .set)
    score.award(1)
    XCTAssertEqual(score.games, [8, 6])
    XCTAssertEqual(score.points, [0, 0])
  }

  func testTennisServerStaysForGameAndAlternatesServiceCourts() {
    var engine = PracticeEngine(settings: .init())
    for point in 0..<4 {
      engine.startRally()
      XCTAssertEqual(engine.flight?.hitter, 1)
      XCTAssertEqual(engine.scoring.server, 1)
      XCTAssertEqual(engine.flight!.from.x < PracticeEngine.width / 2, point.isMultiple(of: 2))
      XCTAssertEqual(engine.flight!.landing.x > PracticeEngine.width / 2, point.isMultiple(of: 2))
      engine.end(0, reason: "Opponent missed.", tip: "")
    }
    engine.startRally()
    XCTAssertEqual(engine.flight?.hitter, 0)
    XCTAssertGreaterThan(engine.flight!.from.x, PracticeEngine.width / 2)
    XCTAssertLessThan(engine.flight!.landing.x, PracticeEngine.width / 2)
  }

  func testOptionalTiebreakServiceOrderAndWinByTwo() {
    var score = PracticeScore(format: .tiebreak)
    var servers: [Int] = []
    for point in 0..<12 {
      servers.append(score.server)
      score.award(point % 2)
    }
    XCTAssertEqual(Array(servers.prefix(7)), [1, 0, 0, 1, 1, 0, 0])
    XCTAssertEqual(score.points, [6, 6])
    score.award(0)
    XCTAssertNil(score.winner)
    score.award(0)
    XCTAssertEqual(score.winner, 0)
    XCTAssertEqual(score.points, [8, 6])
    XCTAssertEqual(score.games, [0, 0])
    XCTAssertEqual(score.lastAward, .tiebreak)
  }

  func testResultsNamePointGameAndSetWinnerAndCannotAwardTwice() {
    var engine = PracticeEngine(settings: .init())
    engine.startRally()
    engine.end(0, reason: "Opponent's shot landed long.", tip: "Move early.")
    XCTAssertEqual(engine.feedback.title, "You won the point.")
    XCTAssertTrue(engine.feedback.reason.hasPrefix("Opponent's shot landed long."))
    XCTAssertTrue(engine.feedback.reason.contains("served deep"))
    engine.end(1, reason: "Duplicate", tip: "")
    XCTAssertEqual(engine.scoring.points, [1, 0])
    for _ in 1..<24 {
      engine.startRally()
      engine.end(0, reason: "Opponent didn't reach the ball in time.", tip: "")
      if engine.scoring.games == [1, 0] && engine.scoring.points == [0, 0] {
        XCTAssertEqual(engine.feedback.title, "You won the game.")
        XCTAssertEqual(engine.phase, .point)
      }
    }
    XCTAssertEqual(engine.phase, .finished)
    XCTAssertEqual(engine.feedback.title, "You won the set.")
    XCTAssertEqual(engine.scoreSummary, "Games: You 6 · Opponent 0")
    XCTAssertFalse(engine.showsPointResult)
    // Consecutive wins show the opponent's two-second reaction before the set result.
    for _ in 0..<240 { engine.step(1 / 120) }
    XCTAssertEqual(engine.instruction.title, "You won the set.")
    engine.startRally()
    XCTAssertEqual(engine.phase, .finished)
    let fresh = PracticeEngine(settings: engine.settings)
    XCTAssertEqual(fresh.scoring.games, [0, 0])
    XCTAssertNil(fresh.scoring.winner)
  }

  func testCustomOpponentResultAndTiebreakResultAreExplicit() {
    var engine = PracticeEngine(settings: .init(scoring: .tiebreak, opponentName: "Sam"))
    for _ in 0..<7 {
      engine.startRally()
      engine.end(1, reason: "You didn't reach the ball in time.", tip: "")
    }
    XCTAssertEqual(engine.feedback.title, "Sam won the tiebreak.")
    XCTAssertEqual(engine.scoreSummary, "You 0 · Sam 7 points")
    XCTAssertFalse(engine.scoreAnnouncement.contains("chance"))
  }

  func testNewManualMatchesUseGamesWithoutUnchosenTiebreaks() {
    var match = TennisMatch(players: [.init(name: "You"), .init(name: "Opponent")])
    XCTAssertTrue(match.bestOfThree)
    XCTAssertEqual(match.useSetTiebreak, false)
    for _ in 0..<6 {
      for side in 0...1 { for _ in 0..<4 { match.record(winner: side, outcome: "Winner") } }
    }
    XCTAssertEqual(match.games, [6, 6])
    XCTAssertNil(match.tiebreak)
    for _ in 0..<8 { match.record(winner: 0, outcome: "Winner") }
    XCTAssertEqual(match.sets, [[8, 6]])
    match.undo()
    XCTAssertEqual(match.games, [7, 6])
    XCTAssertEqual(match.pointLabel(0), "40")
  }

  func testLegacyManualMatchRetainsItsTiebreakRules() throws {
    let original = TennisMatch(players: [.init(name: "You"), .init(name: "Opponent")])
    var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
    json.removeValue(forKey: "useSetTiebreak")
    var legacy = try JSONDecoder().decode(TennisMatch.self, from: JSONSerialization.data(withJSONObject: json))
    XCTAssertNil(legacy.useSetTiebreak)
    legacy.games = [5, 6]
    for _ in 0..<4 { legacy.advance(0) }
    XCTAssertNotNil(legacy.tiebreak)
  }
}
