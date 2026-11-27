import XCTest
import simd
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

  func testOneTapTakesOverTheIncomingBallAndAssistedRallyIsAFasterWinner() throws {
    var game = PracticeEngine(settings: .init())
    game.phase = .live
    game.inventory.held = .rally
    game.launch(1, aim: Vec(x: 1, y: 23), kind: .cross)
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
      XCTAssertTrue(game.canUsePower)
      game.players[0].pos = Vec(x: 2, y: outgoing ? 22 : PracticeEngine.net + 2)
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

  func testPoweredReplayCapturesEveryFinishOnTheStrings() throws {
    for (power, leftBall) in [(CourtPower.ace,false),(.overhead,false),(.rally,false),(.rally,true)] {
      var game = PracticeEngine(settings: .init())
      game.inventory.held = power
      game.scoring = PracticeScore(format: .tennis, firstServer: 0)
      var performance = CourtPerformance(game: game)
      if power == .ace {
        game.start()
      } else {
        game.phase = .live
        game.players[0].pos = Vec(x: 4, y: 21)
        game.players[0].destination = game.players[0].pos
        game.launch(1, aim: Vec(x: leftBall ? 1.5 : 4.5, y: 21), kind: .cross)
      }
      game.usePower()
      game.usePower()
      for _ in 0..<2400 {
        game.step(PointReplay.tick, random: { 0.5 })
        performance.update(game: game, dt: PointReplay.tick)
        if game.showsPointResult { break }
      }
      XCTAssertEqual(game.scoring.points[0], 1)
      let clip = performance.replay
      let winner = try XCTUnwrap(clip.strikes.last)
      XCTAssertEqual(winner.power, power)
      XCTAssertEqual(clip.strikes.filter { $0.power != nil }.count, 1)
      XCTAssertEqual(clip.opening, max(0, winner.time - (power == .ace ? 1.05 : 0.85)), accuracy: 0.00001)
      let frame = try XCTUnwrap(clip.frame(at: winner.time))
      XCTAssertLessThan(simd_distance(frame.near[.strings], frame.ball), 0.001)
      if power == .rally {
        XCTAssertEqual(game.flight?.powerBackhand, leftBall)
        let hands = simd_distance(frame.near[.grip], frame.near[.leftHand])
        if leftBall { XCTAssertEqual(hands, 0.095, accuracy: 0.002) }
        else { XCTAssertGreaterThan(hands, 0.25) }
      } else {
        XCTAssertGreaterThan(frame.ball.y, 2.45)
        XCTAssertGreaterThan(frame.near[.leftShoe].y, 0.25)
      }
    }
  }

  func testArmedAceWaitsForOwnServeAcrossPointBoundary() {
    var game = PracticeEngine(settings: .init())
    game.phase = .live
    game.scoring = PracticeScore(format: .tennis, firstServer: 0)
    game.inventory.held = .ace
    game.launch(1, aim: Vec(x: 2, y: 20), kind: .cross)
    game.usePower()
    XCTAssertEqual(game.inventory.armed, true)
    XCTAssertNil(game.queuedPower)
    finish(1, in: &game)
    game.start()
    nextFrames(&game) { $0.flight?.power == .ace }
    XCTAssertNil(game.inventory.held)
  }

  func testServiceBoxSavesAndMissesUseTheAirbornePathOnBothSides() throws {
    for side in 0...1 {
      for (offset,loft,stroke,touch) in [(1.43,0.74,NetStroke.dive,true),(-1.43,0.74,.dive,true),
                                         (0.18,1.85,.jump,true),(1.85,0.74,.dive,false)] {
        func depth(_ z: Double) -> Double { side == 0 ? z : PracticeEngine.length-z }
        var game = PracticeEngine(settings: .init(local: true))
        game.phase = .live
        let feet = Vec(x: 4, y: depth(15))
        game.players[side].pos = feet
        game.players[side].destination = feet
        let flight = BallFlight(from: Vec(x: 4+offset,y: depth(1)), landing: Vec(x: 4+offset,y: depth(22)),
          contact: Vec(x: 4+offset,y: depth(23.1)), duration: 2, hitter: 1-side, explanation: "",loft: loft)
        game.flight = flight
        var motion = CourtPerformance(game:game)
        var attempted: NetEffort?
        for _ in 0..<300 {
          game.step(PointReplay.tick, random:{0.6})
          motion.update(game: game,dt: PointReplay.tick)
          if let effort = game.players[side].netEffort { attempted = effort }
          if game.contactSerial > 0 || game.phase != .live { break }
        }
        let effort = try XCTUnwrap(attempted)
        XCTAssertEqual(effort.stroke, stroke)
        XCTAssertEqual(effort.reachable, touch)
        if touch {
          XCTAssertEqual(game.bounceSerial, 0)
          XCTAssertEqual(game.flight?.stroke, stroke == .dive ? .lob : stroke.overhead ? .overhead : .volley)
          let hit = try XCTUnwrap(motion.replay.strikes.last)
          let frame = try XCTUnwrap(motion.replay.frame(at: hit.time))
          let body = side == 0 ? frame.near : frame.far
          XCTAssertLessThan(simd_distance(frame.ball,body[.strings]),0.001)
          if stroke == .jump { XCTAssertGreaterThan(body[.leftShoe].y,0.27) }
          else { XCTAssertLessThan(body[.head].y,1.20) }
        } else {
          XCTAssertEqual(game.contactSerial,0)
          XCTAssertEqual(game.phase,.point)
        }
        var serve = flight
        serve.serve = true
        XCTAssertNil(BallContactWindow.netOpportunity(flight:serve, player:feet, side:side, after:0))
        XCTAssertNil(BallContactWindow.netOpportunity(flight:flight, player:feet, side:side, after:0.8))
      }
    }
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
