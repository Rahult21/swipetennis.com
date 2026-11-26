import XCTest
@testable import TennisCore

final class TacticalTrainingTests: XCTestCase {
  func testLostBallSnapshotIsIndependentAndRetainedInFinishingShot() throws {
    var game = PracticeEngine(settings:.init())
    game.phase = .live
    game.players[0].energy = 0.64
    var performance = CourtPerformance(game:game)
    game.launch(1,aim:Vec(x:1.4,y:21.5),kind:.cross)
    performance.update(game:game,dt:PointReplay.tick)
    let decision = try XCTUnwrap(performance.replay.finishingShot.decisions[0])
    var retry = decision.game
    let originalBall = try XCTUnwrap(game.flight)
    XCTAssertEqual(retry.flight?.landing,originalBall.landing)
    XCTAssertEqual(retry.flight?.duration,originalBall.duration)
    XCTAssertEqual(retry.players[0].energy,0.64)
    retry.move(0,to:Vec(x:2,y:20))
    retry.end(0,reason:"Practice",tip:"")
    XCTAssertEqual(game.scoring.points,[0,0])
    XCTAssertEqual(game.players[0].destination,decision.feet)
    XCTAssertTrue(game.coach.records.isEmpty)
  }

  func testNoDecisionRecordedForFaultAndHeightUsesPhysicalJointPositions() throws {
    var game = PracticeEngine(settings:.init())
    game.phase = .live
    var motion = CourtPerformance(game:game)
    game.launch(0,aim:Vec(x:1,y:2),kind:.line,fault:"wide")
    motion.update(game:game,dt:PointReplay.tick)
    XCTAssertNil(motion.replay.decisions[1])
    let height = try XCTUnwrap(motion.replay.heights[0])
    XCTAssertEqual(height.height,game.flight!.strikeOrigin!.y,accuracy:0.001)
  }

  func testRivalPredictsBeforeLearningAndRemembersIntoRematch() throws {
    var repeated = ClubEncounter.debut.makeGame()
    repeated.phase = .live
    repeated.rivalReads = RivalReads(serves:[2,2,2])
    var changed = repeated
    repeated.launch(0,aim:Vec(x:0.8,y:6.2),kind:.cross,serve:true)
    changed.launch(0,aim:Vec(x:3.8,y:6.2),kind:.cross,serve:true)
    XCTAssertLessThan(repeated.reactAt,changed.reactAt)
    XCTAssertEqual(repeated.players[1].destination.x,changed.players[1].destination.x)
    var save = SoloCareer()
    save.record(changed,encounter:.debut)
    let restored = try JSONDecoder().decode(SoloCareer.self,from:JSONEncoder().encode(save))
    XCTAssertEqual(restored.readsByRival?["Morgan"]?.serves,[2,2,2,0])
    XCTAssertNil(restored.readsByRival?["Casey"])
  }

  func testBaselineApproachPatternCanBeDisguised() {
    var repeated = ClubEncounter.debut.makeGame()
    repeated.phase = .live
    repeated.rivalReads = RivalReads(approaches:[1,1,1], recentAttacks:[true,true,true])
    var changed = repeated
    repeated.launch(0,aim:Vec(x:7,y:2),kind:.line)
    changed.launch(0,aim:Vec(x:1,y:2),kind:.line)
    XCTAssertLessThan(repeated.reactAt,changed.reactAt)
    XCTAssertEqual(changed.rivalReads?.recentAttacks,[true,true,true,false])
  }

  func testServePlanAndNetSplitSeedRealFlights() throws {
    let serve = TrainingFeed.serve(.wide,surface:.clay)
    XCTAssertEqual(serve.scoring.server,0)
    XCTAssertEqual(serve.servePreparation?.placement,.wide)
    var feed = TrainingFeed.net(surface:.grass,lob:true,right:true)
    let original = try XCTUnwrap(feed.flight)
    TrainingFeed.split(Vec(x:8,y:16.8),into:&feed)
    XCTAssertEqual(feed.players[0].pos,Vec(x:8,y:16.8))
    XCTAssertEqual(feed.flight?.kind,.lob)
    XCTAssertEqual(feed.flight?.duration,original.duration)
    XCTAssertEqual(feed.players[0].splitForReturn,feed.contactSerial)
    XCTAssertEqual(feed.flight?.elapsed,0)
  }

  func testScoutingUsesKnownRepliesAndChangeovers() {
    var game = PracticeEngine(settings:.init(scoring:.tennis,opponentName:"Casey"))
    game.scoutedReplies = [true,false,true,true].map { ScoutedReply(stretched:true,short:$0,backhand:true) }
    XCTAssertEqual(game.scoutingNote,"3 of 4 stretched backhands from Casey landed short.")
    XCTAssertNil(game.changeoverNote)
    for _ in 0..<4 { game.scoring.award(0) }
    XCTAssertEqual(game.changeoverNote,game.scoutingNote)
  }

  func testCapturedMotionIsBundledAndInterpolates() {
    for clip in ["plant","recover","volley"] {
      let a = CapturedTransitions.sample(clip,seconds:0.10)
      let b = CapturedTransitions.sample(clip,seconds:0.12)
      let c = CapturedTransitions.sample(clip,seconds:0.11)
      XCTAssertEqual(c.hand.y,(a.hand.y+b.hand.y)/2,accuracy:0.0001)
      XCTAssertGreaterThan(abs(a.pelvis)+abs(a.left.x)+abs(a.hand.y),0.001,clip)
    }
  }

  func testHardCourtBrakesSoonerThanClay() {
    func braking(_ surface: CourtSurface) -> Double {
      var game = PracticeEngine(settings:.init(surface:surface))
      game.players[0].velocity = Vec(x:4,y:0)
      game.players[0].destination = game.players[0].pos
      game.updateFootwork(0.04)
      return game.players[0].velocity.x
    }
    XCTAssertLessThan(braking(.hard),braking(.grass))
    XCTAssertLessThan(braking(.grass),braking(.clay))
  }
}
