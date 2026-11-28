import XCTest
import simd
@testable import TennisCore

final class PointReplayTests: XCTestCase {
  private let tick = PointReplay.tick

  func testLowGroundstrokesKeepTheLegsLoadedThroughContact() throws {
    for shot in [StudioStroke.forehand,.backhand] {
      let clip = try XCTUnwrap(StrokeStudioClip(shot))
      let impact = try XCTUnwrap(clip.frame(clip.contactTime)).near
      let finish = try XCTUnwrap(clip.frame(clip.contactTime+0.15)).near
      XCTAssertLessThan(impact[.strings].y,0.70)
      let thigh = simd_normalize(impact[.rightHip]-impact[.rightKnee])
      let shin = simd_normalize(impact[.rightShoe]-impact[.rightKnee])
      let kneeFlexion = Float.pi-acos(min(1,max(-1,simd_dot(thigh,shin))))
      XCTAssertGreaterThan(kneeFlexion,Float.pi/6)
      XCTAssertGreaterThan(finish[.rightHip].y-impact[.rightHip].y,0.06)
    }
  }

  func testRunCadenceAndSupportsThroughAcceleration() throws {
    XCTAssertNotNil(RunningStride.sample(phase:0.5))
    for facing: Float in [-1,1] { for heading: Float in [-1.56,0,0.72,1.56] {
      var feet = CourtFootwork(), center = CourtPoint3D.zero
      let direction = CourtPoint3D(sin(heading)*facing,0,-cos(heading)*facing)
      let dt = Float(tick)
      feet.advance(centre:center,velocity:.zero,destination:center,facing:facing,strideBias:.zero,dt:0)
      var steps = 0, airborne = 0, supported = 0
      for i in 0..<360 {
        let speed: Float = min(9,Float(i)*dt*12)
        let previous = feet.left
        center += direction*speed*dt
        feet.advance(centre:center,velocity:direction*speed,destination:center+direction*3,
                     facing:facing,strideBias:.zero,dt:dt)
        if i >= 120 {
          if previous.y > 0.015 && feet.left.y <= 0.015 { steps += 1 }
          if feet.left.y < 0.0005 && previous.y < 0.0005 {
            XCTAssertLessThan(simd_distance(feet.left,previous),0.003)
            supported += 1
          }
          if min(feet.left.y,feet.right.y)>0.035 { airborne += 1 }
        }
      }
      XCTAssertTrue((4...6).contains(steps))
      XCTAssertGreaterThan(supported,35)
      XCTAssertGreaterThan(airborne,20)
    } }
  }

