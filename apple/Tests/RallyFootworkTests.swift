import XCTest
import simd
@testable import TennisCore

final class RallyFootworkTests: XCTestCase {
  func testWideDrivePlantsOutsideAndOpensInsideOnRecoveryCommand() throws {
    for side in 0...1 {
      for direction in [-1.0, 1.0] {
        for requestRecovery in [false, true] {
          var game = PracticeEngine(settings: .init(local: true, surface: .hard, allCourtTraining: false))
          game.phase = .live
          game.players[side].pos = Vec(x: 4.115, y: side == 0 ? 22.6 : PracticeEngine.length-22.6)
          game.players[1-side].pos = Vec(x: 4.115, y: side == 0 ? 1 : PracticeEngine.length-1)
          for i in 0...1 { game.players[i].destination = game.players[i].pos }
          game.launch(1-side, aim: Vec(x: 4.115+direction*2.65, y: side == 0 ? 21.5 : PracticeEngine.length-21.5), kind: .cross)
          game.apply(.guidedMove(.receive), side: side)
          var performance = CourtPerformance(game: game), poses: [AthletePose] = []
          var impact: Int?
          for tick in 0..<420 {
            if let impact, tick == impact+19, requestRecovery { game.apply(.guidedMove(.recover), side: side) }
            game.step(PointReplay.tick, random: { 0.8 })
            performance.update(game: game, dt: PointReplay.tick)
            let frame = try XCTUnwrap(performance.frame)
            poses.append(side == 0 ? frame.near : frame.far)
            if impact == nil && game.flight?.hitter == side { impact = tick }
            if let impact, tick >= impact+70 { break }
          }
          let hit = try XCTUnwrap(impact)
          let rightPlant = (direction > 0) == (side == 0)
          let outside: BodyJoint = rightPlant ? .rightShoe : .leftShoe
          let inside: BodyJoint = rightPlant ? .leftShoe : .rightShoe
          let anchor = poses[hit-17][outside]
          // A shoe can roll about the forefoot while keeping its place on court.
          for i in (hit-17)...(hit+33) {
            let shift = poses[i][outside]-anchor
            XCTAssertLessThan(hypot(shift.x,shift.z), 0.025)
          }
          let hips = (poses[hit-17][.leftHip]+poses[hit-17][.rightHip])/2
          XCTAssertLessThan(abs(hips.x-anchor.x), 0.17)
          let inward = Float(-direction)
          let first = poses[hit+34][inside]-poses[hit+18][inside]
          if requestRecovery {
            XCTAssertGreaterThan(first.x*inward, 0.18)
            XCTAssertGreaterThan(first.y, 0.035)
            XCTAssertGreaterThan((poses[hit+62][outside].x-anchor.x)*inward, 0.28)
          } else {
            XCTAssertLessThan(abs(first.x), 0.025)
          }
        }
      }
    }
  }

