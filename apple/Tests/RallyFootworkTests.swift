import XCTest
@testable import TennisCore

final class RallyFootworkTests: XCTestCase {
  private func incoming(side: Int, bot: Bool = false) -> PracticeEngine {
    var game = PracticeEngine(settings: .init(local: !bot, surface: .hard, allCourtTraining: false))
    game.phase = .live
    let p = Vec(x: 4.2, y: side == 0 ? 23.4 : 0.37)
    game.players[side].pos = p
    game.players[side].destination = p
    game.launch(1-side, aim: Vec(x: p.x, y: p.y + (side == 0 ? -1.1 : 1.1)), kind: .cross)
    return game
  }

  func testDepthAndPaceForBothEndsOfCourt() throws {
    for side in 0...1 {
      for length in [20.0, 145.0] {
        var game = incoming(side: side)
        game.selectShotSwipe(Vec(x: 0, y: -length), side: side)
        game.players[side].settled = 0.4
        game.returnBall(side, volley: false, random: {0.99})
        let line = try XCTUnwrap(game.flight)
        XCTAssertEqual(line.contactQuality, .planted)
        XCTAssertEqual(line.kind, .line)
        let depth = side == 0 ? line.landing.y : PracticeEngine.length - line.landing.y
        XCTAssertTrue(length < 30 ? depth > 7 : depth < 1.2)
        game.launch(side, aim: line.landing, kind: .cross)
        XCTAssertEqual(line.duration, game.flight!.duration / (1.5 * 1.2), accuracy: 0.0001)
      }
      var stretched = incoming(side: side, bot: side == 1)
      stretched.players[side].velocity = Vec(x: 4.1, y: 0)
      stretched.returnBall(side, volley: false, random: {0.99})
      let block = try XCTUnwrap(stretched.flight)
      XCTAssertEqual(block.contactQuality, .stretched)
      XCTAssertTrue(PracticeEngine.isShortBall(block, receiving: 1-side))
      stretched.launch(side, aim: block.landing, kind: block.kind)
      XCTAssertEqual(block.duration, stretched.flight!.duration / 0.8, accuracy: 0.0001)
    }
  }

  func testTappingTheOpenCourtAimsTheVolleyAndCutsReactionTime() throws {
    for side in 0...1 {
      var g = incoming(side: side)
      g.players[side].pos = Vec(x: 4.3, y: side == 0 ? 15 : 8.77)
      let target = Vec(x: 7.35, y: side == 0 ? 4.5 : PracticeEngine.length - 4.5)
      g.tapCourt(side, at: target)
      g.ball = g.players[side].pos
      g.returnBall(side, volley: true, random: {0.99})
      let volley = try XCTUnwrap(g.flight)
      XCTAssertEqual(volley.stroke, .volley)
      XCTAssertEqual(volley.landing, target)
      g.launch(side, aim: target, kind: volley.kind)
      XCTAssertLessThan(volley.duration, g.flight!.duration)
    }
  }

  func testSwipeTempoAndEffortCarryBetweenPoints() throws {
    func run(_ duration: Double) throws -> PracticeEngine {
      var g = incoming(side: 0)
      var swipe = PracticeGesture(side: 0)
      _ = swipe.update(at: .zero, screenPoint: .zero, timestamp: 0)
      let action = try XCTUnwrap(swipe.update(at: Vec(x: -4,y: 0),
        screenPoint: Vec(x: -90,y: 0), ended: true, timestamp: duration))
      let input = CupInput(action, shotEpoch: nil, movementEpoch: g.contactSerial, runPace: swipe.runPace)
      try JSONDecoder().decode(CupInput.self, from: JSONEncoder().encode(input)).apply(to: &g, side: 0)
      for _ in 0..<48 { g.updateFootwork(1/120) }
      return g
    }
    var fast = try run(0.08)
    let slow = try run(0.65)
    XCTAssertEqual(fast.players[0].runPace, 1.5)
    XCTAssertGreaterThan(fast.players[0].velocity.length, slow.players[0].velocity.length)
    let energy = fast.players[0].energyLevel
    XCTAssertLessThan(energy, slow.players[0].energyLevel)
    fast.end(0, reason: "Winner", tip: "")
    fast.start()
    XCTAssertEqual(fast.players[0].energyLevel, energy)
    var recovered = fast.players[0]
    recovered.expendEnergy(pace: 1, distance: 4, dt: 2, late: true)
    XCTAssertGreaterThan(recovered.energyLevel, energy)
    var early = recovered, late = recovered
    early.expendEnergy(pace: 1.5, distance: 5, dt: 1, late: false)
    late.expendEnergy(pace: 1.5, distance: 5, dt: 1, late: true)
    XCTAssertLessThan(late.energyLevel, early.energyLevel)
  }

  func testWideOpponentCannotCoverAnOpenCourtVolleyBySpeedingUp() throws {
    var game = incoming(side: 0, bot: true)
    game.settings.difficulty = .tough
    game.players[0].pos = Vec(x: 4.8, y: 14.1)
    game.players[0].destination = game.players[0].pos
    game.players[1].pos = Vec(x: 0.3, y: 0.3)
    game.launch(1, aim: Vec(x: 7.6, y: 22.6), kind: .cross)
    game.players[1].destination = game.players[1].pos
    game.players[1].velocity = Vec(x: -2.4, y: 0)
    game.tapCourt(0, at: Vec(x: 7.8, y: 5.5))
    for _ in 0..<360 where game.flight?.hitter == 1 && game.phase == .live {
      game.step(1/120, random: {0.99})
    }
    XCTAssertEqual(game.flight?.stroke, .volley)
    XCTAssertEqual(game.bounceSerial, 0)
    let volleySerial = game.contactSerial
    for _ in 0..<360 where game.phase == .live { game.step(1/120, random: {0.99}) }
    XCTAssertEqual(game.coach.records.last?.winner, 0)
    XCTAssertEqual(game.contactSerial, volleySerial)
  }

  func testWideChaseGetsOneDiveChanceAndASlowRecovery() throws {
    for side in 0...1 {
      for roll in [0.49, 0.50] {
        var g = incoming(side: side, bot: side == 1)
        g.players[side].pos.x -= 1.98
        g.players[side].destination = g.flight!.contact
        g.players[side].velocity.x = 4.2
        g.flight!.opponentReplyPrepared = true
        g.flight!.elapsed = g.flight!.duration - 0.10
        g.attemptRunningDive(side, incoming: g.flight!, random: {roll})
        g.attemptRunningDive(side, incoming: g.flight!, random: { XCTFail("Rerolled a dive"); return 0 })
        XCTAssertEqual(g.players[side].netEffort != nil, roll < 0.5)
        if roll < 0.5 {
          for _ in 0..<25 where g.flight?.hitter != side { g.step(1/120, random: {0.99}) }
          XCTAssertEqual(g.flight?.contactQuality, .diving)
          XCTAssertEqual(g.flight?.kind, .lob)
          let effort = try XCTUnwrap(g.players[side].netEffort)
          XCTAssertGreaterThan(effort.impactTime + NetStroke.dive.recovery, g.time)
          XCTAssertEqual(g.tactics[side].volleys, 0)
        }
      }
    }
  }
}
