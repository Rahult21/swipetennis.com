import XCTest
import simd
@testable import TennisCore

final class GroundstrokeSpacingTests: XCTestCase {
  private func checkContact(_ frame: RallyFrame, side: Int, backhand: Bool,
                            file: StaticString = #filePath, line: UInt = #line) {
    let pose = side == 0 ? frame.near : frame.far
    let facing: Float = side == 0 ? 1 : -1
    let hittingSide = backhand ? -facing : facing
    let hips = (pose[.leftHip] + pose[.rightHip]) / 2
    let width = (frame.ball.x - hips.x) * hittingSide
    let hand = (pose[.grip].x - hips.x) * hittingSide
    let lead = (hips.z - frame.ball.z) * facing
    XCTAssertGreaterThan(width, 0.70, file: file, line: line)
    XCTAssertGreaterThan(hand, 0.30, file: file, line: line)
    XCTAssertTrue(lead > 0 && lead < width, "Contact should be slightly ahead and to the side", file: file, line: line)
    XCTAssertLessThan(simd_distance(pose[.strings], frame.ball), 0.002, file: file, line: line)
    if backhand {
      XCTAssertGreaterThan(pose.supportGrip, 0.90, file: file, line: line)
      XCTAssertEqual(simd_distance(pose[.grip], pose[.leftHand]), 0.095, accuracy: 0.006, file: file, line: line)
    }
  }

  func testWideReturnsOnBothWingsAndBothBaselines() throws {
    for side in 0...1 {
      for wing in [-1.0, 1.0] {
        func baselinePosition(x: Double, depth: Double) -> Vec {
          Vec(x: side == 0 ? x : PracticeEngine.width-x, y: side == 0 ? depth : PracticeEngine.length-depth)
        }
        var game = PracticeEngine(settings: .init(local: true, surface: .hard, allCourtTraining: false))
        game.phase = .live
        let middle = PracticeEngine.width/2
        game.players[side].pos = baselinePosition(x: middle, depth: 22.6)
        game.players[1-side].pos = baselinePosition(x: middle, depth: 1)
        for i in game.players.indices { game.players[i].destination = game.players[i].pos }
        game.launch(1-side, aim: baselinePosition(x: middle+wing*2.65, depth: 21.5), kind: .cross)
        game.apply(.guidedMove(.receive), side: side)
        var motion = CourtPerformance(game: game)
        var reduced = CourtPerformance(game: game)
        for _ in 0..<420 {
          game.step(PointReplay.tick, random: { 0.8 })
          motion.update(game: game, dt: PointReplay.tick)
          reduced.update(game: game, dt: PointReplay.tick, reduceMotion: true)
          if game.flight?.hitter == side { break }
        }
        XCTAssertEqual(game.flight?.hitter, side)
        checkContact(try XCTUnwrap(motion.frame), side: side, backhand: wing < 0)
        checkContact(try XCTUnwrap(reduced.frame), side: side, backhand: wing < 0)
        let strike = try XCTUnwrap(motion.replay.strikes.last)
        checkContact(try XCTUnwrap(motion.replay.frame(at: strike.time)), side: side, backhand: wing < 0)
      }
    }
  }

  func testStationaryStudioGroundstrokesUseTheSameSideContact() throws {
    for shot in [StudioStroke.forehand, .backhand] {
      let clip = try XCTUnwrap(StrokeStudioClip(shot))
      checkContact(try XCTUnwrap(clip.frame(clip.contactTime)), side: 0, backhand: shot == .backhand)
    }
  }
}
