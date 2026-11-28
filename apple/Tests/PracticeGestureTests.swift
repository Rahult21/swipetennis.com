import XCTest

@testable import TennisCore

final class PracticeGestureTests: XCTestCase {
  func testEightPointSwipeStartsFullGuideRunBeforeReleaseAndOnlyOnce() throws {
    for side in 0...1 {
      for kind in [MovementGuideKind.receive, .recover] {
        var engine = PracticeEngine(settings: .init(local: true))
        engine.phase = .live
        engine.players[side].pos = Vec(x: 7, y: side == 0 ? 22 : 2)
        engine.players[side].destination = engine.players[side].pos
        engine.launch(kind == .receive ? 1 - side : side,
          aim: Vec(x: 2, y: kind == .receive ? (side == 0 ? 22 : 2) : (side == 0 ? 2 : 22)), kind: .cross)
        let guide = try XCTUnwrap(engine.swipeMovementGuide(side))
        let path = Vec(x: guide.to.x - guide.from.x, y: guide.to.y - guide.from.y)
        let delta = Vec(x: path.x / path.length * 0.18, y: path.y / path.length * 0.18)
        let origin = Vec(x: 3, y: 20)
        let end = Vec(x: origin.x + delta.x, y: origin.y + delta.y)
        var gesture = PracticeGesture(side: side, movementEpoch: engine.contactSerial, targetGuide: guide)
        XCTAssertNil(gesture.update(at: origin, screenPoint: .zero))
        XCTAssertNil(gesture.update(at: end, screenPoint: Vec(x: 3, y: 0)))
        let action = try XCTUnwrap(gesture.update(at: end, screenPoint: Vec(x: 8, y: 0)))
        XCTAssertEqual(action, .guidedMove(kind))
        engine.apply(action, side: side, movementEpoch: gesture.movementEpoch)
        XCTAssertEqual(engine.players[side].destination, PracticeEngine.own(side, guide.to))
        XCTAssertEqual(engine.tactics[side].splitSteps, 0)
        XCTAssertNil(gesture.update(at: end, screenPoint: Vec(x: 30, y: 0)))
        XCTAssertNil(gesture.update(at: end, screenPoint: Vec(x: 30, y: 0), ended: true))
      }
    }
  }

  func testGuideTapAndOppositeSwipeDoNotStartAGuidedRun() {
    let guide = MovementGuide(kind: .receive, from: .zero, to: Vec(x: 4, y: 0))
    var tap = PracticeGesture(side: 0, targetGuide: guide)
    _ = tap.update(at: .zero, screenPoint: .zero)
    XCTAssertNil(tap.update(at: Vec(x: 0.1, y: 0), screenPoint: Vec(x: 3, y: 0)))
    XCTAssertEqual(tap.update(at: .zero, screenPoint: .zero, ended: true), .courtTap(.zero))
    var wrong = PracticeGesture(side: 0, targetGuide: guide)
    _ = wrong.update(at: .zero, screenPoint: .zero)
    XCTAssertNil(wrong.update(at: Vec(x: -0.2, y: 0), screenPoint: Vec(x: -12, y: 0)))
  }

  func testTappingYellowOrWhiteNeverChangesDestination() {
    for side in 0...1 {
      var engine = PracticeEngine(settings: .init(local: true))
      engine.phase = .live
      engine.launch(1 - side, aim: Vec(x: 1, y: side == 0 ? 22 : 2), kind: .cross)
      let stopped = engine.players[side].destination
      engine.tapCourt(side, at: engine.contactGuide(side)!)
      XCTAssertEqual(engine.players[side].destination, stopped)
      engine.launch(side, aim: Vec(x: 2, y: side == 0 ? 2 : 22), kind: .cross)
      engine.tapCourt(side, at: engine.recoveryGuide(side)!)
      XCTAssertEqual(engine.players[side].destination, engine.players[side].pos)
    }
  }

