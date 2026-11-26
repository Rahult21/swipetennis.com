import XCTest
import simd
@testable import TennisCore

final class ApproachAndFootworkTests: XCTestCase {
  func testSwipeCannotCrossContactOrRestartApproachAfterBounce() throws {
    for side in 0...1 {
      let forward = Vec(x: 0, y: side == 0 ? -3 : 3)
      var game = PracticeEngine(settings: .init(local: true))
      game.phase = .live
      game.launch(1-side, aim: game.players[side].pos, kind: .cross)
      let receiving = game.contactSerial
      game.apply(.shotSwipe(Vec(x: 0,y: -35)), side: side, shotEpoch: receiving)
      XCTAssertEqual(game.players[side].kind, .line)
      game.launch(side, aim: Vec(x: 4,y: side == 0 ? 2 : 22), kind: .line)
      let outgoing = game.contactSerial
      game.apply(.run(forward), side: side, movementEpoch: receiving)
      game.apply(.shotSwipe(Vec(x: 25,y: 0)), side: side, shotEpoch: receiving)
      XCTAssertFalse(game.followingApproach[side])
      XCTAssertEqual(game.flight?.kind, .line)
      game.apply(.run(forward), side: side, movementEpoch: outgoing)
      XCTAssertTrue(game.followingApproach[side])
      game.flight!.elapsed = game.flight!.duration * 0.8 - 0.003
      game.step(1.0/120, random: { 0.99 })
      XCTAssertFalse(game.followingApproach[side])
      let stopped = game.players[side].pos
      game.apply(.run(forward), side: side, movementEpoch: outgoing)
      game.followShot(side)
      XCTAssertEqual(game.players[side].destination, stopped)
      XCTAssertNotEqual(game.movementGuide(side)?.kind, .approach)
      XCTAssertEqual(game.tactics[side].approaches, 1)
      game.launch(1-side, aim: Vec(x: 5,y: side == 0 ? 18 : 5), kind: .cross)
      game.apply(.run(forward), side: side, movementEpoch: outgoing)
      XCTAssertEqual(game.players[side].destination, stopped)
      let target = try XCTUnwrap(game.contactGuide(side))
      game.apply(.guidedMove(.receive), side: side)
      XCTAssertEqual(game.players[side].destination, PracticeEngine.own(side,target))
    }
  }

  func testRunAndStrokeDoNotCarryOverToTheNextExchange() {
    var game = PracticeEngine(settings: .init(local: true))
    game.phase = .live
    game.players[0].pos = Vec(x: 2,y: 22)
    game.players[0].destination = game.players[0].pos
    game.launch(1, aim: Vec(x: 7,y: 21), kind: .cross)
    game.swipeCourt(0, delta: Vec(x: 0,y: -3))
    XCTAssertEqual(game.players[0].destination,game.players[0].pos)
    game.players[0].pos = game.flight!.contact
    game.selectShotSwipe(Vec(x: 0,y: -40),side: 0)
    game.returnBall(0,volley: false,random: { 0.99 })
    XCTAssertEqual(game.flight?.kind,.line)
    XCTAssertNil(game.players[0].aim)
    XCTAssertEqual(game.players[0].kind,.cross)
  }

  func testAirborneFootBrakesBeforeTheOppositeLeadOnReversal() {
    for facing: Float in [-1,1] {
      var feet = CourtFootwork(), centre = CourtPoint3D(4,0,18)
      feet.advance(centre: centre, velocity: .zero, destination: centre, facing: facing, strideBias: .zero, dt: 0)
      func advance(_ speed: Float) {
        let velocity = CourtPoint3D(speed*facing,0,0)
        centre += velocity/120
        feet.advance(centre: centre, velocity: velocity, destination: centre+velocity,
          facing: facing, strideBias: .zero, dt: 1/120)
      }
      for _ in 0..<3 { advance(2) }
      let airborne = feet.right, plant = feet.left
      XCTAssertGreaterThan(airborne.y,0)
      advance(-1)
      XCTAssertEqual(feet.right.x,airborne.x,accuracy: 0.00001)
      XCTAssertLessThan(feet.right.y,airborne.y)
      XCTAssertEqual(feet.left,plant)
      for _ in 0..<10 { advance(-2) }
      XCTAssertGreaterThan(feet.left.y,0)
      XCTAssertLessThan((feet.left.x-plant.x)*facing,0)
    }
  }

  func testEarlyVolleyEndsTheRunAtThePlayersCurrentPosition() {
    var game = PracticeEngine(settings: .init())
    game.phase = .live
    game.launch(0, aim: Vec(x: 2,y: 3), kind: .cross)
    game.followShot(0)
    game.updateFootwork(0.04)
    let feet = game.players[0].pos
    game.launch(1, aim: Vec(x: 2,y: 22), kind: .line, stroke: .volley)
    XCTAssertFalse(game.followingApproach[0])
    XCTAssertEqual(game.players[0].destination, feet)
    XCTAssertEqual(game.players[0].velocity, .zero)
  }

