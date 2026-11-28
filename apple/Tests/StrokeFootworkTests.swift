import XCTest
import simd
@testable import TennisCore

final class StrokeFootworkTests: XCTestCase {
  private func frames(on side: Int, startX: Double, aimX: Double, short: Bool) throws -> (frames: [AthletePose], hit: Int) {
    func court(_ x: Double, _ z: Double) -> Vec {
      side == 0 ? Vec(x:x,y:z) : Vec(x:PracticeEngine.width-x,y:PracticeEngine.length-z)
    }
    var game = PracticeEngine(settings:.init(local:true,surface:.hard,allCourtTraining:false))
    game.phase = .live
    game.players[side].pos = court(startX,short ? 22.3 : 22.6)
    game.players[1-side].pos = court(4.115,1)
    for i in game.players.indices { game.players[i].destination = game.players[i].pos }
    game.launch(1-side,aim:court(aimX,short ? 17.2 : 21.45),kind:.cross)
    if short { game.flight?.duration = 1.72 }
    game.apply(.guidedMove(.receive),side:side)
    var motion = AthleteMotion(), poses: [AthletePose] = [], impact: Int?
    for i in 0..<420 {
      let serial = game.contactSerial
      game.step(1/120,random:{0.8})
      let hit = serial != game.contactSerial && game.flight?.hitter == side
      poses.append(motion.sample(game:game,side:side,hit:hit,dt:1/120,reduceMotion:false))
      if hit && impact == nil { impact = i }
      if let impact, i >= impact+36 { break }
    }
    return (poses,try XCTUnwrap(impact))
  }

  func testWideBackhandCollectsTheTrailingShoeAndUsesAnOpenBase() throws {
    for side in 0...1 {
      let (poses,impact) = try frames(on:side,startX:6.7,aimX:2.6,short:false)
      let hit = poses[impact], loaded = poses[impact-17]
      let base = hit[.rightShoe]-hit[.leftShoe]
      XCTAssertLessThan(abs(base.z),0.24)
      XCTAssertGreaterThan(abs(base.x),0.48)
      XCTAssertLessThan(simd_length(base),0.85)
      XCTAssertLessThan(simd_distance(hit[.leftShoe],loaded[.leftShoe]),0.06)
      XCTAssertGreaterThan(hit[.leftHip].y-loaded[.leftHip].y,0.08)
      XCTAssertGreaterThan(hit.supportGrip,0.90)
    }
    let closed = try XCTUnwrap(StrokeStudioClip(.backhand))
    let p = try XCTUnwrap(closed.frame(closed.contactTime)).near
    XCTAssertGreaterThan(p[.leftShoe].z-p[.rightShoe].z,0.33)
  }

  func testApproachDrivesUseBothWingsWithLegDriveAndAnAcrossBodyFinish() throws {
    for side in 0...1 {
      for backhand in [false,true] {
        let (poses,impact) = try frames(on:side,startX:4.1,aimX:backhand ? 2.1 : 5.4,short:true)
        let load = poses[impact-18], hit = poses[impact], finish = poses[impact+26]
        let facing: Float = side == 0 ? 1 : -1
        let shootingSide: Float = backhand ? -facing : facing
        let line = load[.rightShoulder]-load[.leftShoulder]
        XCTAssertGreaterThan(abs(atan2(-line.z*facing,line.x*facing)),1.1)
        XCTAssertGreaterThan(hit[.leftHip].y-load[.leftHip].y,0.075)
        func sideOfChest(_ pose: AthletePose) -> Float {
          (pose[.strings].x-(pose[.rightShoulder].x+pose[.leftShoulder].x)/2)*shootingSide
        }
        XCTAssertGreaterThan(sideOfChest(hit),0.68)
        XCTAssertLessThan(sideOfChest(finish),-0.12)
        XCTAssertGreaterThan(finish[.strings].y-hit[.strings].y,0.38)
      }
    }
  }

  func testDiagonalChangeCollectsTheTrailingFootThroughAMediumSpeedCut() {
    var game = PracticeEngine(settings:.init(local:true,surface:.hard))
    game.phase = .live
    game.players[0].pos = Vec(x:4.1,y:16.55)
    var motion = AthleteMotion()
    for (turn,target) in [Vec(x:0.2,y:15.1),Vec(x:7.6,y:15.2),Vec(x:3.2,y:21.5)].enumerated() {
      game.move(0,to:target)
      for frame in 0..<81 {
        game.updateFootwork(1/120)
        game.time += 1/120
        let p = motion.sample(game:game,side:0,hit:false,dt:1/120,reduceMotion:false)
        if turn == 2 && (12...23).contains(frame) {
          XCTAssertLessThan(simd_distance(p[.leftShoe],p[.rightShoe]),1.05)
        }
      }
    }
  }