  func testStartingRunOnPlayerLeavesFreshSwipeAvailableForShot() throws {
    var engine = PracticeEngine(settings: .init())
    engine.startRally()
    let guide = try XCTUnwrap(engine.swipeMovementGuide(0, onPlayer: true))
    engine.apply(.guidedMove(guide.kind), side: 0, movementEpoch: engine.contactSerial)
    XCTAssertNil(engine.swipeMovementGuide(0, onPlayer: true))
    XCTAssertTrue(engine.canDrawDrop(0))
    let destination = engine.players[0].destination
    engine.apply(.shotSwipe(Vec(x: 0, y: -40)), side: 0, shotEpoch: engine.shotGestureEpoch(0))
    XCTAssertEqual(engine.players[0].kind, .line)
    XCTAssertEqual(engine.players[0].destination, destination)
    engine.launch(0, aim: Vec(x: 2, y: 2), kind: .line)
    let afterContact = engine.players[0].destination
    engine.apply(.guidedMove(.receive), side: 0, movementEpoch: 0)
    XCTAssertEqual(engine.players[0].destination, afterContact)
  }

  func testVolleyAndOverheadLessonsUseTapWithoutMovingPlayer() throws {
    for lesson in [DemoLesson.approachVolley, .overhead] {
      var engine = PracticeEngine(settings: .init())
      engine.beginShotDemo(lesson, attempt: 0, demonstration: false)
      var tapped = false
      for _ in 0..<2400 where engine.demo?.result == nil {
        if engine.canTapNetShot(0) && !tapped {
          let destination = engine.players[0].destination
          let splits = engine.tactics[0].splitSteps
          engine.tapCourt(0, at: engine.players[0].pos)
          XCTAssertEqual(engine.players[0].destination, destination)
          XCTAssertEqual(engine.tactics[0].splitSteps, splits)
          XCTAssertEqual(engine.demo?.chosenShot, .line)
          engine.demo?.scriptShot = true
          tapped = true
        }
        engine.performDemoScript()
        engine.step(1 / 120)
      }
      XCTAssertTrue(tapped, lesson.rawValue)
      XCTAssertTrue(try XCTUnwrap(engine.demo?.result).success, lesson.rawValue)
    }
  }

  func testContinuousRunFollowsUpThenLeftBeforeLiftOnEitherEnd() throws {
    for side in 0...1 {
      var game = PracticeEngine(settings: .init(local: true))
      game.phase = .live
      let facing = side == 0 ? 1.0 : -1.0
      let origin = Vec(x: 4, y: side == 0 ? 22 : 2)
      game.players[side].pos = origin
      let epoch = game.contactSerial
      var drag = PracticeGesture(side: side, movementEpoch: epoch, movementOrigin: origin)
      _ = drag.update(at: .zero, timestamp: 0)
      let up = Vec(x: 0, y: -facing)
      let left = Vec(x: -facing, y: -facing)
      let first = try XCTUnwrap(drag.update(at: up, timestamp: 0.10))
      CupInput(first, shotEpoch: nil, movementEpoch: epoch).apply(to: &game, side: side)
      XCTAssertEqual(game.players[side].destination, Vec(x: origin.x, y: origin.y - 1.5 * facing))
      let turn = try XCTUnwrap(drag.update(at: left, timestamp: 0.18))
      CupInput(turn, shotEpoch: nil, movementEpoch: epoch).apply(to: &game, side: side)
      XCTAssertEqual(game.players[side].destination, Vec(x: origin.x - 1.5 * facing, y: origin.y - 1.5 * facing))
      XCTAssertNil(drag.update(at: left, ended: true, timestamp: 0.19))
    }
  }

  func testHeldGuidedRunCanTurnIntoFreeMovement() {
    let origin = Vec(x: 4, y: 22)
    let guide = MovementGuide(kind: .receive, from: origin, to: Vec(x: 4, y: 18))
    var drag = PracticeGesture(side: 0, targetGuide: guide, movementOrigin: origin)
    _ = drag.update(at: .zero)
    XCTAssertEqual(drag.update(at: Vec(x: 0, y: -0.4)), .guidedMove(.receive))
    XCTAssertNil(drag.update(at: Vec(x: 0, y: -0.8)))
    XCTAssertEqual(drag.update(at: Vec(x: -1, y: -0.8), playerPosition: Vec(x: 4, y: 19)),
      .move(Vec(x: 2.5, y: 19)))
  }

