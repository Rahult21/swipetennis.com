import XCTest
import simd
@testable import TennisCore

final class ReceiverAndSwingTests: XCTestCase {
  func testReceiveRhythmOnBothEndsAndBothServes() throws {
    for server in 0...1 {
      for number in 1...2 {
        var game = PracticeEngine(settings: .init(local: true))
        game.scoring = PracticeScore(format: .tiebreak, firstServer: server)
        game.start(random: { 0.6 })
        game.servePreparation?.number = number
        let receiver = 1 - server
        func sample(_ elapsed: Double, reduced: Bool = false) -> ReceiverFootwork {
          game.servePreparation?.elapsed = elapsed
          return ReceiverFootwork.pose(game: game, side: receiver, reduceMotion: reduced)
        }
        let hop = sample(0.22), low = sample(0.60)
        XCTAssertGreaterThan(min(hop.left.y, hop.right.y), 0.06)
        XCTAssertGreaterThan(hop.hips.y - low.hips.y, 0.15)
        XCTAssertGreaterThan(low.lean, 0.12)
        XCTAssertGreaterThan(low.right.x - low.left.x, 0.15)
        XCTAssertGreaterThan(sample(0.60).left.y, 0.035)
        XCTAssertGreaterThan(sample(0.92).right.y, 0.035)
        XCTAssertEqual(sample(0.22, reduced: true).left, .zero)
        XCTAssertEqual(ReceiverFootwork.pose(game: game, side: server, reduceMotion: false).hips, .zero)
      }
    }
  }

  func testForwardSplitStraddlesServiceContactWithoutAnAutomaticInput() throws {
    for server in 0...1 {
      for power in [false, true] where !power || server == 0 {
        var game = PracticeEngine(settings: .init(local: true))
        game.scoring = PracticeScore(format: .tiebreak, firstServer: server)
        game.start(random: { 0.6 })
        game.servePreparation?.elapsed = 1.5
        game.servePreparation?.settled = 1.5
        if power { game.queuedPower = .ace }
        game.requestServe(server)
        let receiver = 1 - server
        let split = game.splitStarted[receiver]
        var motion = CourtPerformance(game: game)
        var before: AthletePose?, last: AthletePose?
        var impact: AthletePose?, landed: AthletePose?
        var biggestLandingStep: Float = 0
        for _ in 0..<200 {
          game.swingAtTestToss(server)
          let clock = game.servePreparation?.tossElapsed
          game.step(PointReplay.tick, random: { 0.90 })
          motion.update(game: game, dt: PointReplay.tick)
          let frame = try XCTUnwrap(motion.frame)
          let p = receiver == 0 ? frame.near : frame.far
          if let clock, clock < 0.56 { before = p }
          if let ball = game.flight, ball.serve {
            if impact == nil { impact = p }
            if (0.10...0.18).contains(ball.elapsed), let last {
              biggestLandingStep = max(biggestLandingStep, simd_distance(last[.rightShoe], p[.rightShoe]))
            }
            if ball.elapsed > 0.16 { landed = p; break }
          }
          last = p
        }
        let set = try XCTUnwrap(before), air = try XCTUnwrap(impact), landing = try XCTUnwrap(landed)
        let sign: Float = receiver == 0 ? -1 : 1
        for foot in [BodyJoint.leftShoe, .rightShoe] {
          XCTAssertGreaterThan(air[foot].y - landing[foot].y, 0.055)
          XCTAssertGreaterThan((landing[foot].z - set[foot].z)*sign, 0.10)
        }
        XCTAssertLessThan(biggestLandingStep, 0.055)
        XCTAssertEqual(game.splitStarted[receiver], split)
      }
    }
  }

  func testTossingHandFoldsOutsideTheShoulderAndBackhandKeepsItsSecondGrip() throws {
    let serve = try XCTUnwrap(StrokeStudioClip(.serve))
    for t in stride(from: -0.28, through: -0.08, by: PointReplay.tick) {
      let p = try XCTUnwrap(serve.frame(serve.contactTime+t)).near
      XCTAssertEqual(p.supportGrip, 0)
      XCTAssertGreaterThan(simd_distance(p[.leftHand], p[.leftShoulder]), 0.19)
    }
    let drive = try XCTUnwrap(StrokeStudioClip(.backhand))
    for t in stride(from: -0.18, through: 0.27, by: PointReplay.tick) {
      let p = try XCTUnwrap(drive.frame(drive.contactTime+t)).near
      XCTAssertGreaterThan(p.supportGrip, 0.88)
      XCTAssertEqual(simd_distance(p[.leftHand], p[.grip]), 0.095, accuracy: 0.012)
    }
  }

