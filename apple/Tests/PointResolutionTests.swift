import XCTest
import simd
@testable import TennisCore

final class PointResolutionTests: XCTestCase {
  private func fault(_ kind: String, hitter: Int = 1, targetX: Double = 1.4) -> PracticeEngine {
    var engine = PracticeEngine(settings: .init(local: true))
    engine.phase = .live
    engine.players[hitter].pos = Vec(x: 6, y: hitter == 0 ? 24 : -0.5)
    engine.launch(hitter, aim: Vec(x: targetX, y: hitter == 0 ? 1.8 : 21.97), kind: .cross, fault: kind)
    return engine
  }

  private func reachImpact(_ engine: inout PracticeEngine, dt: Double = 1 / 120) {
    for _ in 0..<1000 where engine.phase == .live { engine.step(dt) }
  }

  func testOutTargetAcceptsSwipesThroughBounceWithoutChangingScoreOrAddingSwing() throws {
    for side in 0...1 {
      for kind in ["wide", "long"] {
        var engine = fault(kind, hitter: 1-side)
        let target = try XCTUnwrap(engine.contactGuide(side))
        XCTAssertEqual(target, engine.outBallChaseTarget(side))
        XCTAssertNil(engine.movementGuide(side)) // No yellow chase line for an out ball.
        engine.apply(.guidedMove(.receive), side: side)
        XCTAssertEqual(engine.players[side].destination, target)
        reachImpact(&engine)
        XCTAssertTrue(engine.acceptsCourtMovement)
        XCTAssertEqual(engine.players[side].destination, target)
        XCTAssertEqual(engine.contactGuide(side), target)
        let score = engine.scoring.points, events = engine.coach.events, serial = engine.contactSerial
        engine.players[side].pos = Vec(x: 4, y: side == 0 ? 22 : 1.77)
        engine.players[side].velocity = .zero
        let from = engine.players[side].pos
        for _ in 0..<24 { engine.apply(.guidedMove(.receive), side: side); engine.step(1/120) }
        XCTAssertLessThan(engine.players[side].pos.distance(to: target), from.distance(to: target))
        XCTAssertEqual(engine.scoring.points, score)
        XCTAssertEqual(engine.coach.events, events)
        XCTAssertEqual(engine.contactSerial, serial)
        while engine.isResolvingPoint { engine.step(1/120) }
        XCTAssertFalse(engine.acceptsCourtMovement)
        XCTAssertNil(engine.contactGuide(side))
        let destination = engine.players[side].destination
        engine.tapCourt(side, at: .zero)
        XCTAssertEqual(engine.players[side].destination, destination)
      }
    }
  }

  func testOutChaseDoesNotCreateNetTargetAndDirectionalSwipeStillMoves() throws {
    let net = fault("net")
    XCTAssertNil(net.outBallChaseTarget(0))
    XCTAssertNil(net.contactGuide(0))
    var out = fault("long")
    reachImpact(&out)
    let target = try XCTUnwrap(out.outBallChaseTarget(0))
    out.swipeCourt(0, delta: Vec(x: target.x-out.players[0].pos.x, y: target.y-out.players[0].pos.y))
    XCTAssertEqual(out.players[0].destination, target)
  }

  func testFaultCompletesItsFlightBeforeMarkingImpactOrAwardingPoint() throws {
    for side in 0...1 {
      for kind in ["net", "wide", "long"] {
        var engine = fault(kind, hitter: side)
        let original = try XCTUnwrap(engine.flight)
        engine.flight!.elapsed = original.duration * 0.8 - 0.02
        engine.step(0.01)
        XCTAssertEqual(engine.phase, .live)
        XCTAssertEqual(engine.scoring.points, [0, 0])
        XCTAssertNil(engine.pointResolution)
        XCTAssertFalse(engine.showsPointResult)
        XCTAssertGreaterThan(engine.ball.distance(to: original.landing), 0)
        engine.step(0.02)
        let resolution = try XCTUnwrap(engine.pointResolution)
        XCTAssertEqual(resolution.impact?.point, original.landing)
        XCTAssertEqual(engine.ball, original.landing)
        XCTAssertTrue(resolution.showsMarker)
        XCTAssertFalse(engine.showsPointResult)
        XCTAssertEqual(engine.scoring.points[1 - side], 1)
        let serial = engine.contactSerial
        engine.step(0.04)
        XCTAssertGreaterThan(engine.ball.distance(to: original.landing), 0)
        XCTAssertEqual(engine.contactSerial, serial) // No assisted swing can return the dead ball.
      }
    }
  }

