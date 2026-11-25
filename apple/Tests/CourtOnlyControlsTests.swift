import XCTest
@testable import TennisCore

final class CourtOnlyControlsTests: XCTestCase {
  func testTappingNetPostStillSplitsInsteadOfBeingSwallowedBySliceGesture() {
    for side in 0...1 {
      let point = Vec(x: -1.65, y: PracticeEngine.net)
      var gesture = PracticeGesture(side: side, intent: .slice)
      _ = gesture.update(at: point)
      XCTAssertEqual(gesture.update(at: point, ended: true), .courtTap(point))
    }
  }

  func testRepeatedYellowTapsDoNotDelayTheRunForEitherHuman() {
    for side in 0...1 {
      var engine = PracticeEngine(settings: .init(local: true))
      engine.phase = .live
      engine.launch(1 - side, aim: Vec(x: 1.8, y: side == 0 ? 22.5 : 1.27), kind: .cross)
      let target = engine.contactGuide(side)!
      var untapped = engine
      untapped.move(side, to: target)
      for _ in 0..<400 where engine.flight?.hitter != side && engine.phase == .live {
        let stillRunning = engine.players[side].pos.distance(to: target) > PracticeEngine.contactRadius
        engine.tapCourt(side, at: target)
        engine.step(1 / 120, random: { 0.5 })
        untapped.step(1 / 120, random: { 0.5 })
        if stillRunning {
          XCTAssertEqual(engine.players[side].pos.x, untapped.players[side].pos.x, accuracy: 0.000001)
          XCTAssertEqual(engine.players[side].pos.y, untapped.players[side].pos.y, accuracy: 0.000001)
        }
      }
      XCTAssertEqual(engine.flight?.hitter, side)
      XCTAssertNil(engine.flight?.fault)
      XCTAssertEqual(engine.players[side].destination, target)
      XCTAssertGreaterThan(engine.tactics[side].splitSteps, 0)
    }
  }

  func testPlayerSwipeUsesScreenDirectionAndMirrorsFarPlayer() {
    for side in 0...1 {
      var gesture = PracticeGesture(side: side, intent: .shot)
      let from = Vec(x: 100, y: 200)
      let to = Vec(x: 100, y: side == 0 ? 160 : 240)
      XCTAssertNil(gesture.update(at: Vec(x: 2, y: 24), screenPoint: from))
      XCTAssertEqual(gesture.update(at: Vec(x: 2, y: 21), screenPoint: to, ended: true),
        .shotSwipe(Vec(x: 0, y: -40)))
    }
  }

  func testTapOnPlayerIsStillATapAndCancelledDragDoesNotFire() {
    var gesture = PracticeGesture(side: 0, intent: .shot)
    _ = gesture.update(at: Vec(x: 3, y: 22), screenPoint: Vec(x: 100, y: 300))
    XCTAssertEqual(gesture.update(at: Vec(x: 3, y: 22), screenPoint: Vec(x: 102, y: 301), ended: true),
      .courtTap(Vec(x: 3, y: 22)))
    gesture = PracticeGesture(side: 0, intent: .shot)
    _ = gesture.update(at: .zero, screenPoint: .zero)
    _ = gesture.update(at: .zero, screenPoint: Vec(x: 0, y: -60))
    XCTAssertNil(gesture.update(at: .zero, screenPoint: .zero, ended: true))
  }

  func testTouchIntentDoesNotSwitchWhenMovementSwipeCrossesPlayer() {
    var gesture = PracticeGesture(side: 0)
    _ = gesture.update(at: Vec(x: 2, y: 22), screenPoint: Vec(x: 20, y: 300))
    XCTAssertEqual(gesture.update(at: Vec(x: 4, y: 22), screenPoint: Vec(x: 100, y: 300), ended: true),
      .run(Vec(x: 2, y: 0)))
  }

  func testStaleShotGestureCannotChooseShotForAnotherBall() {
    var engine = PracticeEngine(settings: .init())
    engine.startRally()
    let epoch = engine.shotGestureEpoch(0)
    let destination = engine.players[0].destination
    engine.apply(.shotSwipe(Vec(x: 0, y: -40)), side: 0, shotEpoch: epoch)
    XCTAssertEqual(engine.players[0].kind, .line)
    XCTAssertEqual(engine.players[0].destination, destination)
    engine.launch(0, aim: Vec(x: 2, y: 2), kind: .line)
    engine.launch(1, aim: Vec(x: 6, y: 22), kind: .cross)
    engine.apply(.shotSwipe(Vec(x: 0, y: 40)), side: 0, shotEpoch: epoch)
    XCTAssertEqual(engine.players[0].kind, .line)
  }

  func testReceiverShotGestureCanSpanTossAndServeContact() {
    var engine = PracticeEngine(settings: .init())
    engine.start(random: { 0.5 })
    let epoch = engine.shotGestureEpoch(0)
    for _ in 0..<500 where engine.phase == .serving { engine.step(1 / 120, random: { 0.5 }) }
    XCTAssertEqual(engine.phase, .live)
    XCTAssertEqual(engine.shotGestureEpoch(0), epoch)
    engine.apply(.shotSwipe(Vec(x: 0, y: -40)), side: 0, shotEpoch: epoch)
    XCTAssertEqual(engine.players[0].kind, .line)
  }

  func testAfterContactForwardSwipeFromPlayerIsMovement() {
    var engine = PracticeEngine(settings: .init())
    engine.phase = .live
    engine.launch(0, aim: Vec(x: 2, y: 2), kind: .cross)
    XCTAssertFalse(engine.canChooseShot(0))
    XCTAssertNil(engine.shotGestureEpoch(0))
    engine.swipeCourt(0, delta: Vec(x: 0, y: -4))
    XCTAssertTrue(engine.followingApproach[0])
  }

  func testTapQueuesServeUntilTargetSettlesWithoutRepeatedTaps() {
    var engine = PracticeEngine(settings: .init(local: true))
    engine.start()
    engine.chooseServe(.wide, side: 1)
    engine.tapCourt(1, at: engine.players[1].pos)
    XCTAssertTrue(engine.servePreparation!.requested)
    XCTAssertFalse(engine.servePreparation!.isTossing)
    for _ in 0..<400 where engine.phase == .serving { engine.step(1 / 120) }
    XCTAssertEqual(engine.phase, .live)
    XCTAssertEqual(engine.contactSerial, 1)
    XCTAssertEqual(engine.flight?.hitter, 1)
  }

  func testNewAimCancelsQueuedServeAndReceiverTapCannotServeForOpponent() {
    var engine = PracticeEngine(settings: .init(local: true))
    engine.start()
    engine.requestServe(1)
    engine.chooseServe(.wide, side: 1)
    XCTAssertFalse(engine.servePreparation!.requested)
    engine.tapCourt(0, at: Vec(x: 1, y: 22))
    for _ in 0..<600 { engine.step(1 / 120) }
    XCTAssertEqual(engine.phase, .serving)
    XCTAssertFalse(engine.servePreparation!.isTossing)
  }
}