  func testPlantedShoeTurnsContinuouslyThroughAReversalAndReplayScrub() throws {
    for side in 0...1 {
      func court(_ x: Double,_ y: Double) -> Vec {
        side == 0 ? Vec(x:x,y:y) : Vec(x:PracticeEngine.width-x,y:PracticeEngine.length-y)
      }
      var game = PracticeEngine(settings:.init(local:true,surface:.hard))
      game.phase = .live
      game.players[side].pos = court(4.1,16.55)
      var motion = AthleteMotion(), previous: AthletePose?
      for target in [court(4.3,24.9),court(5.3,22.2),court(7.7,16.5),court(7.0,24.6),court(1.4,22.7)] {
        game.move(side,to:target)
        for _ in 0..<81 {
          game.updateFootwork(1/120)
          game.time += 1/120
          let pose = motion.sample(game:game,side:side,hit:false,dt:1/120,reduceMotion:false)
          let heading = try XCTUnwrap(pose.soleHeading)
          if let previous, let last = previous.soleHeading {
            let mid = try XCTUnwrap(previous.blended(to:pose,by:0.5).soleHeading)
            for foot in 0...1 {
              XCTAssertLessThan(abs(heading[foot]-last[foot]),0.126)
              XCTAssertEqual(mid[foot],(heading[foot]+last[foot])*0.5,accuracy:0.001)
              XCTAssertLessThan(abs(pose.toePivotYaw[foot]-previous.toePivotYaw[foot]),0.068)
            }
          }
          previous = pose
        }
      }
    }
  }

  func testBentElbowKeepsItsPlaneWhenTheWristPassesTheBody() {
    let chain = LimbGeometry(upper:0.32,lower:0.28)
    let shoulder = SIMD3<Float>(0,1.35,0)
    for hz in [30.0,60.0,120.0] {
      var bend = ElbowBend(), previous = SIMD3<Float>.zero
      for i in 0..<Int(hz/2) {
        let t = Double(i)/hz
        let wrist = shoulder+SIMD3<Float>(0.18+0.18*Float(t),-0.30,-0.12)
        // At this wrist orientation two very different elbows can hold the same handle.
        let pole = SIMD3<Float>(i < 3 ? -1 : 1,0,-0.1)
        let wanted = chain.hinge(from:shoulder,to:wrist,guide:shoulder+pole,fallback:pole)
        let e = bend.follow(wanted,shoulder:shoulder,wrist:wrist,time:t)
        XCTAssertEqual(simd_distance(e,shoulder),chain.upper,accuracy:0.0001)
        XCTAssertEqual(simd_distance(e,wrist),chain.lower,accuracy:0.0001)
        if i > 0 { XCTAssertLessThan(simd_distance(e,previous),Float(5.0/hz)) }
        let held = bend.follow(wanted,shoulder:shoulder,wrist:wrist,time:t)
        XCTAssertLessThan(simd_distance(e,held),0.00005)
        previous = e
      }
      let earlier = Double(Int(hz/2)-2)/hz
      let lastWrist = shoulder+SIMD3<Float>(0.18+0.18*Float(earlier),-0.30,-0.12)
      let alternate = chain.hinge(from:shoulder,to:lastWrist,guide:shoulder+[-1,0,0],fallback:[-1,0,0])
      let backward = bend.follow(alternate,shoulder:shoulder,wrist:lastWrist,time:earlier)
      XCTAssertLessThan(simd_distance(previous,backward),Float(5.0/hz))
      let wrist = shoulder+SIMD3<Float>(0.28,-0.30,-0.12)
      let target = chain.hinge(from:shoulder,to:wrist,guide:shoulder+[1,0,0],fallback:[1,0,0])
      XCTAssertLessThan(simd_distance(bend.follow(target,shoulder:shoulder,wrist:wrist,time:2),target),0.00001)
    }
  }

  func testKneeAngleRetargetsToUnequalAvatarBones() {
    for limb in [LimbGeometry(upper:0.406,lower:0.415),LimbGeometry(upper:0.444,lower:0.464)] {
      for degrees in [18,38,70,104] {
        let theta = Float(degrees) * .pi/180
        let span = limb.span(matching:[0,-1,0],lowerRay:[0,-cos(theta),sin(theta)])
        let socket = SIMD3<Float>(0,span,0), ankle = SIMD3<Float>.zero
        let knee = limb.hinge(from:socket,to:ankle,guide:[0,span/2,-0.36],fallback:[0,0,-1])
        let measured = acos(simd_dot(simd_normalize(knee-socket),simd_normalize(ankle-knee)))
        XCTAssertEqual(measured,theta,accuracy:0.002)
        XCTAssertEqual(simd_distance(socket,knee),limb.upper,accuracy:0.0001)
        XCTAssertEqual(simd_distance(knee,ankle),limb.lower,accuracy:0.0001)
      }
    }
  }
}