  func testBotTracksWideAndLongShotsThroughTheOutBounce() throws {
    for kind in ["wide", "long"] {
      for serve in [false,true] {
        var game = PracticeEngine(settings: .init())
        game.phase = .live
        game.players[1].pos = Vec(x: 7.1, y: -0.5)
        game.players[1].destination = Vec(x: 4, y: 0)
        game.players[1].velocity = Vec(x: -1, y: 0)
        game.launch(0, aim: Vec(x: 1.2, y: serve ? 6.3 : 2), kind: .cross, fault: kind, serve: serve)
        let start = game.players[1].pos, serial = game.contactSerial
        XCTAssertEqual(game.players[1].velocity.x, serve ? 0 : -1)
        reachImpact(&game)
        let bounce = game.players[1].pos
        if serve { XCTAssertEqual(bounce, start) } else { XCTAssertGreaterThan(start.distance(to: bounce), 0.3) }
        for _ in 0..<42 { game.step(1/120) }
        if serve { XCTAssertEqual(game.players[1].pos, start) } else { XCTAssertGreaterThan(bounce.distance(to: game.players[1].pos), 0.10) }
        XCTAssertEqual(game.contactSerial,serial)
        XCTAssertEqual(game.phase,serve ? .serveFault : .point)
        XCTAssertEqual(game.scoring.points,serve ? [0,0] : [0,1])
      }
    }
  }

  func testFirstServeFaultIgnoresReceiverMovementThroughSecondServeSetup() {
    for receiver in 0...1 {
      for fault in ["wide", "net", "long"] {
        let server = 1 - receiver
        var game = PracticeEngine(settings: .init(local: true))
        game.scoring = PracticeScore(format: .tennis, firstServer: server)
        game.phase = .live
        let feet = game.players[receiver].pos
        game.players[receiver].velocity = Vec(x: 0, y: receiver == 0 ? -4 : 4)
        let target = Vec(x: 4, y: PracticeEngine.net)
        game.players[receiver].destination = target
        game.launch(server, aim: target, kind: .line, fault: fault, serve: true)
        for _ in 0..<600 where game.phase != .serving {
          XCTAssertNil(game.outBallChaseTarget(receiver))
          game.apply(.guidedMove(.receive), side: receiver)
          game.apply(.position(target), side: receiver, movementEpoch: game.contactSerial)
          game.step(1/120, interactiveRally: true)
          XCTAssertEqual(game.players[receiver].pos, feet)
          XCTAssertEqual(game.players[receiver].velocity, .zero)
        }
        XCTAssertEqual(game.servePreparation?.number, 2)
        XCTAssertEqual(game.scoring.points, [0, 0])
      }
    }
  }

  func testRedMarkerLastsThreeTenthsAndPopupWaitsThreeQuartersAtEveryFrameRate() throws {
    for dt in [1.0 / 30, 1.0 / 60, 1.0 / 120] {
      for kind in ["net", "wide", "long"] {
        var engine = fault(kind)
        reachImpact(&engine, dt: dt)
        let pointTime = engine.time
        while engine.pointResolution!.showsMarker { engine.step(dt) }
        XCTAssertEqual(engine.time - pointTime, 0.3, accuracy: dt + 0.000001)
        XCTAssertFalse(engine.showsPointResult)
        while engine.isResolvingPoint { engine.step(dt) }
        XCTAssertEqual(engine.time - pointTime, 0.75, accuracy: dt + 0.000001)
        XCTAssertTrue(engine.showsPointResult)
        XCTAssertFalse(engine.pointResolution!.showsMarker)
        XCTAssertFalse(engine.needsSimulation)
        for _ in 0..<240 { engine.step(dt) }
        XCTAssertEqual(engine.scoring.points, [1, 0])
        XCTAssertEqual(engine.history.count, 1)
      }
    }
  }

  func testNetFaultMeetsMeshAlongShotLineAndFallsBackOnHittersSide() throws {
    for side in 0...1 {
      let engine = fault("net", hitter: side)
      let flight = try XCTUnwrap(engine.flight)
      let impact = try XCTUnwrap(FaultImpact(flight: flight))
      let target = Vec(x: 1.4, y: side == 0 ? 1.8 : 21.97)
      let t = (PracticeEngine.net - flight.from.y) / (target.y - flight.from.y)
      XCTAssertEqual(impact.point.y, PracticeEngine.net)
      XCTAssertEqual(impact.point.x, flight.from.x + (target.x - flight.from.x) * t, accuracy: 0.000001)
      XCTAssertGreaterThan(impact.height, 0)
      let first = impact.ball(after: 0)
      XCTAssertEqual(first.position, impact.point)
      XCTAssertEqual(first.height, impact.height)
      let falling = impact.ball(after: 0.1)
      XCTAssertLessThan(falling.height, impact.height)
      XCTAssertGreaterThan((falling.position.y - PracticeEngine.net) * (side == 0 ? 1 : -1), 0)
      XCTAssertEqual(impact.ball(after: 0.4).height, 0)
    }
  }

