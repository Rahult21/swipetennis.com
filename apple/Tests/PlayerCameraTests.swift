import XCTest
import simd
@testable import TennisCore

final class PlayerCameraTests: XCTestCase {
  func testPlayerViewContainsRacketAndFeetThroughWidePortraitFollowThrough() throws {
    let aspect: Float = 0.46
    for shot in [StudioStroke.forehand,.backhand,.serve,.volley] {
      let clip = try XCTUnwrap(StrokeStudioClip(shot))
      for k in 0...36 {
        let frame = try XCTUnwrap(clip.frame(clip.duration*Double(k)/36))
        let pose = frame.near
        let hip = (pose[.leftHip]+pose[.rightHip])*0.5
        let camera = PlayerCamera(eye:hip+[-0.88,1.4,3.65],target:hip+[-1.2,-0.2,-6.8],verticalFOV:58)
          .including(frame.ball,aspect:aspect).including(pose,aspect:aspect)
        for joint: BodyJoint in [.head,.leftHand,.grip,.strings,.racketEdge,.leftShoe,.rightShoe] {
          let p = camera.projected(pose[joint],aspect:aspect)
          XCTAssertLessThan(max(abs(p.x),abs(p.y)),1,"\(shot) at sample \(k), \(joint)")
        }
      }
    }
  }
  func testHandshakeOrbitReturnsOverTheStandsAndReduceMotionHoldsTheClasp() {
    for aspect: Float in [0.43,0.68,1.2,2.15] {
      let last = MatchCeremony.camera(seconds:MatchCeremony.duration,aspect:aspect,reduceMotion:false)
      let center = CourtPoint3D(4.115,0,11.885)
      for x: Float in [-22,22] { for z: Float in [-29.6,29.6] {
        let seat = last.projected(center+[x,8.5,z],aspect:aspect)
        XCTAssertLessThan(max(abs(seat.x),abs(seat.y)),1)
      } }
      var previous: Float?, rotation: Float = 0
      let still = MatchCeremony.camera(seconds:0,aspect:aspect,reduceMotion:true)
      for step in 0...20 {
        let seconds = Double(step)/20
        let depth = Float(MatchCeremony.distanceToNet(at:seconds))
        let tracking = MatchCeremony.camera(seconds:seconds,aspect:aspect,reduceMotion:false)
        for camera in [still,tracking] { for side: Float in [-1,1] { for shoulder: Float in [-0.27,0.27] {
          let headAndShoulders = center+[shoulder-side*0.14,1.78,side*depth]
          let p = camera.projected(headAndShoulders,aspect:aspect)
          XCTAssertLessThan(max(abs(p.x),abs(p.y)),0.99)
        } } }
      }
      for t in stride(from:0.0,through:MatchCeremony.duration,by:0.05) {
        let shot = MatchCeremony.camera(seconds:t,aspect:aspect,reduceMotion:false)
        let delta = shot.eye-shot.target, bearing = atan2(delta.x,delta.z)
        if let previous { rotation += atan2(sin(bearing-previous),cos(bearing-previous)) }
        previous = bearing
        XCTAssertEqual(still.eye,MatchCeremony.camera(seconds:t,aspect:aspect,reduceMotion:true).eye)
      }
      XCTAssertGreaterThan(abs(rotation),2 * .pi)
      XCTAssertLessThan(simd_distance(simd_normalize(last.eye-last.target),[0,1,0]),0.01)
    }
  }

  func testPlayerBallAndNextRingFitBothEndsAndOrientations() {
    for side in 0...1 { for aspect: Float in [0.43,0.68,1.2,2.15] {
      for nearX in [-0.6,4.115,8.83] { for depth in [15.2,22.7,25.1] {
        let feet = Vec(x:nearX,y:side == 0 ? depth : 23.77-depth)
        let ring = Vec(x:8.23-nearX,y:feet.y)
        let white = Vec(x:4.115,y:side == 0 ? 24.1 : -0.33)
        let ball = ring.world(height:1.6)
        let view = PlayerCamera.frame(side:side,player:feet,trackedX:Float(nearX),receiver:ring,recovery:white,
                                      ball:ball,aspect:aspect,intro:1,reduceMotion:false,style:.baseline)
        for point in [feet.world(),feet.world(height:2.95),ball,ring.world(),white.world()] {
          let projected = view.projected(point,aspect:aspect)
          XCTAssertLessThan(max(abs(projected.x),abs(projected.y)),1)
        }
      } }
    } }
  }
  func testPortraitReturnFramesTheTwoBaselinesAndNearAthlete() {
    let aspect: Float = 0.46
    for end in 0...1 {
      let near = Vec(x: end == 0 ? 6.2 : 2.03, y: end == 0 ? 24.7 : -0.93)
      let camera = PlayerCamera.frame(side:end,player:near,trackedX:Float(near.x),receiver:near,recovery:nil,
        ball:near.world(),aspect:aspect,intro:1,reduceMotion:false,style:.baseline)
      let feet = camera.projected(near.world(),aspect:aspect)
      let far = camera.projected([4.115,0,end == 0 ? 0 : 23.77],aspect:aspect)
      XCTAssertLessThan(feet.y,-0.50)
      XCTAssertGreaterThan(far.y,0.44)
      XCTAssertGreaterThan(far.y-feet.y,0.99)
    }
  }

