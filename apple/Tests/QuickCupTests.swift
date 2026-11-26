import XCTest
@testable import TennisCore

final class QuickCupTests: XCTestCase {
  func testSTRankingStartsTentativeAndDisplaysFractionalProgress() throws {
    XCTAssertEqual(STRating().label, "ST 4t")
    let rating = try JSONDecoder().decode(STRating.self, from: Data(#"{"points":4.4,"humanMatches":3,"wins":1,"tentative":false}"#.utf8))
    XCTAssertEqual(rating.label, "ST 4.4")
    XCTAssertEqual(rating.humanMatches - rating.wins, 2)
  }
  func testThirdHumanMatchEstablishesRatingIncludingOldCachedProfiles() throws {
    for count in 0...4 {
      let cached = Data("{\"points\":4,\"humanMatches\":\(count),\"wins\":0,\"tentative\":true}".utf8)
      let rating = try JSONDecoder().decode(STRating.self, from: cached)
      XCTAssertEqual(rating.tentative, count < 3)
      XCTAssertEqual(rating.label, count < 3 ? "ST 4t" : "ST 4")
    }
    let third = try JSONDecoder().decode(STRatingChange.self, from: Data(#"{"userID":"me","before":4.1,"after":4.2,"humanMatches":3,"beforeTentative":true,"tentative":false}"#.utf8))
    XCTAssertEqual(third.summary,"ST 4.1t → ST 4.2")
    let fourth = STRatingChange(userID:"me",before:4.2,after:4.3,humanMatches:4,tentative:false,beforeTentative:false)
    XCTAssertEqual(fourth.summary,"ST 4.2 → ST 4.3")
  }
  func testHumanCupGuideAppearsAfterContactForBothPlayersAndTracksIncomingPath() throws {
    for server in 0...1 {
      var settings = PracticeSettings(local: true)
      settings.tournament = true
      var game = PracticeEngine(settings: settings)
      game.scoring = PracticeScore(format: .tiebreak, firstServer: server)
      game.start()
      XCTAssertNil(game.serveReceiveTarget(1 - server))
      XCTAssertNil(game.contactGuide(1 - server))
      game.phase = .live
      game.launch(server, aim: Vec(x: 1, y: server == 0 ? 2 : 22), kind: .cross)
      let first = try XCTUnwrap(game.contactGuide(1 - server))
      XCTAssertEqual(first, game.intercept(1 - server))
      XCTAssertNil(game.contactGuide(server))
      game.launch(server, aim: Vec(x: 7, y: server == 0 ? 2 : 22), kind: .cross)
      let changed = try XCTUnwrap(game.contactGuide(1 - server))
      XCTAssertNotEqual(first.x, changed.x)
      CupInput(kind: "receive", movementEpoch: game.contactSerial).apply(to: &game, side: 1 - server)
      XCTAssertEqual(game.players[1 - server].destination, changed)
    }
  }
  func testShortSwipeCommandRoundTripsAndMovesOnlyTheAssignedHuman() throws {
    for side in 0...1 {
      var game = PracticeEngine(settings: .init(local: true))
      game.phase = .live
      game.launch(1 - side, aim: Vec(x: 1, y: side == 0 ? 22 : 2), kind: .cross)
      let target = try XCTUnwrap(game.contactGuide(side))
      let opponent = game.players[1 - side].destination
      let input = CupInput(.guidedMove(.receive), shotEpoch: game.shotGestureEpoch(side), movementEpoch: game.contactSerial)
      let received = try JSONDecoder().decode(CupInput.self, from: JSONEncoder().encode(input))
      received.apply(to: &game, side: side)
      XCTAssertEqual(game.players[side].destination, target)
      XCTAssertEqual(game.players[1 - side].destination, opponent)
      XCTAssertEqual(game.tactics[side].splitSteps, 0)
    }
  }
  func testInviteLinksAcceptOnlyOurHostAndUnambiguousCodes() {
    XCTAssertEqual(QuickCup.inviteCode(from: " abcdefgh "), "ABCDEFGH")
    XCTAssertEqual(QuickCup.inviteCode(from: "https://swipetennis.com/cup/ABCDEFGH"), "ABCDEFGH")
    XCTAssertEqual(QuickCup.inviteCode(from: "swipetennis://cup/ABCDEFGH"), "ABCDEFGH")
    for bad in ["https://evil.example/cup/ABCDEFGH", "https://swipetennis.com/other/ABCDEFGH", "ABCI1234", "abc", "https://swipetennis.com/cup/ABCDEFGH/extra"] {
      XCTAssertNil(QuickCup.inviteCode(from: bad))
    }
  }
  func testPerspectiveIsReversibleAndFarPlayerSwipesRemainPlayerRelative() {
    let original = Vec(x: 1.2, y: 21.4)
    let opposite = CupPerspective.court(original, side: 1)
    XCTAssertEqual(CupPerspective.court(opposite, side: 1).x, original.x, accuracy: 0.000001)
    XCTAssertEqual(CupPerspective.court(opposite, side: 1).y, original.y, accuracy: 0.000001)
    var gesture = PracticeGesture(side: 1, intent: .shot)
    _ = gesture.update(at: original, screenPoint: CupPerspective.screen(.zero, side: 1))
    let action = gesture.update(at: original, screenPoint: CupPerspective.screen(Vec(x: 0, y: -50), side: 1), ended: true)
    XCTAssertEqual(action, .shotSwipe(Vec(x: 0, y: -50)))
  }
  func testCupCommandsCannotControlBotsOrApplyNonfiniteCoordinates() {
    var engine = PracticeEngine(settings: .init())
    let before = engine.players[1].destination
    CupInput(kind: "move", point: Vec(x: 1, y: 1)).apply(to: &engine, side: 1)
    XCTAssertEqual(engine.players[1].destination, before)
    let human = engine.players[0].destination
    CupInput(kind: "move", point: Vec(x: .infinity, y: 1)).apply(to: &engine, side: 0)
    XCTAssertEqual(engine.players[0].destination, human)
  }
  func testCupUsesFixedLevelAndStandardTiebreakWithoutPowers() throws {
    let cup = try fixture()
    var engine = cup.engine(for: cup.matches[0])
    XCTAssertEqual(engine.settings.difficulty, .medium)
    XCTAssertTrue(engine.settings.tournament)
    XCTAssertFalse(engine.settings.local)
    XCTAssertFalse(engine.settings.allCourtTraining)
    XCTAssertEqual(engine.settings.style, .retriever)
    XCTAssertEqual(engine.scoring.format, .tiebreak)
    engine.start()
    engine.inventory.held = .ace
    XCTAssertFalse(engine.canUsePower)
    engine.usePower()
    XCTAssertNil(engine.queuedPower)
    let encoded = try JSONEncoder().encode(engine)
    XCTAssertTrue(try JSONDecoder().decode(PracticeEngine.self, from: encoded).settings.tournament)
  }
  func testOldPracticeSettingsStillDecodeWithoutTournamentFlag() throws {
    let data = Data(#"{"local":false,"difficulty":"Easy"}"#.utf8)
    XCTAssertFalse(try JSONDecoder().decode(PracticeSettings.self, from: data).tournament)
  }
  func testNextMatchBelongsToTheSignedInPlayer() throws {
    let cup = try fixture()
    XCTAssertEqual(cup.nextMatch(for: "me")?.id, "semi-1")
    XCTAssertNil(cup.nextMatch(for: "someone-else"))
  }
  func testNetworkCheckpointBoundsHistoryAndPreservesPointNumberAfterReconnect() {
    var coach = Coachability()
    for i in 0..<30 { coach.finishPoint(award: .point, winner: i % 2, format: .tiebreak, time: Double(i)) }
    var checkpoint = coach.cupSnapshot
    XCTAssertEqual(checkpoint.records.count, 1)
    XCTAssertEqual(checkpoint.records.last?.pointIndex, 30)
    checkpoint.finishPoint(award: .point, winner: 0, format: .tiebreak, time: 31)
    XCTAssertEqual(checkpoint.records.last?.pointIndex, 31)
    XCTAssertEqual(coach.records.count, 30)
  }
  private func fixture() throws -> QuickCup {
    try JSONDecoder().decode(QuickCup.self, from: Data(#"{"code":"ABCDEFGH","title":"Club Cup","hostID":"me","status":"playing","level":"medium","surface":"hard","createdAt":100,"expiresAt":86400100,"version":2,"participants":[{"id":"me","name":"Me","kind":"human","ready":true},{"id":"bot","name":"Alex · AI","kind":"bot","ready":true,"level":"medium","style":"retriever"}],"matches":[{"id":"semi-1","playerIDs":["me","bot"],"authorityID":"me","status":"waiting","score":[0,0]}]}"#.utf8))
  }
}
