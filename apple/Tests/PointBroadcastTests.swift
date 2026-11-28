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
    let plan = PointBroadcast(shot,celebration:.risingFist)
    XCTAssertEqual(plan.reactionDuration,2)
    let plain = PointBroadcast(shot,celebration:nil)
    XCTAssertEqual(plain.duration,3)
    XCTAssertEqual(plain.sourceTime(at:0.3),plan.sourceTime(at:2.3),accuracy:0.000001)
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
  func testOnlyAnUnreturnedLegalWinnerCanSelectEitherCelebration() throws {
    for side in 0...1 {
      var game = PracticeEngine(settings:.init(local:true))
      game.phase = .live
      game.launch(side,aim:Vec(x:4,y:12),kind:.cross)
      for bucket in 0..<6 {
        let roll = { (Double(bucket)+0.5)/6.0 }
        var point = game
        point.end(side,reason:"Winner",tip:"",random:roll)
        let resolution = try XCTUnwrap(point.pointResolution)
        let saved = try JSONDecoder().decode(PointResolution.self,from:JSONEncoder().encode(resolution))
        XCTAssertEqual(saved.celebration,bucket == 0 ? .fistPump : bucket == 1 ? .risingFist : nil)
        XCTAssertNil(WinnerCelebration.select(winner:1-side,flight:game.flight,random:roll))
      }
      for fault in ["net","wide","long"] {
        game.flight?.fault = fault
        XCTAssertNil(WinnerCelebration.select(winner:side,flight:game.flight,random:{ 0 }))
        XCTAssertNil(WinnerCelebration.select(winner:1-side,flight:game.flight,random:{ 0 }))
      }
    }
    XCTAssertNil(try JSONDecoder().decode(PointResolution.self,from:Data(#"{"elapsed":0}"#.utf8)).celebration)
  }

  func testRisingFistLiftsFromWaistWithTwoSyllables() {
    let low = AthletePose.winnerReaction(at:0.22,celebration:.risingFist)
    let first = AthletePose.winnerReaction(at:0.47,celebration:.risingFist)
    let closure = AthletePose.winnerReaction(at:0.68,celebration:.risingFist)
    let second = AthletePose.winnerReaction(at:0.95,celebration:.risingFist)
    XCTAssertGreaterThan(first.jawOpen,0.6)
    XCTAssertLessThan(closure.jawOpen,0.05)
    XCTAssertGreaterThan(second.jawOpen,0.82)
    XCTAssertGreaterThan(second.lipRound,closure.lipRound)
    XCTAssertGreaterThan(second[.leftHand].y-low[.leftHand].y,0.38)
    XCTAssertGreaterThan(second.reactionFist,0.96)
    let classic = AthletePose.winnerReaction(at:0.68,celebration:.fistPump)
    XCTAssertGreaterThan(classic[.leftHand].y,classic[.head].y)
    XCTAssertLessThan(classic.gaze.x,-0.8)
    XCTAssertEqual(classic.jawOpen,0)
  }

  func testWalkBackPlantsEachFootAndPreservesFormThroughoutBothGestures() throws {
    for side in 0...1 {
      for gesture in [WinnerCelebration.fistPump,.risingFist] {
        var game = PracticeEngine(settings:.init(local:true))
        game.phase = .live
        game.launch(side,aim:Vec(x:4,y:12),kind:.cross)
        var shot = PointReplay()
        for tick in 0..<4 {
          var p = AthletePose.winnerReaction(at:0,celebration:gesture)
          for joint in BodyJoint.allCases { p[joint] += [Float(tick),0,side == 0 ? 16 : 6] }
          shot.record(.init(near:p,far:p,ball:[7,1,10]),game:game,hit:tick == 1)
        }
        let walk = try XCTUnwrap(WinnerWalk(shot:shot,winner:side,celebration:gesture))
        XCTAssertEqual(walk.origin.x,3,accuracy:0.001)
        XCTAssertNil(WinnerWalk(shot:shot,winner:1-side,celebration:gesture))
        let end = walk.sample(at:2).position
        XCTAssertGreaterThan((end.z-walk.origin.z)*(side == 0 ? 1 : -1),0.60)
        let rest = walk.sample(at:0).pose
        var previous = walk.sample(at:0)
        for tick in 1...240 {
          let frame = walk.sample(at:Double(tick)/120)
          var planted = false
          for (hip,knee,shoe) in [(BodyJoint.leftHip,BodyJoint.leftKnee,BodyJoint.leftShoe),(.rightHip,.rightKnee,.rightShoe)] {
            let ankle = frame.pose[shoe]+frame.position
            let other = previous.pose[shoe]+previous.position
            planted = planted || (abs(ankle.y-0.06)<0.00001 && simd_distance(ankle,other)<0.0001)
            XCTAssertEqual(simd_distance(frame.pose[hip],frame.pose[knee]),0.465,accuracy:0.0001)
            XCTAssertEqual(simd_distance(frame.pose[knee],frame.pose[shoe]),0.445,accuracy:0.0001)
          }
          XCTAssertTrue(planted)
          for (a,b) in [(BodyJoint.leftShoulder,BodyJoint.rightShoulder),(.leftHip,.rightHip),
                         (.leftShoulder,.leftElbow),(.leftElbow,.leftHand),(.rightShoulder,.rightElbow),
                         (.rightElbow,.grip),(.grip,.strings)] {
            XCTAssertEqual(simd_distance(frame.pose[a],frame.pose[b]),simd_distance(rest[a],rest[b]),accuracy:0.0001)
          }
          previous = frame
        }
      }
    }
  }
  func testResetFromEitherSidelineNeverCrossesFeetOrOvershootsTheBaseline() throws {
    for side in 0...1 {
      let sign: Float = side == 0 ? 1 : -1
      let baseline: Float = side == 0 ? Float(PracticeEngine.length) : 0
      for x: Float in [-1.1,4.115,9.3] {
        var game = PracticeEngine(settings:.init(local:true))
        game.phase = .live
        game.launch(side,aim:Vec(x:4,y:12),kind:.cross)
        var pose = AthletePose.winnerReaction(at:0,celebration:.risingFist)
        let hip = (pose[.leftHip]+pose[.rightHip])*0.5
        for joint in BodyJoint.allCases { pose[joint] += [x-hip.x,0,baseline-hip.z] }
        var clip = PointReplay()
        clip.record(.init(near:pose,far:pose,ball:[2,1,8]),game:game,hit:true)
        let walk = try XCTUnwrap(WinnerWalk(shot:clip,winner:side,celebration:.risingFist))
        for tick in 0...120 {
          let frame = walk.sample(at:Double(tick)/60)
          XCTAssertGreaterThan((frame.pose[.rightShoe].x-frame.pose[.leftShoe].x)*sign,0.30)
          XCTAssertEqual(frame.position.z,baseline,accuracy:0.00001)
        }
      }
    }
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