  func testFreeWristTravelsContinuouslyAtReplaySamplingRate() throws {
    for stroke in StudioStroke.allCases {
      let clip = try XCTUnwrap(StrokeStudioClip(stroke))
      var prior = try XCTUnwrap(clip.frame(0)).near
      for t in stride(from:tick,to:clip.duration,by:tick) {
        let next = try XCTUnwrap(clip.frame(t)).near
        XCTAssertLessThan(simd_distance(next[.leftHand],prior[.leftHand]),0.13,
                          "\(stroke.rawValue) free wrist jumped at \(t)")
        if stroke == .serve { XCTAssertLessThan(simd_distance(next[.grip],prior[.grip]),0.16) }
        prior = next
      }
    }
  }

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
          game.swipeCourt(0, delta: Vec(x: 0, y: -2))
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
    var ending = clip.finishingShot
    XCTAssertEqual(ending.strikes.map(\.hitter), [0])
    XCTAssertLessThanOrEqual(try XCTUnwrap(ending.strikes.last?.time), 0.55 + tick)
    XCTAssertEqual(ending.frames.last?.ball, clip.frames.last?.ball)
    ending.appendHandshake()
    let shake = try XCTUnwrap(ending.frame(at: try XCTUnwrap(ending.ceremonyStart) + 1.5))
    XCTAssertLessThan(simd_distance(shake.near[.grip], shake.far[.grip]), 0.002)
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
    game.launch(1, aim: Vec(x: 2.55, y: 23.4-PracticeEngine.bounceSpacing), kind: .cross)
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
    let waiting = try pose(-0.45), contact = try pose(0)
    XCTAssertGreaterThan(waiting[.leftHip].y - loaded[.leftHip].y, 0.13)
    XCTAssertGreaterThan(contact[.leftHip].y - loaded[.leftHip].y, 0.11)
    // Compare recovery with the upright stance before the adjustment step.
    XCTAssertEqual(finish[.leftHip].y, try pose(-0.70)[.leftHip].y, accuracy: 0.03)
    let upright = clip.frames.filter { $0.near[.leftHip].y >= waiting[.leftHip].y - 0.04 }
    XCTAssertGreaterThan(Double(upright.count) / Double(clip.frames.count), 0.75)
    XCTAssertGreaterThan(contact.heelPitch, loaded.heelPitch + 0.10)
    XCTAssertGreaterThan(finish[.strings].y, loaded[.strings].y)
    XCTAssertGreaterThan(rotation(uncoiling, .rightHip, .leftHip) - rotation(loaded, .rightHip, .leftHip), 0.1)
    let shouldersAtLoad = rotation(loaded,.rightShoulder,.leftShoulder)
    XCTAssertLessThan(shouldersAtLoad,-1.48) // Close to parallel to the singles sideline.
    let hipsOpening = rotation(uncoiling,.rightHip,.leftHip)-rotation(loaded,.rightHip,.leftHip)
    let shouldersOpening = rotation(uncoiling,.rightShoulder,.leftShoulder)-shouldersAtLoad
    XCTAssertGreaterThan(shouldersOpening,0.08)
    XCTAssertGreaterThan(hipsOpening,shouldersOpening)
    XCTAssertGreaterThan(loaded[.strings].x, loaded[.rightShoulder].x)
    XCTAssertLessThan(finish[.strings].x, finish[.leftShoulder].x)
    XCTAssertGreaterThan(finish[.strings].y, hit.point.y)
  }

  func testBothForehandsSetTheElbowHighDropTheHeadAndWrapAfterExtension() throws {
    for side in 0...1 {
      let sign: Float = side == 0 ? 1 : -1
      var game = PracticeEngine(settings:.init(local:true,surface:.hard,allCourtTraining:false))
      game.phase = .live
      game.players[side].pos = Vec(x:4.115,y:side == 0 ? 22.6 : PracticeEngine.length-22.6)
      game.players[1-side].pos = Vec(x:4.115,y:side == 0 ? 1 : PracticeEngine.length-1)
      for index in 0...1 { game.players[index].destination = game.players[index].pos }
      var performance = CourtPerformance(game:game)
      game.launch(1-side,aim:Vec(x:4.115+Double(sign)*2.65,y:side == 0 ? 21.5 : PracticeEngine.length-21.5),kind:.cross)
      game.apply(.guidedMove(.receive),side:side)
      for _ in 0..<420 {
        game.step(tick,random:{0.8})
        performance.update(game:game,dt:tick)
        if game.flight?.hitter == side && (game.flight?.elapsed ?? 0) > 0.34 { break }
      }
      let clip = performance.replay, hit = try XCTUnwrap(clip.strikes.last)
      XCTAssertEqual(hit.hitter,side)
      func pose(_ time: Double) throws -> AthletePose {
        let frame = try XCTUnwrap(clip.frame(at:hit.time+time))
        return side == 0 ? frame.near : frame.far
      }
      let set = try pose(-0.265), low = try pose(-0.085), contact = try pose(0)
      let through = try pose(0.065), finish = try pose(0.245)
      let shoulders = simd_normalize(set[.rightShoulder]-set[.leftShoulder])
      XCTAssertGreaterThan(abs(shoulders.z),0.96)
      let upper = simd_normalize(set[.rightElbow]-set[.rightShoulder])
      XCTAssertLessThan(abs(upper.y),0.24)
      XCTAssertGreaterThan((set[.strings].z-set[.rightShoulder].z)*sign,0.5)
      XCTAssertGreaterThan(set[.strings].y-set[.grip].y,0.20)
      XCTAssertGreaterThan(set[.strings].y-low[.strings].y,0.8)
      XCTAssertGreaterThan((contact[.rightHip].y-low[.rightHip].y),0.035)
      XCTAssertLessThan(simd_distance(contact[.strings],hit.point),0.0001)
      // The head must keep moving into and out of contact on a full drive.
      let before = try pose(-1.0/60), after = try pose(1.0/60)
      XCTAssertGreaterThan(60*simd_distance(before[.strings],contact[.strings]),8.0)
      XCTAssertGreaterThan(60*simd_distance(contact[.strings],after[.strings]),8.0)
      XCTAssertGreaterThan((contact[.strings].z-through[.strings].z)*sign,0.08)
      XCTAssertGreaterThan(through[.strings].y,contact[.strings].y+0.16)
      XCTAssertLessThan((finish[.grip].x-finish[.leftShoulder].x)*sign,0)
      XCTAssertGreaterThan(finish[.grip].y,finish[.leftShoulder].y)
    }
  }

  func testBothBackhandsCoilThenExtendThroughImpactAndFinishHigh() throws {
    for side in 0...1 {
      let sign: Float = side == 0 ? 1 : -1
      var game = PracticeEngine(settings: .init(local: true))
      game.phase = .live
      let x = 4.0, depth = side == 0 ? 23.4 : PracticeEngine.length-23.4
      game.players[side].pos = Vec(x: x, y: depth)
      game.players[side].destination = game.players[side].pos
      var motion = CourtPerformance(game: game)
      game.launch(1-side, aim: Vec(x: x-Double(sign)*0.58, y: depth-Double(sign)*PracticeEngine.bounceSpacing), kind: .cross)
      motion.update(game: game, dt: tick)
      for _ in 0..<800 {
        game.step(tick, random: { 0.99 }); motion.update(game: game, dt: tick)
        if game.flight?.hitter == side && (game.flight?.elapsed ?? 0) >= 0.23 { break }
      }
      let clip = motion.replay
      let hit = try XCTUnwrap(clip.strikes.first { $0.hitter == side })
      func pose(_ t: Double) throws -> AthletePose {
        let frame = try XCTUnwrap(clip.frame(at: hit.time+t))
        return side == 0 ? frame.near : frame.far
      }
      func yaw(_ p: AthletePose, hips: Bool = false) -> Float {
        let axis = hips ? p[.rightHip]-p[.leftHip] : p[.rightShoulder]-p[.leftShoulder]
        return atan2(-axis.z*sign, axis.x*sign)
      }
      let coil = try pose(-0.21), opening = try pose(-0.115), impact = try pose(0), finish = try pose(0.22)
      let waiting = try pose(-0.45)
      XCTAssertGreaterThan(waiting[.leftHip].y-opening[.leftHip].y, 0.12)
      XCTAssertGreaterThan(impact[.leftHip].y-opening[.leftHip].y, 0.10)
      XCTAssertEqual(finish[.leftHip].y, waiting[.leftHip].y, accuracy: 0.03)
      XCTAssertGreaterThan(yaw(coil), 1.15)
      XCTAssertGreaterThan(yaw(coil)-yaw(coil, hips: true), 0.55)
      XCTAssertLessThan(yaw(opening, hips: true), yaw(coil, hips: true)-0.17)
      XCTAssertGreaterThan(yaw(opening), 1.15)
      XCTAssertLessThan(yaw(finish), -0.65)
      XCTAssertLessThan(simd_distance(impact[.strings], hit.point), 0.0001)
      for p in [coil,opening,impact,finish] { XCTAssertEqual(simd_distance(p[.leftHand],p[.grip]), 0.095, accuracy: 0.002) }
      XCTAssertGreaterThan((finish[.strings].x-finish[.rightShoulder].x)*sign, 0.12)
      XCTAssertGreaterThan(finish[.strings].y, hit.point.y)
    }
  }

  func testBothPlayersStandTallAtBaselineAndNetWhileWaitingAndBetweenPoints() throws {
    var game = PracticeEngine(settings: .init())
    var motion = CourtPerformance(game: game)
    func snapshot() -> AthletePose { motion.update(game: game, dt: tick); return motion.frame!.near }
    let idle = snapshot()
    XCTAssertEqual(idle.heelPitch, 0)
    game.start()
    game.servePreparation!.elapsed = 0.4
    let ready = snapshot()
    XCTAssertLessThan(ready[.head].y, idle[.head].y - 0.03, "The receiver cushions the opening hop")
    XCTAssertEqual(ReceiverFootwork.pose(game: game, side: game.scoring.server, reduceMotion: false).hips, .zero)
    XCTAssertLessThan(ready.heelPitch, 0.03)
    game.phase = .live
    game.players[0].pos.y = PracticeEngine.net + 2
    game.players[0].destination = game.players[0].pos
    for _ in 0..<60 { _ = snapshot() }
    for p in [motion.frame!.near,motion.frame!.far] {
      XCTAssertEqual(p[.head].y, idle[.head].y, accuracy: 0.02)
      let thigh = simd_normalize(p[.leftHip] - p[.leftKnee])
      let shin = simd_normalize(p[.leftKnee] - p[.leftShoe])
      XCTAssertGreaterThan(simd_dot(thigh, shin), cos(Float.pi/8), "Waiting knees flex less than 22.5 degrees")
    }
    game.launch(1, aim: Vec(x: 1, y: 20), kind: .cross)
    _ = snapshot()
    game.end(0, reason: "", tip: "")
    for _ in 0..<96 { game.step(tick); _ = snapshot() }
    let last = try XCTUnwrap(motion.replay.frames.last)
    for p in [last.near,last.far] {
      XCTAssertEqual(p.heelPitch, 0)
      XCTAssertEqual(p[.head].y, idle[.head].y, accuracy: 0.025)
      XCTAssertLessThan(p[.strings].y, p[.rightHip].y)
    }
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
        game.swingAtTestToss(0)
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
      let loaded = try XCTUnwrap(motion.replay.frame(at: hit.time - 0.30)).near
      let rising = try XCTUnwrap(motion.replay.frame(at: hit.time - 0.08)).near
      XCTAssertLessThan(min(loaded[.leftShoe].y, loaded[.rightShoe].y), 0.09)
      XCTAssertGreaterThan(rising[.leftHip].y - rising[.leftShoe].y,
        loaded[.leftHip].y - loaded[.leftShoe].y + 0.13)
    }
    game.start()
    XCTAssertFalse(CourtPerformance(game: game).replay.canPlay)
  }
}
