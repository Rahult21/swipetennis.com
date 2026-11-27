import XCTest

@testable import TennisCore

final class PracticeContactTests: XCTestCase {
  func testGroundReceiveMarkIsSixFeetBeyondBounceOnBothEnds() throws {
    for receiver in 0...1 {
      for kind in [ShotKind.cross, .angle, .drop, .slice, .lob] {
        var game = PracticeEngine(settings: .init(local:true))
        game.phase = .live
        let bounce = Vec(x:2.65,y:receiver == 0 ? 23.5 : 0.27)
        game.launch(1-receiver, aim:bounce, kind:kind)
        let mark = try XCTUnwrap(game.contactGuide(receiver))
        XCTAssertEqual(mark.x,bounce.x)
        XCTAssertEqual((mark.y-bounce.y)*(receiver == 0 ? 1 : -1),1.8288,accuracy:0.000001)
        game.apply(.guidedMove(.receive),side:receiver)
        XCTAssertEqual(game.players[receiver].destination,mark)
        game.players[receiver].pos = mark
        XCTAssertNotNil(game.contactWindow(receiver))
      }
    }
  }

  func testMovingToYellowBehindBaselineProducesACleanReturnAtDifferentFrameRates() {
    for receiver in 0...1 {
      for dt in [1.0 / 120, 1.0 / 60, 1.0 / 30] {
        var engine = rally(receiver: receiver, depth: 0.9, difficulty: .tough)
        engine.players[receiver].pos = Vec(x: 4.115, y: receiver == 0 ? PracticeEngine.length : 0)
        let target = engine.contactGuide(receiver)!
        engine.players[receiver].destination = PracticeEngine.own(receiver, target)
        var arrived = false
        for _ in 0..<300 where engine.contactSerial == 0 && engine.phase == .live {
          engine.step(dt, random: { 0.999999 })
          if engine.players[receiver].pos.distance(to: target) <= PracticeEngine.contactRadius {
            arrived = true
          }
        }
        XCTAssertTrue(arrived)
        XCTAssertEqual(engine.flight?.hitter, receiver)
        XCTAssertNil(engine.flight?.fault)
        XCTAssertEqual(engine.scoring.points, [0, 0])
      }
    }
  }

  func testPlayerCanFinishMovingIntoYellowWithoutAPrematureMiss() {
    var engine = rally(depth: 0.9, difficulty: .tough)
    let target = engine.contactGuide(0)!
    engine.players[0].pos.y -= 1.2
    engine.players[0].destination = engine.players[0].pos
    engine.flight!.elapsed = engine.flight!.duration * 0.86
    engine.step(1 / 120, random: { 0.999999 })
    XCTAssertEqual(engine.contactSerial, 0)
    engine.players[0].pos = target
    engine.players[0].destination = target
    engine.step(1 / 120, random: { 0.999999 })
    XCTAssertEqual(engine.flight?.hitter, 0)
    XCTAssertNil(engine.flight?.fault)
  }

  private func rally(receiver: Int = 0, depth: Double, difficulty: Difficulty = .easy)
    -> PracticeEngine
  {
    var engine = PracticeEngine(settings: PracticeSettings(local: true, difficulty: difficulty))
    let contact = Vec(x: 3, y: receiver == 0 ? PracticeEngine.length + depth : -depth)
    let landing = Vec(x: 3, y: contact.y + (receiver == 0 ? -1.1 : 1.1))
    engine.phase = .live
    engine.players[receiver].pos = contact
    engine.players[receiver].destination = contact
    engine.flight = BallFlight(
      from: Vec(x: 6, y: receiver == 0 ? 1 : 23), landing: landing, contact: contact,
      duration: 2, hitter: 1 - receiver, fault: nil, explanation: "", loft: 1)
    engine.ball = engine.flight!.from
    return engine
  }

  func testOnTimeHumanReturnsInsideOnAndBehindBaselineForBothPlayers() {
    for receiver in 0...1 {
      for depth in [-1.5, 0, 0.9] {
        for difficulty in Difficulty.allCases {
          var engine = rally(receiver: receiver, depth: depth, difficulty: difficulty)
          let guide = engine.contactGuide(receiver)!
          XCTAssertEqual(PracticeEngine.own(receiver, guide), guide)
          let window = engine.contactWindow(receiver)!
          engine.flight!.elapsed = window.entry * engine.flight!.duration - 1 / 120
          engine.players[receiver].settled = 0
          // A successful placement roll still strikes on first reach, even without time to settle.
          engine.step(1 / 120, random: { 0.999999 })
          XCTAssertEqual(engine.contactSerial, 1, "side \(receiver), depth \(depth), \(difficulty)")
          XCTAssertEqual(engine.flight?.hitter, receiver)
          XCTAssertNil(engine.flight?.fault)
          XCTAssertEqual(engine.scoring.points, [0, 0])
        }
      }
    }
  }

