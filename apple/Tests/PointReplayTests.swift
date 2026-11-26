import XCTest
import simd
@testable import TennisCore

final class PointReplayTests: XCTestCase {
  private let tick = PointReplay.tick

  func testAPlantedShoeStaysOnCourtDuringRunsAndAdjustmentSteps() {
    for facing: Float in [-1, 1] {
      var feet = CourtFootwork()
      var centre = CourtPoint3D(2, 0, 2)
      var liftedLeft = false, liftedRight = false
      let velocity = CourtPoint3D(2 * facing, 0, 3.5 * facing)
      feet.advance(centre: centre, velocity: .zero, destination: centre,
        facing: facing, strideBias: .zero, dt: 0)
      for frame in 0..<300 {
        let moving = frame < 180
        let left = feet.left, right = feet.right
        if moving { centre += velocity * Float(tick) }
        feet.advance(centre: centre, velocity: moving ? velocity : .zero,
          destination: moving ? centre + velocity : centre,
          facing: facing, strideBias: .zero, dt: Float(tick))
        XCTAssertTrue((feet.left == left && feet.left.y == 0) || (feet.right == right && feet.right.y == 0))
        liftedLeft = liftedLeft || feet.left.y > 0.08
        liftedRight = liftedRight || feet.right.y > 0.08
      }
      XCTAssertTrue(liftedLeft && liftedRight)
      XCTAssertEqual(feet.left.y, 0)
      XCTAssertEqual(feet.right.y, 0)
      XCTAssertLessThan(simd_distance(centre, (feet.left + feet.right) / 2), 0.17)
    }
  }

  func testApproachAndVolleyReplayRetainsBothRacketsAtEveryActualImpact() throws {
    var game = PracticeEngine(settings: .init())
    game.phase = .live
    game.players[0].pos = Vec(x: 2, y: 23.4)
    game.players[1].pos = Vec(x: 6.23, y: -0.8)
    for i in 0...1 { game.players[i].destination = game.players[i].pos }
    var motion = CourtPerformance(game: game)
    game.launch(1, aim: Vec(x: 2.35, y: 22.3), kind: .cross)
    motion.update(game: game, dt: tick)
    game.choose(0, .line)
    game.apply(.guidedMove(.receive), side: 0)
    for _ in 0..<2400 where game.phase == .live && game.contactSerial < 4 {
      let previous = try XCTUnwrap(game.flight)
      let serial = game.contactSerial
      game.step(tick, random: { 0.99 })
      motion.update(game: game, dt: tick)
      if serial != game.contactSerial {
        let impact = try XCTUnwrap(game.flight?.strikeOrigin)
        var incoming = previous
        incoming.elapsed += tick
        XCTAssertLessThan(simd_distance(impact, incoming.worldBall(at: incoming.progress)), 0.00001)
        if game.contactSerial == 2 {
          XCTAssertFalse(game.followingApproach[0])
          game.apply(.guidedMove(.approach), side: 0)
          XCTAssertTrue(game.followingApproach[0])
        }
        if game.contactSerial == 3 { game.apply(.guidedMove(.receive), side: 0) }
      }
    }
    let clip = motion.replay
    XCTAssertTrue(clip.canPlay)
    XCTAssertEqual(game.flight?.stroke, .volley)
    XCTAssertEqual(clip.strikes.map(\.hitter), [1, 0, 1, 0])
    for hit in clip.strikes {
      let frame = try XCTUnwrap(clip.frame(at: hit.time))
      let athlete = hit.hitter == 0 ? frame.near : frame.far
      XCTAssertLessThan(simd_distance(frame.ball, hit.point), 0.00001)
      XCTAssertLessThan(simd_distance(athlete[.strings], frame.ball), 0.00001)
    }
    let penultimate = try XCTUnwrap(clip.strikes.dropLast().last)
    XCTAssertEqual(clip.opening, max(0, penultimate.time - 0.65))
    let recorded = clip.frames[45], next = clip.frames[46]
    let halfway = try XCTUnwrap(clip.frame(at: 45 * tick + tick * PointReplay.speed))
    XCTAssertLessThan(simd_distance(halfway.ball, (recorded.ball + next.ball) / 2), 0.00001)
    XCTAssertEqual(game.tactics[0].volleys, 1)
  }

