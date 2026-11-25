import XCTest

@testable import TennisCore

final class StrokeAnimationTests: XCTestCase {
  func testQuickIncomingBallFlowsOutOfRecoveryWithoutPoseJump() {
    var animation = StrokeAnimation()
    animation.hit(style: .groundstroke)
    animation.update(delta: 0.24, lateralBall: 1, arrival: nil, incomingStyle: .groundstroke)
    let previous = animation.pose
    animation.update(delta: 0, lateralBall: -1, arrival: 0.24, incomingStyle: .groundstroke)
    XCTAssertNil(animation.timeAfterContact)
    XCTAssertEqual(animation.pose.grip, previous.grip)
    XCTAssertEqual(animation.pose.racketAngle, previous.racketAngle)
    animation.update(delta: 0.24, lateralBall: -1, arrival: 0, incomingStyle: .groundstroke)
    XCTAssertEqual(animation.pose.grip, animation.contactPose.grip)
  }

  func testContactAnimationUsesElapsedPhysicsTimeWithinTheRenderedFrame() {
    var animation = StrokeAnimation()
    animation.hit(style: .groundstroke, elapsed: 1 / 120)
    XCTAssertEqual(animation.timeAfterContact, 1 / 120)
    XCTAssertNotEqual(animation.pose.grip, animation.contactPose.grip)
  }

  func testBackhandUsesPlayerRelativeLeftForBothEnds() {
    XCTAssertLessThan(StrokeAnimation.lateralBallOffset(ballX: 2, playerX: 4, courtSide: 0), 0)
    XCTAssertLessThan(StrokeAnimation.lateralBallOffset(ballX: 6, playerX: 4, courtSide: 1), 0)
    for side in 0...1 {
      var animation = StrokeAnimation()
      animation.update(
        delta: 0,
        lateralBall: StrokeAnimation.lateralBallOffset(
          ballX: side == 0 ? 2 : 6, playerX: 4, courtSide: side), arrival: 0.4,
        incomingStyle: .groundstroke)
      XCTAssertEqual(animation.stance, .backhand)
      XCTAssertTrue(animation.contactPose.supportHandOnGrip)
      XCTAssertLessThan(animation.contactPose.racketCentre.x, 0)
    }
  }

  func testDeadBandAndStrokeCommitPreventRacketFlips() {
    var animation = StrokeAnimation()
    animation.update(delta: 0, lateralBall: -0.4, arrival: 0.4, incomingStyle: .groundstroke)
    animation.update(delta: 0, lateralBall: 0.06, arrival: 0.3, incomingStyle: .groundstroke)
    XCTAssertEqual(animation.stance, .backhand)
    animation.update(delta: 0, lateralBall: -0.3, arrival: 0.10, incomingStyle: .groundstroke)
    animation.update(delta: 0, lateralBall: 1, arrival: 0.05, incomingStyle: .groundstroke)
    XCTAssertEqual(animation.stance, .backhand)
    animation.hit(style: .groundstroke)
    animation.update(delta: 0.15, lateralBall: 1, arrival: 0.5, incomingStyle: .groundstroke)
    XCTAssertEqual(animation.stance, .backhand)
    animation.update(delta: 0.6, lateralBall: 1, arrival: 0.5, incomingStyle: .groundstroke)
    XCTAssertEqual(animation.stance, .forehand)
  }

  func testForwardSwingArrivesAtContactWithoutDiscontinuity() {
    for lateral in [-1.0, 1.0] {
      var animation = StrokeAnimation()
      animation.update(delta: 0, lateralBall: lateral, arrival: 0.12, incomingStyle: .groundstroke)
      let prepared = animation.pose
      animation.update(delta: 0, lateralBall: lateral, arrival: 0, incomingStyle: .groundstroke)
      let impact = animation.pose
      XCTAssertNotEqual(prepared.racketAngle, impact.racketAngle)
      animation.hit(style: .groundstroke)
      XCTAssertEqual(animation.pose.grip, impact.grip)
      XCTAssertEqual(animation.pose.racketAngle, impact.racketAngle)
      animation.update(delta: 0.2, lateralBall: lateral, arrival: nil, incomingStyle: .groundstroke)
      XCTAssertEqual(animation.pose.grip, animation.finishPose.grip)
      animation.update(delta: 1, lateralBall: lateral, arrival: nil, incomingStyle: .groundstroke)
      XCTAssertEqual(animation.pose.grip, animation.readyPose.grip)
    }
  }

  func testContactReachKeepsBallOnStringsForCentredAndStretchedContacts() {
    for reach in [0.0, 7, 20, 35] {
      for lateral in [-1.0, 1.0] {
        var animation = StrokeAnimation()
        animation.update(
          delta: 0, lateralBall: lateral, arrival: 0.3, incomingStyle: .groundstroke, reach: reach)
        XCTAssertEqual(animation.contactPose.racketCentre.x, reach * lateral, accuracy: 0.0001)
        XCTAssertEqual(animation.contactPose.racketCentre.y, 31, accuracy: 0.0001)
      }
    }
  }

  func testVolleyIsCompactAndServeIsOverhead() {
    var volley = StrokeAnimation()
    var ground = StrokeAnimation()
    var serve = StrokeAnimation()
    volley.update(delta: 0, lateralBall: 1, arrival: 0.15, incomingStyle: .volley)
    ground.update(delta: 0, lateralBall: 1, arrival: 0.15, incomingStyle: .groundstroke)
    XCTAssertLessThan(abs(volley.preparedPose.shoulderTurn), abs(ground.preparedPose.shoulderTurn))
    XCTAssertLessThan(volley.recoveryDuration, ground.recoveryDuration)
    serve.hit(style: .serve)
    XCTAssertGreaterThan(serve.contactPose.racketCentre.y, 55)
    XCTAssertFalse(serve.contactPose.supportHandOnGrip)
  }

  func testVolleySwingAnticipatesReachInsteadOfWaitingForBallAtBody() {
    for side in 0...1 {
      let from = Vec(x: 4, y: side == 0 ? 1 : 23)
      let landing = Vec(x: 4, y: side == 0 ? 23 : 1)
      let player = Vec(x: 4, y: side == 0 ? 17 : 7)
      var flight = BallFlight(
        from: from, landing: landing, contact: landing, duration: 2, hitter: 1 - side,
        fault: nil, explanation: "", loft: 1, serve: false)
      let progress = StrokeAnimation.volleyContactProgress(
        flight: flight, player: player, side: side)
      XCTAssertNotNil(progress)
      if let progress {
        let contactY = from.y + (landing.y - from.y) * progress / 0.8
        XCTAssertEqual(abs(contactY - player.y), 0.9, accuracy: 0.0001)
      }
      XCTAssertNil(
        StrokeAnimation.volleyContactProgress(
          flight: flight, player: Vec(x: 6, y: player.y), side: side))
      flight.serve = true
      XCTAssertNil(
        StrokeAnimation.volleyContactProgress(flight: flight, player: player, side: side))
      flight.serve = false
      flight.loft = 2.5
      XCTAssertNil(
        StrokeAnimation.volleyContactProgress(flight: flight, player: player, side: side))
    }
  }
}
