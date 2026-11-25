import XCTest

@testable import TennisCore

final class AllCourtTests: XCTestCase {
  private func approach(style: BotStyle = .baseline, x: Double = 2) -> PracticeEngine {
    var engine = PracticeEngine(settings: PracticeSettings(style: style))
    engine.phase = .live
    engine.players[0].pos = Vec(x: x, y: 23.4)
    engine.players[0].destination = engine.players[0].pos
    engine.players[1].pos = Vec(x: PracticeEngine.width - x, y: style == .volley ? 8 : -0.8)
    engine.players[1].destination = engine.players[1].pos
    engine.flight = BallFlight(
      from: engine.players[1].pos,
      landing: Vec(x: x, y: 22.3), contact: engine.players[0].pos,
      duration: 2, hitter: 1, fault: nil, explanation: "", loft: 1)
    engine.choose(0, .line)
    engine.returnBall(0, volley: false, random: { 0.999 })
    return engine
  }

  func testCleanLineApproachProducesReachableEasyVolleyAcrossStyles() {
    for style in BotStyle.allCases {
      for x in [1.5, 6.7] {
        var engine = approach(style: style, x: x)
        XCTAssertTrue(engine.flight!.trainingApproach)
        XCTAssertNil(engine.flight!.fault)
        XCTAssertEqual(engine.flight!.landing.x, x, accuracy: 0.000001)
        XCTAssertFalse(engine.attacking[0])
        XCTAssertFalse(engine.followingApproach[0])
        XCTAssertTrue(engine.approachAvailable[0])
        engine.apply(.guidedMove(.approach), side: 0)
        XCTAssertTrue(engine.attacking[0] && engine.followingApproach[0])
        XCTAssertLessThan(engine.players[0].destination.y, 18.285)
        for _ in 0..<900 where engine.contactSerial < 2 && engine.phase == .live {
          if let due = engine.opponentContactDue(0), due < 0.14 && due >= 0 {
            engine.beginSplit(0)
          }
          engine.step(1 / 120, random: { 0.99 })
          XCTAssertLessThanOrEqual(
            engine.players[1].velocity.length, style.speed * Difficulty.easy.speed + 0.001)
        }
        XCTAssertEqual(
          engine.contactSerial, 2,
          "\(style) failed to reach line approach: \(engine.feedback.reason)")
        guard engine.contactSerial == 2 else { continue }
        XCTAssertTrue(engine.flight!.trainingReply)
        XCTAssertEqual(engine.flight!.kind, .cross)
        XCTAssertLessThan(engine.flight!.loft, 2)
        XCTAssertNil(engine.flight!.fault)
        XCTAssertGreaterThan(engine.tactics[0].splitSteps, 0)
        XCTAssertFalse(engine.followingApproach[0])
        engine.apply(.guidedMove(.receive), side: 0)
        for _ in 0..<600 where engine.contactSerial < 3 && engine.phase == .live {
          engine.step(1 / 120, random: { 0.99 })
        }
        XCTAssertEqual(
          engine.contactSerial, 3, "\(style) failed to reach lob: \(engine.feedback.reason)")
        XCTAssertEqual(engine.flight!.hitter, 0)
        XCTAssertEqual(engine.flight!.stroke, .volley)
        XCTAssertNil(engine.flight!.fault)
        XCTAssertEqual(engine.tactics[0].volleys, 1)
        XCTAssertEqual(engine.tactics[0].openCourtShots, 1)
      }
    }
  }

  func testManualMovementOverridesAutomaticApproachAndRecoverExitsAttack() {
    var engine = approach()
    let target = Vec(x: 7, y: 22)
    engine.move(0, to: target)
    for _ in 0..<5 { engine.step(1 / 120) }
    XCTAssertFalse(engine.followingApproach[0])
    XCTAssertEqual(engine.players[0].destination, target)
    engine.recover(0)
    XCTAssertFalse(engine.attacking[0])
    XCTAssertEqual(engine.players[0].destination.y, PracticeEngine.length)
    XCTAssertLessThanOrEqual(
      abs(engine.players[0].destination.x - PracticeEngine.width / 2), 0.914401)
  }