  func testWideBackhandTurnsWithOutsideLegAndKeepsBothHandsThroughRecovery() throws {
    for side in 0...1 {
      let sign: Float = side == 0 ? 1 : -1
      var game = PracticeEngine(settings: .init(local: true, surface: .hard, allCourtTraining: false))
      game.phase = .live
      game.players[side].pos = Vec(x: 4.115, y: side == 0 ? 22.6 : PracticeEngine.length-22.6)
      game.players[1-side].pos = Vec(x: 4.115, y: side == 0 ? 1 : PracticeEngine.length-1)
      for i in 0...1 { game.players[i].destination = game.players[i].pos }
      game.launch(1-side, aim: Vec(x: 4.115-Double(sign)*2.65, y: side == 0 ? 21.5 : PracticeEngine.length-21.5), kind: .cross)
      game.apply(.guidedMove(.receive), side: side)
      var performance = CourtPerformance(game: game)
      var poses: [AthletePose] = [], impact: Int?
      for i in 0..<420 {
        if let impact, i == impact+19 { game.apply(.guidedMove(.recover), side: side) }
        game.step(PointReplay.tick, random: { 0.8 })
        performance.update(game: game, dt: PointReplay.tick)
        let frame = try XCTUnwrap(performance.frame)
        poses.append(side == 0 ? frame.near : frame.far)
        if impact == nil && game.flight?.hitter == side { impact = i }
        if let impact, i >= impact+50 { break }
      }
      let hit = try XCTUnwrap(impact)
      func turn(_ across: CourtPoint3D) -> Float { atan2(-sign*across.z,sign*across.x) }
      for p in poses[(hit-24)...hit] {
        let belt = turn(p[.rightHip]-p[.leftHip])
        let shoulders = turn(p[.rightShoulder]-p[.leftShoulder])
        XCTAssertLessThan(abs(shoulders-belt), .pi/3)
      }
      for p in poses[hit...(hit+45)] {
        XCTAssertEqual(simd_distance(p[.grip],p[.leftHand]), 0.095, accuracy: 0.005)
      }
      let finish = poses[hit+28]
      let shoulderHeight = (finish[.leftShoulder].y+finish[.rightShoulder].y)/2
      XCTAssertGreaterThan(finish[.grip].y-shoulderHeight, 0.09)
      XCTAssertGreaterThan(finish[.leftElbow].y-shoulderHeight, 0.0)
    }
  }

  func testTwoBoneHingePreservesUnequalLengthsAndBendPlane() {
    let limb = LimbGeometry(upper: 0.252, lower: 0.267)
    for high: Float in [-0.2, 0, 0.2] {
      let root = SIMD3<Float>(1, 1.45, 2), end = root + [0.30, high, -0.20]
      let hinge = limb.hinge(from: root, to: end, guide: root + [0.30, -0.25, 0.15], fallback: [0, 0, 1])
      XCTAssertEqual(simd_distance(root, hinge), limb.upper, accuracy: 0.0001)
      XCTAssertEqual(simd_distance(hinge, end), limb.lower, accuracy: 0.0001)
      XCTAssertGreaterThan(hinge.z, (root.z + end.z) / 2)
    }
    let singular = limb.hinge(from: .zero, to: [0, -0.52, 0], guide: [0, -0.3, 0], fallback: [0, -1, 0])
    XCTAssertTrue(singular.x.isFinite && singular.y.isFinite && singular.z.isFinite)
  }

  func testBothPreparedSwingsHaveASideOnSetAndCarryThroughContact() throws {
    for shot in [StudioStroke.forehand, .backhand] {
      let clip = try XCTUnwrap(StrokeStudioClip(shot))
      let set = try XCTUnwrap(clip.frame(clip.contactTime - 0.29)).near
      let shoulders = set[.rightShoulder] - set[.leftShoulder]
      XCTAssertGreaterThan(abs(atan2(shoulders.z, shoulders.x)), 75 * .pi / 180)
      let contact = try XCTUnwrap(clip.frame(clip.contactTime))
      XCTAssertEqual(simd_distance(contact.near[.strings], contact.ball), 0, accuracy: 0.0001)
      let strike = SIMD3<Float>(0.5, 0.87, 0.7)
      let dt: Float = 0.0001
      func path(_ time: Float) -> SIMD3<Float> {
        GroundstrokePath(time: time, backhand: shot == .backhand, strike: strike, rush: 0, power: false).strings
      }
      let before = (path(0) - path(-dt)) / dt, after = (path(dt) - path(0)) / dt
      XCTAssertGreaterThan(after.z, 4)
      XCTAssertLessThan(simd_distance(before, after), 0.10)
    }
  }
}
