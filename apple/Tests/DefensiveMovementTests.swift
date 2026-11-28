import XCTest
import simd
@testable import TennisCore

final class DefensiveMovementTests: XCTestCase {
  private func wideBall(receiver: Int, gap: Double, local: Bool, kind: ShotKind = .cross) -> PracticeEngine {
    var game = PracticeEngine(settings: .init(local: local, difficulty: .medium, style: .allcourt, surface: .hard))
    game.phase = .live
    let z = receiver == 0 ? 22.0 : 1.77
    game.players[1-receiver].pos = Vec(x: 4, y: PracticeEngine.length-z)
    game.launch(1-receiver, aim: Vec(x: 4, y: z), kind: kind)
    let f = game.flight!
    let impact = f.worldBall(at: 0.99).courtPosition
    game.players[receiver].pos = Vec(x: impact.x-gap,y: impact.y)
    game.players[receiver].destination = game.players[receiver].pos
    game.flight?.elapsed = f.time(at: 0.99)-0.69
    return game
  }

  func testFourMetreDefensiveJumpOnEitherEndUsesRealRacketContact() throws {
    for receiver in 0...1 {
      for dt in [1.0/120,1.0/60,1.0/30] {
        var game = wideBall(receiver: receiver,gap: 4,local: receiver == 0)
        let start = game.players[receiver].pos
        let original = try XCTUnwrap(game.flight)
        let target = original.worldBall(at:0.99)
        var last = start
        var jumped = false
        for _ in 0..<160 where game.flight?.hitter != receiver && game.phase == .live {
          game.step(dt,interactiveRally:true,random:{0.6})
          let here = game.players[receiver].pos
          XCTAssertLessThan(here.distance(to:last),dt*11)
          last = here
          if game.players[receiver].netEffort?.stroke == .jumpLob { jumped = true }
        }
        let outgoing = try XCTUnwrap(game.flight)
        XCTAssertTrue(jumped)
        XCTAssertEqual(outgoing.hitter,receiver)
        XCTAssertTrue(outgoing.isDefensiveLob)
        XCTAssertNil(outgoing.fault)
        XCTAssertGreaterThan(start.distance(to:last),2.8)
        XCTAssertLessThan(last.distance(to:target.courtPosition),0.93)
        XCTAssertLessThan(simd_distance(try XCTUnwrap(outgoing.strikeOrigin),target),0.002)
      }
    }
  }

  func testFourMetresIsMeasuredToTheInterceptionAndFaultsAreExcluded() {
    for side in 0...1 {
      for gap in [0.5,4.02] {
        var game = wideBall(receiver:side,gap:gap,local:true)
        game.prepareJumpLob(side,incoming:game.flight!,dt:1/120)
        XCTAssertNil(game.players[side].netEffort)
      }
      var fault = wideBall(receiver:side,gap:3.75,local:true)
      fault.flight?.serve = true
      fault.flight?.fault = "wide"
      fault.prepareJumpLob(side,incoming:fault.flight!,dt:1/120)
      XCTAssertNil(fault.players[side].netEffort)
    }
  }

  func testAnOrdinaryGroundstrokeWindowStillRequiresTheTimedSwipe() throws {
    var game = wideBall(receiver:0,gap:3.2,local:true)
    game.flight?.reboundDepth = 4.50
    let f = try XCTUnwrap(game.flight)
    game.players[0].pos = f.contact
    game.players[0].destination = f.contact
    let distance = f.worldBall(at:0.99).courtPosition.distance(to:f.contact)
    XCTAssertGreaterThan(distance,PracticeEngine.contactRadius+0.3)
    XCTAssertLessThan(distance,4)
    let time = f.time(at:0.99)-0.25
    game.flight?.elapsed = time
    XCTAssertNotNil(game.contactWindow(0))
    game.prepareJumpLob(0,incoming:game.flight!,dt:1/120)
    XCTAssertNil(game.players[0].netEffort)
    for _ in 0..<120 where game.phase == .live { game.step(1/120,interactiveRally:true,random:{0.61}) }
    XCTAssertEqual(game.flight?.hitter,1)
    XCTAssertTrue(game.isResolvingPoint)
  }

  func testRunningSaveOnALowDropMeetsTheBallBeforeItDies() throws {
    for side in 0...1 {
      var game = wideBall(receiver:side,gap:3.7,local:true,kind:.drop)
      let incoming = try XCTUnwrap(game.flight)
      let ball = incoming.worldBall(at:0.91)
      let start = Vec(x:Double(ball.x)-3.7,y:Double(ball.z))
      game.players[side].pos = start
      game.players[side].destination = start
      game.flight?.elapsed = incoming.time(at:0.91)-0.56
      var motion = AthleteMotion(), hitPose: AthletePose?
      let serial = game.contactSerial
      for _ in 0..<160 where game.contactSerial == serial {
        game.step(1/120,interactiveRally:true,random:{0.65})
        let hit = game.contactSerial != serial
        let p = motion.sample(game:game,side:side,hit:hit,dt:1/120,reduceMotion:false)
        if hit { hitPose = p }
      }
      XCTAssertTrue(game.flight?.isDefensiveLob == true)
      XCTAssertEqual(game.flight?.hitter,side)
      XCTAssertGreaterThan(game.flight?.loft ?? 0,3)
      XCTAssertGreaterThan(ball.y,0.23)
      let hit = try XCTUnwrap(hitPose)
      XCTAssertLessThan(simd_distance(hit[.strings],ball),0.003)
      XCTAssertLessThan(hit[.rightHip].y,1.0)
    }
  }