  func testSideStepsOpenWithTravelSideFootAndKeepTheShoesApart() {
    for facing: Float in [-1,1] {
      for sign: Float in [-1,1] {
        var feet = CourtFootwork()
        var center = CourtPoint3D(4,0,12)
        let speed = CourtPoint3D(sign*5,0,0)
        feet.advance(centre: center, velocity: .zero, destination: center, facing: facing, strideBias: .zero, dt: 0)
        let left = feet.left, right = feet.right
        for tick in 0..<120 {
          center += speed / 120
          feet.advance(centre: center, velocity: speed, destination: center+speed, facing: facing, strideBias: .zero, dt: 1/120)
          if tick == 0 {
            let leadsLeft = sign*facing < 0
            XCTAssertEqual(leadsLeft ? feet.right : feet.left, leadsLeft ? right : left)
            let step = leadsLeft ? feet.left-left : feet.right-right
            XCTAssertGreaterThan(step.y,0); XCTAssertGreaterThan(step.x * sign,0)
          }
          XCTAssertGreaterThanOrEqual((feet.right.x-feet.left.x)*facing, 0.24)
          XCTAssertLessThan(abs((feet.left.x+feet.right.x)/2-center.x), 0.45)
        }
      }
    }
  }

  func testApproachArrowDependsOnReturnedBounceDepthAndInPlayReturn() {
    for side in 0...1 {
      for depth in [4.99,5.0,6.2] {
        var game = PracticeEngine(settings: .init(local: true))
        game.phase = .live
        let sign = side == 0 ? 1.0 : -1.0
        let y = side == 0 ? PracticeEngine.length-depth : depth
        game.players[side].pos = Vec(x: 3,y: y+sign*1.1)
        game.players[side].destination = Vec(x: 3,y: y-sign)
        game.launch(1-side, aim: Vec(x: 3,y: y), kind: .cross)
        game.returnBall(side,volley: false,random: { 0.99 })
        XCTAssertEqual(game.movementGuide(side)?.kind == .approach, depth >= 5)
        XCTAssertEqual(game.players[side].destination, game.players[side].pos)
        game.followShot(side)
        XCTAssertTrue(game.followingApproach[side])
        game.launch(1-side, aim: Vec(x: 1,y: y), kind: .cross, fault: "long")
        game.swipeCourt(side,delta: Vec(x: 0,y: -sign*2))
        XCTAssertEqual(game.players[side].destination, game.players[side].pos)
        XCTAssertFalse(game.followingApproach[side])
        XCTAssertNil(game.movementGuide(side))
        game.launch(side, aim: .zero, kind: .cross, serve: true)
        XCTAssertFalse(game.canFollowShot(side))
      }
    }
  }

  func testFirstCleanNetVolleyUnlocksDoubleSpeedAndShortMovementSwipes() throws {
    var game = PracticeEngine(settings: .init(local: true))
    game.phase = .live
    game.players[0].pos = Vec(x: 1, y: PracticeEngine.net+2)
    game.players[0].destination = game.players[0].pos
    game.launch(1, aim: game.players[0].pos, kind: .cross)
    game.ball = game.players[0].pos
    game.flight!.contact = game.players[0].pos
    XCTAssertFalse(game.quickNetFeet(0))
    game.returnBall(0, volley: true, random: { 0.5 })
    XCTAssertTrue(game.quickNetFeet(0))
    XCTAssertFalse(game.quickNetFeet(1))
    var gesture = PracticeGesture(side: 0, movementGain: 1.8)
    _ = gesture.update(at: .zero)
    guard case .run(let delta)? = gesture.update(at: Vec(x: 0.35,y: 0), ended: true) else {
      return XCTFail("A short lateral movement must register after a volley")
    }
    XCTAssertEqual(delta.x, 0.63, accuracy: 0.001)
    game = try JSONDecoder().decode(PracticeEngine.self, from: JSONEncoder().encode(game))
    game.move(0,to: Vec(x: 9.8,y: game.players[0].pos.y))
    var peak = 0.0
    for _ in 0..<100 { game.updateFootwork(1/120); peak = max(peak,game.players[0].velocity.length) }
    XCTAssertGreaterThan(peak, 11.9)
    XCTAssertLessThanOrEqual(peak, 12.0001)
    game.end(0,reason: "",tip: "")
    XCTAssertFalse(game.quickNetFeet(0))
    game.start()
    XCTAssertNotEqual(game.players[0].madeNetVolley,true)
  }

  func testGarmentHasNoOpenEdgesAndEveryTriangleSurvivesWideAndBentPoses() {
    let garment = TennisShorts.mesh, triangles = garment.indices
    var uses: [UInt64:Int] = [:], balance: [UInt64:Int] = [:]
    for i in stride(from: 0, to: triangles.count, by: 3) {
      for k in 0..<3 {
        let a = triangles[i+k], b = triangles[i+(k+1)%3]
        let edge = UInt64(min(a,b)) << 32 | UInt64(max(a,b))
        uses[edge,default: 0] += 1; balance[edge,default: 0] += a<b ? 1 : -1
      }
    }
    XCTAssertTrue(uses.values.allSatisfy { $0 == 2 })
    XCTAssertTrue(balance.values.allSatisfy { $0 == 0 })
    for t in 0...100 {
      let phase = Float(t)/100
      var pose = AthletePose()
      pose[.leftHip] = [-0.14,0.78,0]; pose[.rightHip] = [0.14,0.78,0]
      pose[.leftKnee] = [-0.23-phase*0.26,0.42,-phase*0.29]
      pose[.rightKnee] = [0.24+phase*0.15,0.45,0.12-phase*0.38]
      let p = garment.positions(for: pose)
      for i in stride(from: 0, to: triangles.count, by: 3) {
        let a = p[Int(triangles[i])], b = p[Int(triangles[i+1])], c = p[Int(triangles[i+2])]
        XCTAssertGreaterThan(simd_length(simd_cross(b-a,c-a)), 0.000001)
      }
    }
  }
}