  func testRunningArrivalHasNoSettlingGate() {
    var engine = rally(depth: 0.8, difficulty: .tough)
    let window = engine.contactWindow(0)!
    engine.flight!.elapsed = window.entry * engine.flight!.duration - 1 / 120
    engine.players[0].velocity = Vec(x: 3, y: 0)
    engine.players[0].settled = 0
    engine.step(1 / 120, random: { 0.999999 })
    XCTAssertEqual(engine.flight?.hitter, 0)
    XCTAssertNil(engine.flight?.fault)
  }

  func testGroundstrokeHappensAtReachInsteadOfWaitingForFlightEnd() {
    var engine = rally(depth: 0.9)
    let originalDuration = engine.flight!.duration
    let expected = engine.contactWindow(0)!.entry * originalDuration
    while engine.contactSerial == 0 && engine.time < originalDuration + 0.1 {
      engine.step(1 / 120, random: { 0.999999 })
    }
    XCTAssertEqual(engine.time, expected, accuracy: 1 / 120 + 0.000001)
    XCTAssertLessThan(engine.time, originalDuration - 0.15)
    XCTAssertEqual(engine.contactSerial, 1)
  }

  func testWholeVisibleGuideIncludingBackEdgeIsHittable() {
    for receiver in 0...1 {
      for angle in stride(from: 0.0, to: 2 * .pi, by: .pi / 4) {
        var engine = rally(receiver: receiver, depth: 0.9, difficulty: .tough)
        let guide = engine.contactGuide(receiver)!
        let position = Vec(
          x: guide.x + cos(angle) * PracticeEngine.contactRadius,
          y: guide.y + sin(angle) * PracticeEngine.contactRadius)
        engine.players[receiver].pos = position
        engine.players[receiver].destination = position
        engine.flight!.elapsed = engine.flight!.duration * 0.8
        for _ in 0..<28 where engine.contactSerial == 0 {
          engine.step(1 / 60, random: { 0.999999 })
        }
        XCTAssertEqual(engine.flight?.hitter, receiver, "side \(receiver), angle \(angle)")
        XCTAssertNil(engine.flight?.fault)
        XCTAssertEqual(engine.contactSerial, 1)
      }
    }
  }

  func testVolleyArrivalAlsoGuaranteesContactWithoutSettling() {
    var engine = rally(depth: -7, difficulty: .tough)
    let contact = engine.players[0].pos
    engine.flight!.from.x = contact.x
    engine.flight!.landing = Vec(x: contact.x, y: 22)
    engine.flight!.contact = Vec(x: contact.x, y: 23.1)
    let window = engine.contactWindow(0)!
    XCTAssertTrue(window.volley)
    engine.flight!.elapsed = window.entry * engine.flight!.duration - 1 / 120
    engine.step(1 / 120, random: { 0.999999 })
    XCTAssertEqual(engine.flight?.hitter, 0)
    XCTAssertNil(engine.flight?.fault)
  }

  func testOutBallHasChaseGuideButNoContactWindowAndAwardsTheReceiver() {
    var engine = rally(depth: 1.7)
    engine.settings.local = false
    engine.flight!.fault = "long"
    engine.flight!.landing.y = PracticeEngine.length + 0.6
    engine.flight!.elapsed = engine.flight!.duration * 0.8 - 1 / 120
    XCTAssertNotNil(engine.contactGuide(0))
    XCTAssertFalse(engine.showsGoldenContact(0))
    XCTAssertNil(engine.contactWindow(0))
    engine.step(1 / 120, random: { 0.999999 })
    XCTAssertEqual(engine.scoring.points, [1, 0])
    XCTAssertEqual(engine.feedback.title, "You won the point.")
    XCTAssertEqual(engine.contactSerial, 0)
  }

  func testTooLateStillLosesAndCannotAwardThePointTwice() {
    var engine = rally(depth: 0.9)
    engine.players[0].pos.x += 2
    engine.players[0].destination = engine.players[0].pos
    engine.flight!.elapsed = engine.flight!.duration - 1 / 120
    engine.step(1 / 120, random: { 0.999999 })
    for _ in 0..<10 { engine.step(1 / 120) }
    XCTAssertEqual(engine.scoring.points, [0, 1])
    XCTAssertEqual(engine.contactSerial, 0)
  }

  func testFastFrameCrossingContactWindowDoesNotSkipTheShot() {
    var engine = rally(depth: 0.9)
    let window = engine.contactWindow(0)!
    engine.flight!.elapsed = window.entry * engine.flight!.duration - 0.005
    engine.step(0.04, random: { 0.999999 })
    XCTAssertEqual(engine.flight?.hitter, 0)
    XCTAssertNil(engine.flight?.fault)
    XCTAssertEqual(engine.contactSerial, 1)
  }
}