  func testForehandStartsAtTheHipsAndFinishesAcrossTheBody() throws {
    var game = PracticeEngine(settings: .init(local: true))
    game.phase = .live
    game.players[0].pos = Vec(x: 2.0, y: 23.4)
    game.players[0].destination = game.players[0].pos
    var motion = CourtPerformance(game: game)
    game.launch(1, aim: Vec(x: 2.55, y: 22.3), kind: .cross)
    motion.update(game: game, dt: tick)
    for _ in 0..<600 {
      game.step(tick, random: { 0.99 })
      motion.update(game: game, dt: tick)
      if motion.replay.strikes.count == 2, (game.flight?.elapsed ?? 0) > 0.25 { break }
    }
    let clip = motion.replay
    let hit = try XCTUnwrap(clip.strikes.first(where: { $0.hitter == 0 }))
    func pose(_ relative: Double) throws -> AthletePose {
      try XCTUnwrap(clip.frame(at: hit.time + relative)).near
    }
    func rotation(_ p: AthletePose, _ right: BodyJoint, _ left: BodyJoint) -> Float {
      let axis = p[right] - p[left]
      return atan2(-axis.z, axis.x)
    }
    let loaded = try pose(-0.17), uncoiling = try pose(-0.10), finish = try pose(0.22)
    XCTAssertGreaterThan(rotation(uncoiling, .rightHip, .leftHip) - rotation(loaded, .rightHip, .leftHip), 0.1)
    XCTAssertEqual(rotation(uncoiling, .rightShoulder, .leftShoulder), rotation(loaded, .rightShoulder, .leftShoulder), accuracy: 0.02)
    XCTAssertGreaterThan(loaded[.strings].x, loaded[.rightShoulder].x)
    XCTAssertLessThan(finish[.strings].x, finish[.leftShoulder].x)
    XCTAssertGreaterThan(finish[.strings].y, hit.point.y)
  }

  func testTwoServeFaultsKeepTossesAndLandingsAndSkipIdleTime() throws {
    var game = PracticeEngine(settings: .init(local: true))
    game.scoring = PracticeScore(format: .tennis, firstServer: 0)
    game.start()
    var motion = CourtPerformance(game: game)
    for attempt in 1...2 {
      let count = motion.replay.frames.count
      for _ in 0..<200 {
        game.step(tick)
        motion.update(game: game, dt: tick)
      }
      XCTAssertEqual(count, motion.replay.frames.count)
      game.requestServe(0)
      var sawBounce = false
      for _ in 0..<1500 {
        game.step(tick, random: { 0 })
        motion.update(game: game, dt: tick)
        if game.pointResolution?.elapsed == 0, let impact = game.pointResolution?.impact {
          sawBounce = true
          XCTAssertEqual(game.worldBall, impact.point.world(height: Float(impact.height)))
        }
        if game.showsPointResult || (attempt == 1 && game.servePreparation?.number == 2) { break }
      }
      XCTAssertTrue(sawBounce)
    }
    XCTAssertTrue(game.showsPointResult)
    XCTAssertEqual(motion.replay.strikes.count, 2)
    for hit in motion.replay.strikes {
      let frame = try XCTUnwrap(motion.replay.frame(at: hit.time))
      XCTAssertEqual(frame.near[.strings].y, 2.73, accuracy: 0.0001)
      XCTAssertLessThan(simd_distance(frame.ball, frame.near[.strings]), 0.00001)
    }
    game.start()
    XCTAssertFalse(CourtPerformance(game: game).replay.canPlay)
  }
}
