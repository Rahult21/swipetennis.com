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

extension CourtPresentationTests {
  func testStudioUsesActualContactsAndPreservesNaturalReach() throws {
    for stroke in StudioStroke.allCases {
      let clip = try XCTUnwrap(StrokeStudioClip(stroke),stroke.rawValue)
      let contact = try XCTUnwrap(clip.frame(clip.contactTime))
      XCTAssertGreaterThan(clip.duration,0.85,stroke.rawValue)
      XCTAssertEqual(simd_distance(contact.near[.strings],contact.ball),0,accuracy:0.001,stroke.rawValue)
      for t in stride(from:0.0,through:clip.duration,by:PointReplay.tick) {
        let f = try XCTUnwrap(clip.frame(t))
        for p in [f.near,f.far] {
          XCTAssertLessThanOrEqual(simd_distance(p[.rightShoulder],p[.grip]),0.681,stroke.rawValue)
          XCTAssertLessThanOrEqual(simd_distance(p[.leftShoulder],p[.leftHand]),0.681,stroke.rawValue)
          XCTAssertEqual(simd_distance(p[.strings],p[.grip]),0.49,accuracy:0.001,stroke.rawValue)
        }
      }
    }
  }
  func testQuickStartShowsAnActualRunAndTwoDifferentShotDepths() throws {
    let run = try XCTUnwrap(StrokeStudioClip(.chase))
    let start = try XCTUnwrap(run.frame(0)).near, hit = try XCTUnwrap(run.frame(run.contactTime)).near
    let hips = (hit[.leftHip]+hit[.rightHip]-start[.leftHip]-start[.rightHip])*0.5
    XCTAssertGreaterThan(hips.x,3.5, "The running lesson should show several real lateral strides.")

    func opponentLanding(_ stroke: StudioStroke) throws -> Vec {
      let clip = try XCTUnwrap(StrokeStudioClip(stroke))
      let returnFlight = try XCTUnwrap(clip.recording.decisions[1]?.game.flight)
      XCTAssertEqual(returnFlight.hitter,0)
      return returnFlight.landing
    }
    let deep = try opponentLanding(.forehand), short = try opponentLanding(.backhand)
    XCTAssertGreaterThan(short.y-deep.y,2.0, "The quick-start diagonal and drive should teach visibly different depths.")
  }

  func testServeDropsTheHeadOfTheRacketThenExtendsThroughTheToss() throws {
    let clip = try XCTUnwrap(StrokeStudioClip(.serve))
    func pose(_ relative: Double) throws -> AthletePose { try XCTUnwrap(clip.frame(clip.contactTime+relative)).near }
    let loaded = try pose(-0.30), dropped = try pose(-0.145), hit = try pose(0), finish = try pose(0.17)
    XCTAssertGreaterThan(loaded[.strings].y,loaded[.grip].y+0.24)
    XCTAssertLessThan(dropped[.strings].y,dropped[.grip].y-0.25)
    XCTAssertGreaterThan(hit[.strings].y,hit[.grip].y+0.35)
    let elbow = hit[.rightElbow]
    let angle = acos(simd_dot(simd_normalize(hit[.rightShoulder]-elbow),simd_normalize(hit[.grip]-elbow)))
    XCTAssertGreaterThan(angle,145*Float.pi/180)
    XCTAssertGreaterThan(hit[.leftShoe].y,0.13)
    XCTAssertLessThan(hit[.leftShoe].y,0.30)
    XCTAssertGreaterThan(finish[.rightShoe].y,finish[.leftShoe].y+0.10)
    XCTAssertGreaterThan(loaded.shoeYaw.y,loaded.shoeYaw.x+0.35)
    for kind: CapturedStroke.Kind in [.serve,.smash,.forehand,.backhand,.volley] {
      let sample = try XCTUnwrap(CapturedStroke.sample(kind,at:-0.1))
      XCTAssertGreaterThan(simd_length(sample.elbow),0.04)
      XCTAssertTrue(sample.chestYaw.isFinite)
    }
  }

}
