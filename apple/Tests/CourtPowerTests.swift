import XCTest
@testable import TennisCore

final class CourtPowerTests: XCTestCase {
  private func nextFrames(_ game: inout PracticeEngine, until done: (PracticeEngine) -> Bool) {
    for _ in 0..<2400 {
      if done(game) { return }
      game.step(1 / 120, random: { 0.5 })
    }
    XCTFail("Timed out waiting for gameplay transition")
  }

  private func finish(_ winner: Int, in game: inout PracticeEngine, roll: Double = 0) {
    game.phase = .live
    game.end(winner, reason: "", tip: "", random: { roll })
  }

  func testEveryPairAwardsOneRandomPowerAndAnOccupiedSlotSurvivesWinsAndLosses() {
    for (index, expected) in CourtPower.allCases.enumerated() {
      var game = PracticeEngine(settings: .init())
      let draw = (Double(index) + 0.5) / 3
      finish(0, in: &game)
      XCTAssertNil(game.inventory.held)
      finish(1, in: &game)
      finish(0, in: &game)
      XCTAssertNil(game.inventory.held)
      finish(0, in: &game, roll: draw)
      XCTAssertEqual(game.inventory.held, expected)
      finish(0, in: &game)
      finish(0, in: &game)
      finish(1, in: &game)
      XCTAssertEqual(game.inventory.held, expected)
      game.start()
      XCTAssertEqual(game.inventory.held, expected)
      var local = PracticeEngine(settings: .init(local: true))
      finish(0, in: &local)
      finish(0, in: &local)
      XCTAssertNil(local.inventory.held)
    }
  }

  func testGreenTapArmsTheCurrentBallAndAssistedRallyIsAFasterWinner() throws {
    var game = PracticeEngine(settings: .init())
    game.phase = .live
    game.inventory.held = .rally
    game.launch(1, aim: Vec(x: 1, y: 23), kind: .cross)
    game.usePower()
    XCTAssertNil(game.queuedPower)
    let target = try XCTUnwrap(game.contactGuide(0))
    game.tapCourt(0, at: target)
    XCTAssertTrue(game.canUsePower)
    game.usePower()
    XCTAssertNotNil(game.assist)
    XCTAssertFalse(game.canUsePower)
    let initial = game.players[0].pos
    nextFrames(&game) { $0.flight?.power == .rally }
    let winner = try XCTUnwrap(game.flight)
    XCTAssertGreaterThan(game.players[0].pos.distance(to: initial), 0.2)
    XCTAssertEqual(winner.power?.contactGain, 1.5)
    var plain = game
    plain.launch(0, aim: winner.landing, kind: .cross)
    XCTAssertEqual(winner.duration * 1.5, plain.flight!.duration, accuracy: 0.00001)
    XCTAssertNil(game.inventory.held)
    let contacts = game.contactSerial
    nextFrames(&game) { $0.phase == .point }
    XCTAssertEqual(game.contactSerial, contacts)
    XCTAssertEqual(game.momentum.winsInRow, 1)
    XCTAssertTrue(game.feedback.reason.contains("Rally Smash"))
  }

  func testOverheadCanBeCalledDuringApproachOrIncomingFeedAndClearsOpponent() throws {
    for outgoing in [false, true] {
      var game = PracticeEngine(settings: .init())
      game.phase = .live
      game.inventory.held = .overhead
      game.launch(outgoing ? 0 : 1, aim: Vec(x: 4, y: outgoing ? 1 : 20), kind: .lob)
      XCTAssertFalse(game.canUsePower)
      game.players[0].pos = Vec(x: 2, y: PracticeEngine.net + 2)
      game.players[0].destination = game.players[0].pos
      if outgoing { game.flight!.opponentError = .unreachable }
      game.usePower()
      nextFrames(&game) { $0.flight?.power == .overhead }
      let shot = try XCTUnwrap(game.flight)
      XCTAssertEqual(shot.stroke, .overhead)
      XCTAssertEqual(shot.power?.contactGain, 2)
      XCTAssertEqual(shot.landing, Vec(x: PracticeEngine.width / 2, y: PracticeEngine.net / 2))
      XCTAssertLessThan(shot.contact.y, game.players[1].pos.y)
      nextFrames(&game) { $0.phase == .point }
      XCTAssertGreaterThan(game.flight!.height, 2.5)
      XCTAssertEqual(game.momentum.winsInRow, 1)
    }
  }