  func testWideAndLongMarksAreOutsideCorrectLinesAndBounceContinues() throws {
    for side in 0...1 {
      for kind in ["wide", "long"] {
        for targetX in [1.4, 6.83] {
          let engine = fault(kind, hitter: side, targetX: targetX)
          let impact = try XCTUnwrap(engine.flight.flatMap(FaultImpact.init))
          if kind == "wide" {
            XCTAssertTrue(targetX < 4 ? impact.point.x < 0 : impact.point.x > PracticeEngine.width)
          } else {
            XCTAssertTrue(side == 0 ? impact.point.y < 0 : impact.point.y > PracticeEngine.length)
          }
          XCTAssertEqual(impact.ball(after: 0).height, 0)
          XCTAssertGreaterThan(impact.ball(after: 0.2).height, 0)
          let after = impact.ball(after: 0.75)
          XCTAssertEqual(after.height, 0)
          XCTAssertGreaterThan(after.position.distance(to: impact.point), 0.1)
          XCTAssertEqual(impact.ball(after: 2).position, after.position)
        }
      }
    }
  }

  func testShotTracksKeepTheirBearingThroughTheBounceAndRunoff() throws {
    for side in 0...1 {
      for kind in [ShotKind.cross,.line,.lob,.slice,.drop,.angle] {
        let near = side == 0
        let start = Vec(x:6.7,y:near ? 23.37 : 0.4)
        let target = Vec(x:1.5,y:near ? 1.47 : 22.3)
        var game = PracticeEngine(settings:.init(local:true))
        game.phase = .live
        game.players[side].pos = start
        game.launch(side,aim:target,kind:kind)
        var flight = try XCTUnwrap(game.flight)
        // Include an incoming strike well away from the feet, as happens on a stretch.
        flight.strikeOrigin = start.world(height:1.24)+[0.65,0,near ? -0.31 : 0.31]
        let origin = flight.launchPosition, dx = target.x-origin.x, dz = target.y-origin.y
        let length = hypot(dx,dz)
        var previous = -1.0
        for i in 0...175 {
          let p = Double(i)/100
          let ball = i <= 100 ? flight.worldBall(at:p) : flight.runout(after:p-1)
          let x = Double(ball.x)-origin.x, z = Double(ball.z)-origin.y
          XCTAssertLessThan(abs(dx*z-dz*x)/length,0.00002)
          let along = (dx*x+dz*z)/length
          XCTAssertGreaterThanOrEqual(along+0.00001,previous)
          XCTAssertGreaterThanOrEqual(ball.y,0)
          previous = along
        }
        XCTAssertEqual(flight.worldBall(at:0),flight.launchPoint)
        XCTAssertEqual(flight.worldBall(at:0.8).y,0,accuracy:0.000001)
        XCTAssertEqual(flight.worldBall(at:1),flight.runout(after:0))
        if kind == .cross || kind == .line {
          let depth = flight.runout(after:PointResolution.resultDelay).z
          XCTAssertTrue(near ? depth < 0 : depth > Float(PracticeEngine.length))
        }
      }
    }
  }

  func testHighOverheadClearsTheBackstopWhileLowBallsReboundOffIt() {
    let shot = BallFlight(from:Vec(x:4.115,y:13.1),landing:Vec(x:4.115,y:6),
      contact:Vec(x:4.115,y:-3),duration:0.48,hitter:0,fault:nil,explanation:"",loft:0.45,power:.overhead)
    let end = shot.runout(after:PointResolution.resultDelay)
    XCTAssertGreaterThan(end.y,2.24)
    XCTAssertLessThan(Double(end.z),CourtRunoff.depth.lowerBound)
    let pad = CourtRunoff.depth.lowerBound
    XCTAssertEqual(CourtRunoff.afterPlay(Vec(x:4,y:pad-1)).y,pad+0.25,accuracy:0.00001)
  }

  func testVeryShallowAngleRunsAlongItsBearingWithinRacketReachOfYellow() {
    let landing = Vec(x:7.8,y:12.39)
    let flight = BallFlight(from:Vec(x:0.25,y:11.17),landing:landing,
      contact:Vec(x:7.8,y:12.84),duration:1.3,hitter:1,fault:nil,explanation:"",loft:1,kind:.angle)
    XCTAssertLessThan(flight.reboundEnd.distance(to:flight.contact),0.8)
    XCTAssertGreaterThan(flight.reboundEnd.x,landing.x)
    XCTAssertGreaterThan(flight.reboundEnd.y,landing.y)
  }

