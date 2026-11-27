import XCTest
import simd
@testable import TennisCore

final class PlayerCameraTests: XCTestCase {
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