  func testSavePreservesEntryVelocityAndCarriesMomentumThroughContact() throws {
    let entering = Vec(x:1.5,y:-0.4)
    let effort = NetEffort(stroke:.jumpLob,serial:3,startTime:1,impactTime:1.7,progress:0.99,
      from:Vec(x:0,y:2),landing:Vec(x:3,y:2),target:[3.7,1,2],reachable:true,
      afterBounce:true,entryVelocity:entering)
    let data = try JSONEncoder().encode(effort)
    let snapshot = try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any])
    XCTAssertEqual(snapshot["stroke"] as? String,"volley")
    XCTAssertEqual(try JSONDecoder().decode(NetEffort.self,from:data).stroke,.jumpLob)
    let legacy = snapshot.filter { $0.key != "runningLob" && $0.key != "entryVelocity" }
    let old = try JSONDecoder().decode(NetEffort.self,from:JSONSerialization.data(withJSONObject:legacy))
    XCTAssertEqual(old.stroke,.volley)
    let dt = 0.0001
    func velocity(at time: Double) -> Vec {
      let a = effort.position(at:time), b = effort.position(at:time+dt)
      return Vec(x:(b.x-a.x)/dt,y:(b.y-a.y)/dt)
    }
    XCTAssertLessThan(velocity(at:1).distance(to:entering),0.01)
    XCTAssertLessThan(velocity(at:1.7-dt).distance(to:velocity(at:1.7)),0.01)
    XCTAssertGreaterThan(velocity(at:1.7).x,0.8)
    XCTAssertEqual(velocity(at:1.93),.zero)
    XCTAssertLessThan(effort.position(at:2).distance(to:effort.landing),0.25)
  }

  func testOpponentAbandonsAPassedAirContactAndChasesTheRebound() throws {
    var game = PracticeEngine(settings:.init(difficulty:.medium,style:.volley))
    game.phase = .live
    game.players[0].pos = Vec(x:2,y:23)
    game.players[1].pos = Vec(x:6.6,y:7)
    game.attacking[1] = true
    game.launch(0,aim:Vec(x:1.2,y:1.5),kind:.cross)
    let passed = game.flight!.time(at:0.83)
    game.flight?.elapsed = passed
    let flight = try XCTUnwrap(game.flight)
    XCTAssertEqual(game.intercept(1),flight.contact)
    game.step(1/120,interactiveRally:true,random:{0.62})
    XCTAssertLessThan(game.players[1].destination.distance(to:flight.contact),0.01)
  }

  func testOpponentCommitsToTheReboundWhenTheLobIsAlreadyPastItsOverheadReach() throws {
    var game = PracticeEngine(settings:.init(difficulty:.tough,style:.volley,surface:.grass,allCourtTraining:false))
    game.phase = .live
    game.players[0].pos = Vec(x:6.72,y:14.97)
    game.players[1].pos = Vec(x:4.08,y:7.91)
    game.players[1].destination = game.players[1].pos
    game.players[1].velocity = Vec(x:2.26,y:0.64)
    game.attacking[1] = true
    game.launch(0,aim:Vec(x:4.61,y:0.66),kind:.lob)
    game.flight?.setLaunchSpeed(kph:68)
    game.flight?.swingStrength = 0.75
    let incoming = try XCTUnwrap(game.flight)
    let overhead = try XCTUnwrap(BallContactWindow.overheadTarget(flight:incoming,side:1))
    game.step(1/120,interactiveRally:true,random:{0.72})
    let read = try XCTUnwrap(game.flight?.opponentIntercept)
    XCTAssertEqual(read.point,incoming.contact)
    XCTAssertGreaterThan(read.point.distance(to:overhead.point),3)
    for _ in 0..<240 where game.flight?.hitter == 0 && game.flight!.progress < overhead.progress {
      XCTAssertEqual(game.intercept(1),read.point)
      game.step(1/120,interactiveRally:true,random:{0.72})
    }
  }

  func testOpponentChasesFromContactAndMovementSpeedIsIndependentOfShotPace() {
    var game = wideBall(receiver:1,gap:4.5,local:false)
    game.flight?.elapsed = 0
    let feet = game.players[1].pos
    game.step(1/120,interactiveRally:true,random:{0.6})
    XCTAssertGreaterThan(game.players[1].pos.x,feet.x)
    XCTAssertGreaterThan(game.reactAt,game.time)
    XCTAssertEqual(game.settings.opponentRunSpeed(),1.2*game.settings.style.speed*game.settings.botSpeed,accuracy:1e-8)
  }

  func testThreeOfFourPlayableLobSmashesLandAndTheMissIsARealFault() throws {
    for defensive in [true,false] {
      var made = 0
      for roll in [0.125,0.375,0.625,0.875] {
        var game = PracticeEngine(settings:.init())
        game.phase = .live
        game.launch(0,aim:Vec(x:5.5,y:3),kind:.lob)
        game.flight?.jumpLob = defensive
        let mark = try XCTUnwrap(BallContactWindow.overheadTarget(flight:game.flight!,side:1))
        game.players[1].pos = mark.point
        game.players[1].destination = mark.point
        for _ in 0..<600 where game.flight?.hitter == 0 && game.phase == .live {
          game.step(1/120,interactiveRally:true,random:{roll})
        }
        XCTAssertEqual(game.flight?.hitter,1)
        XCTAssertEqual(game.flight?.stroke,.overhead)
        let shot = try XCTUnwrap(game.flight)
        XCTAssertGreaterThan(shot.launchPoint.y,2)
        if shot.fault == nil { made += 1 } else { XCTAssertTrue(["net","wide","long"].contains(shot.fault!)) }
      }
      XCTAssertEqual(made,3)
    }
  }
}
