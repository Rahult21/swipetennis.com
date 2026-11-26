import XCTest
@testable import TennisCore

@MainActor final class SoloCareerTests: XCTestCase {
  private func directory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    addTeardownBlock { try FileManager.default.removeItem(at: url) }
    return url
  }

  func testCareerAndQuickPlayResumeIndependentFlightsAcrossRelaunch() async throws {
    let dir = try directory()
    let careerURL = dir.appendingPathComponent("career"), quickURL = dir.appendingPathComponent("quick")
    let store = SoloCareerStore(file: careerURL), quick = PracticeMatchSlot(file: quickURL)
    var game = try XCTUnwrap(store.enter(owner: "A")?.engine)
    XCTAssertEqual(game.scoring.points,[0,0])
    XCTAssertEqual(game.settings.opponentName,"Morgan")
    game.start()
    game.phase = .live
    game.launch(1, aim: Vec(x: 2.4, y: 21), kind: .cross)
    for _ in 0..<10 { game.step(1/120,random:{0.5}) }
    try store.checkpoint(game, owner: "A")
    var other = PracticeEngine(settings: .init(scoring: .tiebreak))
    other.start()
    try quick.save(other, owner: "A")
    try quick.save(game,owner:"A")
    try store.checkpoint(other,owner:"A")
    XCTAssertEqual(PracticeMatchSlot(file:quickURL).saved?.id,other.coach.sessionID)
    let relaunched = SoloCareerStore(file:careerURL)
    let resumed = try XCTUnwrap(relaunched.enter(owner:"A")?.engine)
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    XCTAssertEqual(try encoder.encode(game),try encoder.encode(resumed))
    XCTAssertFalse(relaunched.progress(for:"B").started)
    try quick.discard(other.coach.sessionID,owner:"A")
    XCTAssertEqual(SoloCareerStore(file:careerURL).progress(for:"A").active?.coach.sessionID,game.coach.sessionID)
  }

  func testAllThreeRivalsRecurAndOnlySelectionWinsAdvance() async throws {
    let url = try directory().appendingPathComponent("career")
    for encounter in ClubEncounter.allCases {
      let outcomes = encounter.isTrial ? [false,true] : [false]
      for win in outcomes {
        let store = SoloCareerStore(file:url)
        var game = try XCTUnwrap(store.enter(owner:"A")?.engine)
        XCTAssertEqual(game.settings.clubEncounter,encounter)
        XCTAssertEqual(game.settings.style,encounter.rival.style)
        XCTAssertEqual(game.settings.opponentName,encounter.rival.rawValue)
        XCTAssertEqual(game.scoring.points, [0,0])
        let before = store.progress(for:"A").results.count
        while game.scoring.winner == nil {
          game.start()
          game.phase = .live
          game.end(win ? 0 : 1,reason:"Winner",tip:"",random:{0.5})
        }
        XCTAssertEqual(game.phase,.finished)
        XCTAssertEqual(game.scoring.points, win ? [10,0] : [0,10])
        XCTAssertEqual(game.scoring.lastAward,.tiebreak)
        XCTAssertNil(game.inventory.held)
        try store.checkpoint(game,owner:"A")
        try store.checkpoint(game,owner:"A")
        let next = store.progress(for:"A")
        XCTAssertEqual(next.results.count,before+1)
        XCTAssertNil(next.active)
        XCTAssertEqual(next.results.last?.won,win)
        XCTAssertEqual(next.results.last?.coachPoints,game.coach.records.reduce(0){$0+$1.points})
        if !win && encounter.isTrial { XCTAssertEqual(next.next,encounter) }
      }
    }
    let completed = SoloCareerStore(file:url)
    XCTAssertNil(try completed.enter(owner:"A"))
    XCTAssertEqual(completed.progress(for:"A").results.filter(\.advanced).count,6)
    for rival in TourRival.allCases { XCTAssertEqual(completed.progress(for:"A").meetings(with:rival).count,3) }
  }

  func testBuild11CareerConvertsPlayedPointsAndFinishesTheCurrentServe() async throws {
    let url = try directory().appendingPathComponent("career")
    var old = ClubEncounter.returnGame.makeGame()
    old.settings.scoring = .tennis
    old.scoring = PracticeScore(format: .tennis, firstServer: 1, oneGame: true)
    for side in [0,1,1] { old.scoring.award(side) }
    old.start()
    old.phase = .live
    old.end(0, reason: "Winner", tip: "")
    old.start()
    let server = old.scoring.server, right = old.scoring.serveFromRight
    let debut = ClubResult(id: UUID(), encounter: .debut, won: false, coachPoints: 3, review: nil)
    let career = SoloCareer(results: [debut], active: old)
    try JSONEncoder().encode(["A": career]).write(to: url)
    let store = SoloCareerStore(file: url)
    var game = try XCTUnwrap(store.enter(owner: "A")?.engine)
    XCTAssertEqual(game.scoring.points, [1,0])
    XCTAssertEqual(game.settings.scoring, .tiebreak)
    XCTAssertEqual(game.coach.sessionID, old.coach.sessionID)
    XCTAssertEqual(game.scoring.server, server)
    XCTAssertEqual(game.scoring.serveFromRight, right)
    game.phase = .live
    game.end(1, reason: "Winner", tip: "")
    XCTAssertEqual(game.scoring.points,[1,1])
    XCTAssertEqual(game.scoring.server, 0)
    XCTAssertTrue(game.scoring.serveFromRight)
    try store.checkpoint(game, owner: "A")
    let saved = SoloCareerStore(file: url).progress(for: "A")
    XCTAssertEqual(saved.results.first?.id, debut.id)
    XCTAssertEqual(saved.active?.scoring.points, [1,1])
  }

  func testDebutRequiresTwoClearPointsAndOffersGuestContinuity() async throws {
    let url = try directory().appendingPathComponent("career")
    let store = SoloCareerStore(file:url)
    let game = try XCTUnwrap(store.enter(owner:DemoProgressArchive.guest)?.engine)
    var score = game.scoring
    for _ in 0..<9 { score.award(0); score.award(1) }
    XCTAssertEqual(score.points, [9,9])
    score.award(1)
    XCTAssertNil(score.winner)
    score.award(0)
    score.award(1)
    XCTAssertNil(score.winner)
    score.award(1)
    XCTAssertEqual(score.points, [10,12])
    XCTAssertEqual(score.winner,1)
    XCTAssertTrue(game.settings.tournament)
    XCTAssertFalse(game.settings.allCourtTraining)
    try store.claimGuest(for:"A")
    XCTAssertEqual(store.progress(for:"A").active?.coach.sessionID,game.coach.sessionID)
    XCTAssertFalse(store.progress(for:DemoProgressArchive.guest).started)
    var inFlight = game
    inFlight.start()
    try store.checkpoint(inFlight, owner: DemoProgressArchive.guest)
    XCTAssertEqual(store.progress(for:"A").active?.phase, inFlight.phase)
    let guest = try XCTUnwrap(store.enter(owner:DemoProgressArchive.guest))
    try store.claimGuest(for:"A")
    let restored = SoloCareerStore(file:url)
    XCTAssertEqual(restored.progress(for:DemoProgressArchive.guest).active?.coach.sessionID,guest.id)
    XCTAssertEqual(restored.progress(for:"A").active?.coach.sessionID,game.coach.sessionID)
  }
}