  private func incoming(side: Int, bot: Bool = false) -> PracticeEngine {
    var game = PracticeEngine(settings: .init(local: !bot, surface: .hard, allCourtTraining: false))
    game.phase = .live
    let p = Vec(x: 4.2, y: side == 0 ? 23.4 : 0.37)
    game.players[side].pos = p
    game.players[side].destination = p
    game.launch(1-side, aim: Vec(x: p.x, y: p.y + (side == 0 ? -PracticeEngine.bounceSpacing : PracticeEngine.bounceSpacing)), kind: .cross)
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
      var lastCarry = 0.0
      for length in [24.0, 82, 148] {
        var game = incoming(side: side)
        game.selectShotSwipe(Vec(x: 0, y: -length), side: side)
        game.players[side].velocity = Vec(x: 4.1, y: 0)
        game.returnBall(side, volley: false, random: { 0.99 })
        let block = try XCTUnwrap(game.flight)
        XCTAssertEqual(block.contactQuality, .stretched)
        XCTAssertTrue(PracticeEngine.isShortBall(block, receiving: 1-side))
        let carry = abs(block.landing.y - PracticeEngine.net)
        XCTAssertGreaterThan(carry, lastCarry)
        lastCarry = carry
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

  func testLateLateralAndForwardChasesDiveLobAndRecover() throws {
    for side in 0...1 {
      for forward in [false, true] {
        var g = incoming(side: side, bot: side == 1)
        let direction = side == 0 ? -1.0 : 1.0
        g.players[side].pos = g.flight!.contact
        if forward {
          g.players[side].pos.y -= 1.98 * direction
          g.players[side].velocity.y = 4.2 * direction
        } else {
          g.players[side].pos.x -= 1.98
          g.players[side].velocity.x = 4.2
        }
        g.players[side].destination = g.flight!.contact
        g.flight!.opponentReplyPrepared = true
        g.flight!.elapsed = g.flight!.duration - 0.10
        g.attemptRunningDive(side, incoming: g.flight!)
        let effort = try XCTUnwrap(g.players[side].netEffort)
        for _ in 0..<25 where g.flight?.hitter != side { g.step(1/120, random: {0.99}) }
        XCTAssertEqual(g.flight?.contactQuality, .diving)
        XCTAssertEqual(g.flight?.stroke, .lob)
        XCTAssertGreaterThan(effort.impactTime + NetStroke.dive.recovery, g.time)
        let overhead = try XCTUnwrap(BallContactWindow.overheadTarget(flight:g.flight!,side:1-side))
        g.players[1-side].pos = overhead.point
        g.players[1-side].destination = overhead.point
        for _ in 0..<600 where g.flight?.hitter == side && g.phase == .live { g.step(1/120, random:{0.99}) }
        XCTAssertEqual(g.flight?.stroke, .overhead)
      }
    }
  }

  func testLateSwipeProducesARealLobAndOpponentRunsUnderIt() throws {
    for (aim,delay) in [(Vec(x:0.865,y:21.37),0.675),(Vec(x:7.365,y:21.37),0.675),
                        (Vec(x:4.5,y:16.17),0.525)] {
      var game = PracticeEngine(settings:.init(difficulty:.medium,style:.allcourt,surface:.hard,allCourtTraining:false))
      game.phase = .live
      game.players[0].pos = Vec(x:4.115,y:23.1)
      let opponentStart = Vec(x:3.5,y:-0.45)
      game.players[1].pos = opponentStart
      for side in 0...1 { game.players[side].destination = game.players[side].pos }
      game.launch(1,aim:aim,kind:.cross)
      var running = false, sawLob = false, sawOverhead = false
      var performance = CourtPerformance(game:game)
      var lobTime: Double?
      var closestRacketToHead = Float.infinity
      let sendAt = try XCTUnwrap(game.flight).duration*delay
      for _ in 0..<1100 where game.phase == .live && !sawOverhead {
        if !running && game.time >= sendAt {
          let yellow = try XCTUnwrap(game.contactGuide(0))
          let feet = game.players[0].pos
          game.swipeCourt(0,delta:Vec(x:yellow.x-feet.x,y:yellow.y-feet.y))
          running = true
        }
        let before = game.contactSerial
        game.step(PointReplay.tick,random:{0.77})
        performance.update(game:game,dt:PointReplay.tick)
        if before != game.contactSerial, let flight = game.flight {
          if flight.hitter == 0 {
            sawLob = flight.isDefensiveLob && flight.fault == nil
            lobTime = game.time
          }
          else if sawLob {
            sawOverhead = flight.stroke == .overhead
            XCTAssertGreaterThan(game.players[1].pos.distance(to:opponentStart),1.5)
            XCTAssertGreaterThan(try XCTUnwrap(flight.strikeOrigin).y,2.1)
          }
        }
        if let lobTime, (0.08...0.45).contains(game.time-lobTime), let pose = performance.frame?.near {
          let shaft = pose[.strings]-pose[.grip]
          let projection = simd_dot(pose[.head]-pose[.grip],shaft)/simd_length_squared(shaft)
          let nearest = pose[.grip]+shaft*min(1,max(0,projection))
          closestRacketToHead = min(closestRacketToHead,simd_distance(nearest,pose[.head]))
        }
      }
      XCTAssertTrue(sawLob && sawOverhead)
      XCTAssertTrue(closestRacketToHead.isFinite)
      XCTAssertGreaterThan(closestRacketToHead,0.15, "Keep the racket clear of the face during landing")
    }
  }
}