  func testBaselineViewMakesTheNearPlayerLargerAndReduceMotionKeepsItsWideFrame() {
    let feet = Vec(x:4.115,y:24.3)
    func view(_ kind: MatchViewpoint, motion: Bool = false) -> PlayerCamera {
      PlayerCamera.frame(side:0,player:feet,trackedX:4.115,receiver:nil,recovery:nil,ball:feet.world(height:2.7),
                         aspect:0.62,intro:1,reduceMotion:motion,style:kind)
    }
    func height(_ camera: PlayerCamera) -> Float {
      abs(camera.projected(feet.world(height:1.8),aspect:0.62).y-camera.projected(feet.world(),aspect:0.62).y)
    }
    XCTAssertGreaterThan(height(view(.baseline)),height(view(.wide))*1.5)
    XCTAssertEqual(view(.baseline,motion:true).eye,view(.wide,motion:true).eye)
  }
  func testBaselineAndWideViewsFrameTheBallBehindEitherBaseline() {
    for aspect: Float in [0.43,2.18] { for side in 0...1 {
      let feet = Vec(x:5.8,y:side == 0 ? 23.2 : 0.57)
      for style in MatchViewpoint.allCases { for still in [true,false] {
        func camera(_ ball: CourtPoint3D) -> PlayerCamera {
          PlayerCamera.frame(side:side,player:feet,trackedX:5.8,receiver:nil,recovery:nil,
                             ball:ball,aspect:aspect,intro:1,reduceMotion:still,style:style)
        }
        for x: Float in [-3.5,11.7] { for z: Float in [-7.0,30.77] {
          let ball = CourtPoint3D(x,0.35,z)
          let view = camera(ball), p = view.projected(ball,aspect:aspect)
          XCTAssertLessThan(max(abs(p.x),abs(p.y)),1)
          if still { XCTAssertEqual(camera(feet.world()).eye,view.eye) }
        } }
      } }
    } }
  }

  func testReplayEyeBacksUpAlongItsAxisForABallPassingTheReceiver() {
    for side: Float in [-1,1] { for aspect: Float in [0.43,2.18] {
      let aim = CourtPoint3D(4.1,0.7,11.885+side*6.0)
      let eye = aim+[side*0.9,1.65,side*10.45]
      let close = PlayerCamera(eye:eye,target:aim,verticalFOV:58)
      let ball = CourtPoint3D(-1.8,1.0,11.885+side*20)
      let pulledBack = close.including(ball,aspect:aspect)
      let projection = pulledBack.projected(ball,aspect:aspect)
      XCTAssertLessThan(max(abs(projection.x),abs(projection.y)),1)
      XCTAssertEqual(pulledBack.target,aim)
      XCTAssertGreaterThan(simd_dot(simd_normalize(eye-aim),simd_normalize(pulledBack.eye-aim)),0.99999)
      XCTAssertEqual(close.including(aim,aspect:aspect).eye,eye)
    } }
  }

  func testSpinTracksFlightDirectionAndReversesForSlice() throws {
    func spin(_ kind: ShotKind, _ hitter: Int, elapsed: Double = 0) -> simd_quatf {
      var game = PracticeEngine(settings:.init())
      game.phase = .live
      let from = Vec(x:4,y:hitter == 0 ? 23.0 : 1.0), to = Vec(x:4,y:24-from.y)
      game.flight = BallFlight(from:from,landing:to,contact:to,elapsed:elapsed,duration:1,hitter:hitter,
                               fault:nil,explanation:"",loft:1,kind:kind)
      var spin = BallRotation()
      spin.advance(game,dt:PointReplay.tick)
      return spin.orientation
    }
    let normal = spin(.cross,0), slice = spin(.slice,0), far = spin(.cross,1)
    XCTAssertLessThan(simd_dot(normal.axis,slice.axis),-0.99)
    XCTAssertLessThan(simd_dot(normal.axis,far.axis),-0.99)
    XCTAssertGreaterThan(normal.angle,spin(.cross,0,elapsed:0.85).angle)
    let clip = try XCTUnwrap(StrokeStudioClip(.serve))
    let shot = clip.recording, frame = try XCTUnwrap(shot.frame(at:clip.impact + 0.15))
    let trimmed = shot.suffix(from:12)
    let same = try XCTUnwrap(trimmed.frame(at:clip.impact+0.15-12*PointReplay.tick))
    XCTAssertGreaterThan(abs(simd_dot(frame.ballRotation.vector,same.ballRotation.vector)),0.9999)
  }

  func testContactReviewLoopsAcrossTheRecordedStrike() throws {
    let clip = try XCTUnwrap(StrokeStudioClip(.serve))
    let range = try XCTUnwrap(clip.recording.contactWindow)
    let strike = try XCTUnwrap(clip.recording.strikes.last)
    XCTAssertTrue(range.contains(strike.time))
    XCTAssertLessThan(range.lowerBound,strike.time)
    let lap = range.upperBound-range.lowerBound
    for turn in 0..<6 {
      XCTAssertEqual(PointReplay.loopTime(strike.time + lap*Double(turn),in:range),strike.time,accuracy:0.0001)
    }
    XCTAssertNil(PointReplay().contactWindow)
  }

  func testServeTossStaysInPalmAndDescendsOntoRacket() {
    for side in 0...1 { for power in [false,true] {
      let feet = Vec(x:3.11,y:side == 0 ? 24.4 : -0.63)
      func ball(_ t: Float) -> CourtPoint3D { ServiceToss.ball(feet:feet,side:side,progress:t,explosive:power) }
      for t in stride(from:Float(0),through:ServiceToss.release,by:0.02) {
        XCTAssertEqual(ball(t),ServiceToss.palm(feet:feet,side:side,progress:t))
      }
      XCTAssertGreaterThan(ball(0.7).y,ball(1).y)
      XCTAssertGreaterThan(ball(0.98).y,ball(1).y)
      XCTAssertLessThan(simd_distance(ball(1),serviceImpact(at:feet,side:side,explosive:power)),0.001)
    } }
  }
}
