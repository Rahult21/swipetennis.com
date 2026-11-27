import XCTest
import simd
@testable import TennisCore

final class PointBroadcastTests: XCTestCase {
  private func rally(_ strokes: [(Int, Int, Bool)]) -> PointReplay {
    var game = PracticeEngine(settings:.init(local:true))
    game.phase = .live
    let frame = RallyFrame(near:.init(),far:.init(),ball:[1,1,1])
    var clip = PointReplay()
    for sample in 0..<480 {
      let event = strokes.first { $0.0 == sample }
      if let (_,hitter,fault) = event {
        game.launch(hitter,aim:Vec(x:4,y:12),kind:.cross)
        if fault { game.flight?.fault = "long" }
      }
      clip.record(frame,game:game,hit:event != nil)
    }
    return clip
  }
  func testWinnerDriveEndsBeforeOpponentsErrorAndDoubleFaultStillHasAFilm() throws {
    let clip = rally([(60,1,false),(180,0,false),(345,1,true)])
    let shot = clip.winningShot(for:0)
    XCTAssertEqual(shot.strikes.map(\.hitter),[0])
    XCTAssertFalse(try XCTUnwrap(shot.strikes.last).fault)
    XCTAssertLessThan(shot.duration-0.55,Double(345-180)*PointReplay.tick)
    let fault = rally([(60,1,true),(280,1,true)]).winningShot(for:0)
    XCTAssertEqual(fault.strikes.count,1)
    XCTAssertTrue(try XCTUnwrap(fault.strikes.first).fault)
  }
  func testTwoSecondReactionAndThreeSecondPlayerHighlightUseWallTime() throws {
    let shot = rally([(90,0,false)]).winningShot(for:0)
    let plan = PointBroadcast(shot)
    XCTAssertEqual(PointBroadcast.reactionDuration,2)
    XCTAssertEqual(PointBroadcast.shotDuration,3)
    XCTAssertEqual(plan.sourceTime(at:0),plan.sourceTime(at:2))
    XCTAssertEqual(plan.sourceTime(at:2.3)-plan.sourceTime(at:2.1),0.1,accuracy:0.000001)
    XCTAssertEqual(plan.sourceTime(at:5),plan.end,accuracy:0.000001)
    var previous = plan.start
    for frame in 0...300 {
      let t = plan.sourceTime(at:Double(frame)/60)
      XCTAssertGreaterThanOrEqual(t,previous)
      XCTAssertLessThanOrEqual(t,shot.duration)
      previous = t
    }
  }
  func testReactionsHaveAFistAndTwoSeparatedSyllables() {
    let first = AthletePose.pointReaction(won:true,at:0.47)
    let closure = AthletePose.pointReaction(won:true,at:0.68)
    let second = AthletePose.pointReaction(won:true,at:0.95)
    XCTAssertGreaterThan(first.jawOpen,0.6)
    XCTAssertLessThan(closure.jawOpen,0.05)
    XCTAssertGreaterThan(second.jawOpen,0.82)
    XCTAssertGreaterThan(second.lipRound,closure.lipRound)
    XCTAssertGreaterThan(closure[.leftHand].y,closure[.leftShoulder].y)
    XCTAssertGreaterThan(closure[.leftHand].y,closure[.head].y)
    XCTAssertGreaterThan(closure[.head].x-closure[.leftHand].x,0.22)
    let forearm = simd_normalize(closure[.leftHand]-closure[.leftElbow])
    XCTAssertGreaterThan(forearm.y,0.90)
    XCTAssertLessThan(closure[.grip].y,closure[.rightShoulder].y-0.35)
    XCTAssertGreaterThan(closure.fingerCurl.x,0.96)
    let reset = AthletePose.pointReaction(won:false,at:0.68)
    XCTAssertLessThan(reset[.leftHand].y,reset[.leftElbow].y)
    XCTAssertLessThan(reset.fingerCurl.x,0.5)
  }
  func testLegAndArmLengthsStayFixedEvenWhenTargetsAreUnreachable() {
    let bone = LimbGeometry(upper:0.31,lower:0.25)
    for length: Float in [0,0.01,0.135,0.5,0.565,0.9,1.5] {
      let root = SIMD3<Float>(0.1,1.2,-0.1), target = root+[length,0,0]
      let end = bone.reachable(from:root,toward:target)
      let hinge = bone.hinge(from:root,to:end,guide:root+[0.22,0.01,0],fallback:[1,0,0])
      XCTAssertEqual(simd_distance(root,hinge),bone.upper,accuracy:0.00001)
      XCTAssertEqual(simd_distance(hinge,end),bone.lower,accuracy:0.00001)
    }
  }
  func testReplayFindsOutgoingLandingWhenReturnAndIncomingBounceShareATick() throws {
    var game = PracticeEngine(settings:.init(local:true))
    game.phase = .live
    game.launch(0,aim:Vec(x:3,y:1),kind:.cross)
    var replay = PointReplay()
    var frame = RallyFrame(near:.init(),far:.init(),ball:[1,0.1,1])
    frame.bounce = BounceImpression(serial:4,position:Vec(x:2,y:20),direction:0,surface:.hard,age:0)
    replay.record(frame,game:game,hit:true)
    XCTAssertNil(replay.lastShotBounceTime)
    frame.bounce = BounceImpression(serial:5,position:Vec(x:4,y:2),direction:0,surface:.hard,age:0)
    replay.record(frame,game:game,hit:false)
    XCTAssertEqual(try XCTUnwrap(replay.lastShotBounceTime),PointReplay.tick)
  }
  func testDiscardRemovesFramesContactsDecisionsAndBounceState() {
    var clip = rally([(70,0,false),(183,1,false)])
    XCTAssertTrue(clip.canPlay)
    XCTAssertFalse(clip.decisions.isEmpty)
    clip.discard()
    XCTAssertTrue(clip.frames.isEmpty && clip.strikes.isEmpty && clip.decisions.isEmpty)
    XCTAssertNil(clip.lastShotBounceTime)
    XCTAssertNil(clip.serviceRetry)
  }
}