  func testShotDirectionTracksSelectedAimAndFadesOnOpponentContactOrTimeout() throws {
    for side in 0...1 {
      var game = PracticeEngine(settings: .init(local: true))
      game.phase = .live
      game.launch(1-side, aim: Vec(x: 2, y: side == 0 ? 22 : 2), kind: .cross)
      let epoch = game.shotGestureEpoch(side)
      let swipe = Vec(x: 42, y: -40)
      var cue = try XCTUnwrap(ShotDirection(action: .shotSwipe(swipe), side: side, epoch: epoch, game: game, time: 5))
      XCTAssertNil(ShotDirection(action: .courtTap(.zero), side: side, epoch: epoch, game: game, time: 5))
      XCTAssertNil(ShotDirection(action: .shotSwipe(swipe), side: side, epoch: nil, game: game, time: 5))
      game.selectShotSwipe(swipe, side: side)
      XCTAssertEqual(cue.target, game.players[side].aim)
      var timeout = cue
      XCTAssertEqual(timeout.opacity(at: 5.86, serial: game.contactSerial, hitter: 1-side), 0.5, accuracy: 0.001)
      XCTAssertEqual(timeout.opacity(at: 6, serial: game.contactSerial, hitter: 1-side), 0)
      XCTAssertEqual(cue.opacity(at: 5, serial: game.contactSerial, hitter: 1-side), 1)
      XCTAssertEqual(cue.opacity(at: 5.1, serial: game.contactSerial + 1, hitter: side), 1)
      _ = cue.opacity(at: 5.2, serial: game.contactSerial + 2, hitter: 1-side)
      XCTAssertEqual(cue.opacity(at: 5.25, serial: game.contactSerial + 2, hitter: 1-side), 0.5, accuracy: 0.001)
      XCTAssertEqual(cue.opacity(at: 5.31, serial: game.contactSerial + 2, hitter: 1-side), 0)
    }
  }

  func testUnanchoredCourtSwipesResolveOnReleaseAtAnySpeed() {
    for side in 0...1 {
      for delta in [Vec(x: 0, y: -3), Vec(x: 3, y: 0), Vec(x: -2, y: 2)] {
        var gesture = PracticeGesture(side: side)
        let from = Vec(x: 4, y: side == 0 ? 22 : 2)
        let to = Vec(x: from.x + delta.x, y: from.y + delta.y)
        XCTAssertNil(gesture.update(at: from, timestamp: 1))
        XCTAssertNil(gesture.update(at: to, timestamp: 1.1))
        XCTAssertEqual(gesture.update(at: to, ended: true, timestamp: 1.2), .run(delta))
      }
    }
  }

  func testTapToleranceAndCancelledSwipeDoNotBecomeShots() {
    var gesture = PracticeGesture(side: 0)
    _ = gesture.update(at: Vec(x: 4, y: 22))
    XCTAssertEqual(gesture.update(at: Vec(x: 4.1, y: 22.1), ended: true),
      .courtTap(Vec(x: 4.1, y: 22.1)))
    gesture = PracticeGesture(side: 0)
    _ = gesture.update(at: Vec(x: 4, y: 22))
    _ = gesture.update(at: Vec(x: 4, y: 18))
    XCTAssertNil(gesture.update(at: Vec(x: 4, y: 22), ended: true))
  }

  func testPlayerSwipeRecognizesAllFourShotsAndBothLateralDirections() {
    XCTAssertEqual(ShotSwipe.read(Vec(x: 2, y: -40)), ShotSwipe(kind: .line, lateral: 0))
    XCTAssertEqual(ShotSwipe.read(Vec(x: 0, y: 40)), ShotSwipe(kind: .lob, lateral: 0))
    for direction in [-1.0, 1.0] {
      XCTAssertEqual(ShotSwipe.read(Vec(x: direction * 35, y: -35)),
        ShotSwipe(kind: .cross, lateral: Int(direction)))
      XCTAssertEqual(ShotSwipe.read(Vec(x: direction * 40, y: 4)),
        ShotSwipe(kind: .angle, lateral: Int(direction)))
    }
    XCTAssertNil(ShotSwipe.read(Vec(x: 5, y: 7)))
  }

