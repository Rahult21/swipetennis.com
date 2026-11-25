import XCTest
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

  func testOutTargetStaysTappableThroughBounceWithoutChangingScoreOrAddingSwing() throws {
    for side in 0...1 {
      for kind in ["wide", "long"] {
        var engine = fault(kind, hitter: 1-side)
        let target = try XCTUnwrap(engine.contactGuide(side))
        XCTAssertEqual(target, engine.outBallChaseTarget(side))
        XCTAssertNil(engine.movementGuide(side)) // No yellow chase line for an out ball.
        engine.tapCourt(side, at: target)
        XCTAssertEqual(engine.players[side].destination, target)
        reachImpact(&engine)
        XCTAssertTrue(engine.acceptsCourtMovement)
        XCTAssertEqual(engine.players[side].destination, target)
        XCTAssertEqual(engine.contactGuide(side), target)
        let score = engine.scoring.points, events = engine.coach.events, serial = engine.contactSerial
        engine.players[side].pos = Vec(x: 4, y: side == 0 ? 22 : 1.77)
        engine.players[side].velocity = .zero
        let from = engine.players[side].pos
        for _ in 0..<24 { engine.tapCourt(side, at: target); engine.step(1/120) }
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