  func testAceLocksSelectedTargetAndCelebratesOnceInFourUses() throws {
    var reactions: [Bool] = []
    var game = PracticeEngine(settings: .init())
    game.scoring = PracticeScore(format: .tennis, firstServer: 0)
    for index in 0..<4 {
      game.phase = .ready
      game.start()
      game.inventory.held = .ace
      game.usePower()
      XCTAssertNil(game.queuedPower)
      game.chooseServe(index.isMultiple(of: 2) ? .wide : .center, side: 0)
      let selection = try XCTUnwrap(game.servePreparation?.destination)
      game.usePower()
      game.aimServe(at: .zero, side: 0)
      nextFrames(&game) { $0.flight?.power == .ace }
      let shot = try XCTUnwrap(game.flight)
      XCTAssertEqual(shot.landing.distance(to: selection), 0, accuracy: 0.002)
      XCTAssertTrue(shot.serve)
      XCTAssertNil(shot.fault)
      var plain = game
      plain.launch(0, aim: shot.landing, kind: .cross, serve: true)
      XCTAssertEqual(shot.duration * 1.5, plain.flight!.duration, accuracy: 0.00001)
      var rebound = shot
      rebound.elapsed = shot.duration * 0.92
      plain.flight!.elapsed = plain.flight!.duration * 0.92
      XCTAssertEqual(rebound.height, plain.flight!.height * 1.25, accuracy: 0.00001)
      reactions.append(shot.acknowledge)
      nextFrames(&game) { $0.phase == .point }
      XCTAssertTrue(game.feedback.reason.contains("Ace"))
    }
    XCTAssertEqual(reactions.filter { $0 }.count, 1)
  }

  func testHeldPowerAndCelebrationOrderRoundTripBetweenMatches() throws {
    let inventory = PowerInventory(held: .ace, aceCelebrations: [false, true])
    var nextMatch = PracticeEngine(settings: .init())
    nextMatch.inventory = try JSONDecoder().decode(PowerInventory.self, from: JSONEncoder().encode(inventory))
    nextMatch.start()
    XCTAssertEqual(nextMatch.inventory, inventory)
  }

  func testSplitWindowMeasuresThreeMetersBeforeAndAfterTheBounce() {
    var game = PracticeEngine(settings: .init())
    game.phase = .live
    game.flight = BallFlight(from: Vec(x: 4, y: 22), landing: Vec(x: 4, y: 6),
      contact: Vec(x: 4, y: 1), duration: 1, hitter: 0, explanation: "", loft: 1)
    for (fraction, expected) in [(0.649, false), (0.651, true), (0.8, true), (0.919, true), (0.921, false)] {
      game.flight!.elapsed = fraction
      XCTAssertEqual(game.inSplitWindow(0), expected)
      XCTAssertFalse(game.inSplitWindow(1))
    }
  }

  func testApproachPlantsAtCurrentPositionWhenBallBounces() {
    var game = PracticeEngine(settings: .init())
    game.phase = .live
    game.launch(0, aim: Vec(x: 2, y: 2), kind: .cross)
    game.flight!.elapsed = game.flight!.duration * 0.7
    game.followShot(0)
    let destination = game.players[0].destination
    nextFrames(&game) { $0.bounceSerial > 0 }
    let feet = game.players[0].pos
    XCTAssertGreaterThan(feet.distance(to: destination), 1)
    XCTAssertEqual(game.players[0].destination, feet)
    XCTAssertEqual(game.players[0].velocity, .zero)
    XCTAssertTrue(game.splitTimed[0])
    XCTAssertFalse(game.followingApproach[0])
    for _ in 0..<8 { game.step(1 / 120) }
    XCTAssertEqual(game.players[0].pos, feet)
  }
}