  func testUntouchedWinnerContinuesBehindBaselineInLiveReplayAndRestoredPoint() throws {
    for side in 0...1 {
      let near = side == 0
      var game = PracticeEngine(settings:.init(local:true,allCourtTraining:false))
      game.phase = .live
      game.players[side].pos = Vec(x:6.7,y:near ? 23.37 : 0.4)
      game.players[1-side].pos = Vec(x:7.8,y:near ? 1.3 : 22.5)
      for index in 0...1 { game.players[index].destination = game.players[index].pos }
      var animation = CourtPerformance(game:game)
      game.launch(side,aim:Vec(x:1.5,y:near ? 1.47 : 22.3),kind:.cross)
      var atEnd: CourtPoint3D?, restored: PracticeEngine?
      for _ in 0..<600 where !game.showsPointResult {
        game.step(PointReplay.tick,random:{0.8})
        animation.update(game:game,dt:PointReplay.tick)
        if game.isResolvingPoint && atEnd == nil {
          atEnd = game.worldBall
          restored = try JSONDecoder().decode(PracticeEngine.self,from:JSONEncoder().encode(game))
        } else if restored != nil { restored!.step(PointReplay.tick,random:{0.8}) }
      }
      let last = game.worldBall
      XCTAssertTrue(game.showsPointResult)
      XCTAssertGreaterThan(simd_distance(try XCTUnwrap(atEnd),last),1)
      XCTAssertTrue(near ? last.z < 0 : last.z > Float(PracticeEngine.length))
      XCTAssertEqual(game.ball,last.courtPosition)
      XCTAssertEqual(restored?.worldBall,last)
      XCTAssertEqual(animation.replay.frames.last?.ball,last)
      XCTAssertEqual(game.scoring.points[side],1)
      XCTAssertNil(game.pointResolution?.impact)
    }
  }

  func testWinnerAlsoWaitsButNeverShowsAnOutMarker() {
    var engine = PracticeEngine(settings: .init())
    engine.phase = .live
    engine.end(0, reason: "Opponent didn't reach the ball in time.", tip: "")
    XCTAssertFalse(engine.showsPointResult)
    XCTAssertNil(engine.pointResolution?.impact)
    for _ in 0..<90 { engine.step(1 / 120) }
    XCTAssertTrue(engine.showsPointResult)
    XCTAssertEqual(engine.scoring.points, [1, 0])
  }

  func testNewPointClearsOldMarkerAndFlightResolution() {
    var engine = fault("long")
    reachImpact(&engine)
    engine.start(random: { 0.5 })
    XCTAssertEqual(engine.phase, .serving)
    XCTAssertNil(engine.pointResolution)
    XCTAssertNil(engine.flight)
    XCTAssertFalse(engine.showsPointResult)
  }

  func testEveryOpponentStyleAndDifficultyProducesNetWideAndLongFaults() throws {
    var seed: UInt64 = 91
    func random() -> Double {
      seed = seed &* 6364136223846793005 &+ 1442695040888963407
      return Double(seed >> 11) / 9007199254740992.0
    }
    for difficulty in Difficulty.allCases {
      for style in BotStyle.allCases {
        var engine = PracticeEngine(settings: .init(difficulty: difficulty, style: style))
        var seen: Set<String> = []
        for _ in 0..<600 {
          let contact = Vec(x: 2, y: 1)
          engine.phase = .live
          engine.players[1].pos = contact
          engine.players[1].destination = contact
          engine.flight = BallFlight(from: Vec(x: 6, y: 24), landing: contact,
            contact: contact, duration: 2, hitter: 0, fault: nil, explanation: "", loft: 1)
          engine.ball = contact
          engine.returnBall(1, volley: false, random: random)
          if let kind = engine.flight?.fault {
            seen.insert(kind)
            let impact = try XCTUnwrap(engine.flight.flatMap(FaultImpact.init))
            if kind == "net" { XCTAssertEqual(impact.point.y, PracticeEngine.net) }
            if kind == "wide" { XCTAssertTrue(impact.point.x < 0 || impact.point.x > PracticeEngine.width) }
            if kind == "long" { XCTAssertGreaterThan(impact.point.y, PracticeEngine.length) }
          }
        }
        XCTAssertEqual(seen, ["net", "wide", "long"], "\(difficulty) / \(style)")
      }
    }
  }
}
