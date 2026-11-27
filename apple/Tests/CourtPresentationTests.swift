import XCTest
import simd
@testable import TennisCore

final class CourtPresentationTests: XCTestCase {
  func testSplitLandingWidensFeetAndAbsorbsWeightBeforeReturningUpright() {
    for side in 0...1 {
      var game = PracticeEngine(settings:.init(local:true))
      game.phase = .live
      var motion = AthleteMotion()
      let ready = motion.sample(game:game,side:side,hit:false,dt:0,reduceMotion:false)
      game.splitStarted[side] = game.time
      func pose(_ t: Double) -> AthletePose {
        game.time = t + game.splitStarted[side]
        return motion.sample(game:game,side:side,hit:false,dt:PointReplay.tick,reduceMotion:false)
      }
      let airborne = pose(0.09), landed = pose(0.204), recovered = pose(0.45)
      XCTAssertGreaterThan(airborne[.leftShoe].y, ready[.leftShoe].y + 0.09)
      XCTAssertEqual(landed[.leftShoe].y, ready[.leftShoe].y,accuracy:0.001)
      XCTAssertGreaterThan(simd_distance(landed[.leftShoe],landed[.rightShoe]),
                           simd_distance(ready[.leftShoe],ready[.rightShoe]) + 0.08)
      XCTAssertLessThan(landed[.head].y,ready[.head].y - 0.035)
      XCTAssertEqual(recovered[.head].y,ready[.head].y,accuracy:0.01)
    }
  }

  func testGazeTracksInEachPlayersOwnFrameAndReturnsToRest() {
    for side in 0...1 {
      var game = PracticeEngine(settings:.init(local:true))
      game.phase = .live
      let pos = game.players[side].pos
      let sign = side == 0 ? 1.0 : -1.0
      game.ball = Vec(x:pos.x+sign*3,y:pos.y-sign*2)
      var motion = AthleteMotion()
      var pose = AthletePose()
      for _ in 0..<90 { pose = motion.sample(game:game,side:side,hit:false,dt:PointReplay.tick,reduceMotion:false) }
      XCTAssertGreaterThan(pose.gaze.x,0.5)
      XCTAssertLessThan(pose.gaze.y,0)
      game.phase = .ready
      for _ in 0..<90 { pose = motion.sample(game:game,side:side,hit:false,dt:PointReplay.tick,reduceMotion:false) }
      XCTAssertEqual(pose.gaze.x,0,accuracy:0.001)
    }
  }

  func testServeShowsTrophyThenTucksTossArmAndKeepsImpact() throws {
    var game = TrainingFeed.serve(.wide,surface:.hard)
    game.servePreparation?.requested = true
    var motion = CourtPerformance(game:game)
    for _ in 0..<900 where game.contactSerial == 0 {
      game.step(PointReplay.tick,random:{ 0.99 })
      motion.update(game:game,dt:PointReplay.tick)
    }
    let clip = motion.replay
    let strike = try XCTUnwrap(clip.strikes.last)
    let trophy = try XCTUnwrap(clip.frame(at:strike.time-0.30)).near
    let hit = try XCTUnwrap(clip.frame(at:strike.time)).near
    XCTAssertGreaterThan(trophy[.leftShoulder].y,trophy[.rightShoulder].y+0.09)
    XCTAssertGreaterThan(trophy[.leftHand].y, trophy[.head].y)
    XCTAssertLessThan(hit[.leftHand].y,hit[.head].y)
    XCTAssertEqual(simd_distance(hit[.strings],strike.point),0,accuracy:0.0001)
  }

  func testGroundBounceCreatesOneScrubbableMarkAndNetHasNone() throws {
    for surface in CourtSurface.allCases {
      for fault in [nil, "wide", "net"] as [String?] {
        var game = PracticeEngine(settings:.init(local:true,surface:surface))
        game.phase = .live
        var motion = CourtPerformance(game:game)
        game.launch(1,aim:Vec(x:0.1,y:19),kind:.cross,fault:fault)
        let original = try XCTUnwrap(game.flight)
        motion.update(game:game,dt:PointReplay.tick)
        for _ in 0..<720 where game.needsSimulation {
          game.step(PointReplay.tick,random:{0.99}); motion.update(game:game,dt:PointReplay.tick)
        }
        let clip = motion.replay.finishingShot
        if fault == "net" { XCTAssertNil(clip.lastShotBounceTime); continue }
        XCTAssertEqual(clip.bounceTimes.count,1)
        let t = try XCTUnwrap(clip.lastShotBounceTime)
        let frame = try XCTUnwrap(clip.frame(at:t))
        XCTAssertEqual(frame.bounce?.position,original.landing)
        XCTAssertEqual(frame.bounce?.surface,surface)
        XCTAssertNil(clip.frame(at:t - PointReplay.tick)?.bounce)
        XCTAssertGreaterThan(t,try XCTUnwrap(clip.strikes.last).time)
      }
    }
  }

  func testPracticeRecordsPersistWithoutCountingAbandonedAttempts() throws {
    var record = TacticalPracticeRecord()
    for success in [true, true, false, true] { record.finish(success:success) }
    let restored = try JSONDecoder().decode(TacticalPracticeRecord.self,from:JSONEncoder().encode(record))
    XCTAssertEqual(restored.attempts,4)
    XCTAssertEqual(restored.successes,3)
    XCTAssertEqual(restored.bestStreak,2)
    XCTAssertEqual(restored.streak,1)
  }
}