  func testShotSwipePreservesFootworkAndAimsInChosenDirectionForBothPlayers() {
    for side in 0...1 {
      for dx in [-35.0, 35.0] {
        var engine = PracticeEngine(settings: .init(local: true))
        engine.phase = .live
        engine.launch(1 - side, aim: Vec(x: 2, y: side == 0 ? 22 : 2), kind: .cross)
        let destination = Vec(x: 2, y: side == 0 ? 20 : 3)
        engine.move(side, to: destination)
        engine.selectShotSwipe(Vec(x: dx, y: -35), side: side)
        XCTAssertEqual(engine.players[side].destination, destination)
        XCTAssertEqual(engine.players[side].kind, .cross)
        let right = dx * (side == 0 ? 1 : -1) > 0
        XCTAssertEqual(engine.players[side].aim!.x > PracticeEngine.width / 2, right)
        engine.selectShotSwipe(Vec(x: 0, y: 40), side: side)
        XCTAssertEqual(engine.players[side].kind, .lob)
        XCTAssertEqual(engine.players[side].destination, destination)
      }
    }
  }

  func testLiveSwipePreviewMatchesCommittedAimAndDepthOnBothSides() throws {
    for side in 0...1 {
      var game = PracticeEngine(settings: .init(local: true))
      game.launch(1-side, aim: Vec(x: 2, y: side == 0 ? 22 : 2), kind: .cross)
      game.phase = .live
      var previous: Vec?
      for distance in [24.0, 48, 72] {
        let delta = Vec(x: distance, y: -distance)
        let target = try XCTUnwrap(game.swipeLanding(delta, side: side))
        game.selectShotSwipe(delta, side: side)
        XCTAssertEqual(game.players[side].aim, target)
        if let previous {
          XCTAssertTrue(side == 0 ? target.x > previous.x : target.x < previous.x)
          XCTAssertTrue(side == 0 ? target.y < previous.y : target.y > previous.y)
        }
        previous = target
      }
    }
  }

  func testOlderSurfaceSavesSelectTheMatchingArena() throws {
    for surface in CourtSurface.allCases {
      let data = try JSONEncoder().encode(PracticeSettings(surface: surface))
      let saved = try JSONDecoder().decode(PracticeSettings.self, from: data)
      XCTAssertNil(saved.venue)
      XCTAssertEqual(saved.matchVenue.surface, surface)
    }
    var night = PracticeSettings(surface: .hard)
    night.venue = .night
    let saved = try JSONDecoder().decode(PracticeSettings.self, from: JSONEncoder().encode(night))
    XCTAssertEqual(saved.matchVenue, .night)
  }

  func testDirectionalRunningKeepsShotAndStaysOnOwnCourt() {
    for side in 0...1 {
      var engine = PracticeEngine(settings: .init(local: true))
      engine.phase = .live
      engine.players[side].pos = Vec(x: 4, y: side == 0 ? 20 : 4)
      engine.choose(side, .lob)
      let aim = engine.players[side].aim
      engine.swipeCourt(side, delta: Vec(x: 3, y: 0))
      XCTAssertGreaterThan(engine.players[side].destination.x, 4)
      XCTAssertEqual(engine.players[side].kind, .lob)
      XCTAssertEqual(engine.players[side].aim, aim)
      engine.swipeCourt(side, delta: Vec(x: -100, y: side == 0 ? -100 : 100))
      XCTAssertEqual(engine.players[side].destination, PracticeEngine.own(side, engine.players[side].destination))
    }
  }

  func testForwardCourtSwipeApproachesAfterAnyShotWithoutSelectingLine() {
    var engine = PracticeEngine(settings: .init(allCourtTraining: false))
    engine.phase = .live
    engine.launch(0, aim: Vec(x: 1.5, y: 2), kind: .cross)
    engine.swipeCourt(0, delta: Vec(x: 0, y: -3))
    XCTAssertTrue(engine.followingApproach[0])
    XCTAssertTrue(engine.attacking[0])
    XCTAssertLessThan(engine.players[0].destination.y, 18)
    XCTAssertEqual(engine.flight?.kind, .cross)
    XCTAssertFalse(engine.flight!.trainingApproach)
  }