  func testTrainingCanBeDisabledWithoutChangingCleanContactGuarantee() {
    var engine = approach()
    engine.settings.allCourtTraining = false
    engine.flight!.hitter = 1
    engine.flight!.contact = engine.players[0].pos
    engine.choose(0, .line)
    engine.returnBall(0, volley: false, random: { 0.999 })
    XCTAssertFalse(engine.flight!.trainingApproach)
    XCTAssertNil(engine.flight!.fault)
  }

  func testOlderSavedSettingsDecodeWithoutLosingTheArchive() throws {
    let json = Data(
      #"{"local":false,"difficulty":"Easy","style":"Baseline","surface":"Grass"}"#.utf8)
    let settings = try JSONDecoder().decode(PracticeSettings.self, from: json)
    XCTAssertTrue(settings.allCourtTraining)
    var disabled = settings
    disabled.allCourtTraining = false
    let roundTrip = try JSONDecoder().decode(
      PracticeSettings.self, from: JSONEncoder().encode(disabled))
    XCTAssertFalse(roundTrip.allCourtTraining)
    XCTAssertEqual(roundTrip.style, settings.style)
  }

  func testOverheadUsesDescendingReachableHeightAndRaisedRacket() {
    let flight = BallFlight(
      from: Vec(x: 3, y: 1), landing: Vec(x: 3, y: 18.4),
      contact: Vec(x: 3, y: 19.5), duration: 2.6, hitter: 1, fault: nil, explanation: "", loft: 2.5,
      kind: .lob)
    let target = BallContactWindow.overheadTarget(flight: flight, side: 0)!
    let window = BallContactWindow.next(flight: flight, player: target.point, side: 0)!
    XCTAssertTrue(window.overhead && window.volley)
    XCTAssertGreaterThan(window.entry, 0.4)
    XCTAssertLessThan(window.exit, 0.8)
    let height = sin(window.entry / 0.8 * .pi) * flight.loft * 1.7
    XCTAssertLessThanOrEqual(height, 2.950001)
    XCTAssertGreaterThanOrEqual(height, 2.2)
    var animation = StrokeAnimation()
    animation.hit(style: .overhead)
    XCTAssertGreaterThan(animation.contactPose.racketCentre.y, 60)
    XCTAssertFalse(animation.contactPose.supportHandOnGrip)
  }

  func testNetCoverageTracksShotSideAndOpenTargetAvoidsOpponent() {
    let left = CourtTactics.netCoverage(side: 0, opponentContact: Vec(x: 1, y: 1))
    let right = CourtTactics.netCoverage(side: 0, opponentContact: Vec(x: 7.23, y: 1))
    XCTAssertLessThan(left.x, 4.115)
    XCTAssertGreaterThan(right.x, 4.115)
    XCTAssertEqual(left.y, PracticeEngine.net + 2.8)
    XCTAssertGreaterThan(
      CourtTactics.openCourt(side: 0, opponent: Vec(x: 1, y: 1), overhead: true).x, 4.115)
  }

  func testBillboardGivesTheNextActionForThePatternAndOutBall() {
    var engine = approach()
    XCTAssertEqual(engine.instruction.title, "Swipe in along the yellow line")
    engine.apply(.guidedMove(.approach), side: 0)
    XCTAssertEqual(engine.instruction.title, "Follow your shot to the net")
    engine.beginSplit(0)
    XCTAssertEqual(engine.instruction.title, "Split step. Read the reply.")
    engine.time += 0.3
    engine.flight!.hitter = 1
    engine.flight!.from = Vec(x: 2, y: 1)
    engine.flight!.landing = Vec(x: 3, y: 18.4)
    engine.flight!.loft = 2.5
    engine.flight!.elapsed = 0
    XCTAssertEqual(engine.instruction.title, "Get under the lob")
    engine.flight!.fault = "long"
    XCTAssertEqual(engine.instruction.title, "Watch the bounce")
    engine.phase = .point
    engine.feedback.title = "Your point."
    XCTAssertEqual(engine.instruction.title, "Your point.")
  }
}