  func testYellowAndWhiteSwipesSnapExactlyWithoutAutomaticSplit() {
    var engine = PracticeEngine(settings: .init())
    engine.startRally()
    let yellow = engine.contactGuide(0)!
    engine.swipeCourt(0, delta: Vec(x: yellow.x - engine.players[0].pos.x, y: yellow.y - engine.players[0].pos.y))
    XCTAssertEqual(engine.players[0].destination, PracticeEngine.own(0, yellow))
    XCTAssertEqual(engine.tactics[0].splitSteps, 0)
    engine.time += 0.3
    engine.launch(0, aim: Vec(x: 2, y: 2), kind: .line)
    engine.followShot(0)
    let white = engine.recoveryGuide(0)!
    engine.apply(.guidedMove(.recover), side: 0)
    XCTAssertEqual(engine.players[0].destination, white)
    XCTAssertFalse(engine.attacking[0])
    XCTAssertEqual(engine.tactics[0].splitSteps, 0)
  }

  func testTapsBounceWithCooldownAndNeverChangeMovementOrAim() {
    var engine = PracticeEngine(settings: .init())
    engine.startRally()
    engine.choose(0, .line)
    let destination = engine.players[0].destination
    let aim = engine.players[0].aim
    engine.tapCourt(0, at: Vec(x: 0, y: 14))
    XCTAssertNotNil(engine.splitProgress(0))
    XCTAssertEqual(engine.tactics[0].splitSteps, 1)
    for _ in 0..<5 { engine.tapCourt(0, at: Vec(x: 0, y: 14)) }
    XCTAssertEqual(engine.tactics[0].splitSteps, 1)
    engine.time += 0.3
    engine.selectShotSwipe(.zero, side: 0)
    XCTAssertEqual(engine.tactics[0].splitSteps, 2)
    XCTAssertEqual(engine.players[0].destination, destination)
    XCTAssertEqual(engine.players[0].aim, aim)
  }

  func testSplitTimingIsRewardedNearOpponentContactAndNeverAutomatic() {
    var engine = PracticeEngine(settings: .init())
    engine.phase = .live
    engine.launch(0, aim: Vec(x: 2, y: 2), kind: .cross, trainingApproach: true)
    engine.players[1].pos = engine.flight!.contact
    engine.players[1].destination = engine.players[1].pos
    let entry = engine.contactWindow(1)!.entry
    engine.flight!.elapsed = entry * engine.flight!.duration - 0.2
    XCTAssertEqual(engine.coachCue, .split(false))
    engine.beginSplit(0)
    XCTAssertTrue(engine.splitTimed[0])
    XCTAssertEqual(engine.tactics[0].timedSplits, 1)
    XCTAssertEqual(engine.coachCue, .split(true))
    var untouched = PracticeEngine(settings: .init())
    untouched.phase = .live
    untouched.attacking[0] = true
    untouched.launch(0, aim: Vec(x: 2, y: 2), kind: .cross, trainingApproach: true)
    untouched.players[1].pos = untouched.flight!.contact
    for _ in 0..<500 { untouched.step(1 / 120, random: { 0.5 }) }
    XCTAssertEqual(untouched.tactics[0].splitSteps, 0)
  }

  func testInactiveCourtIgnoresPlayInputs() {
    var engine = PracticeEngine(settings: .init())
    let player = engine.players[0]
    engine.tapCourt(0, at: .zero)
    engine.swipeCourt(0, delta: Vec(x: 0, y: -4))
    engine.selectShotSwipe(Vec(x: 0, y: -40), side: 0)
    XCTAssertEqual(engine.players[0].destination, player.destination)
    XCTAssertEqual(engine.players[0].kind, player.kind)
    XCTAssertEqual(engine.tactics[0].splitSteps, 0)
  }

  func testLineChosenWhileRunningUsesActualContactPosition() {
    var engine = PracticeEngine(settings: .init(allCourtTraining: false))
    engine.phase = .live
    engine.players[0].pos = Vec(x: 2, y: 24)
    engine.launch(1, aim: Vec(x: 6, y: 22.9), kind: .cross)
    engine.selectShotSwipe(Vec(x: 0, y: -40), side: 0)
    engine.players[0].pos = Vec(x: 6, y: 24)
    engine.flight = BallFlight(from: Vec(x: 2, y: 1), landing: Vec(x: 6, y: 22.9),
      contact: engine.players[0].pos, duration: 2, hitter: 1, fault: nil, explanation: "", loft: 1)
    engine.returnBall(0, volley: false, random: { 0.99 })
    XCTAssertEqual(engine.flight!.landing.x, 6, accuracy: 0.001)
    XCTAssertNil(engine.flight!.fault)
  }
}
