import Foundation

/// Regenerate the browser athlete from the same motion samples used by live iOS play and replay.
/// From the repo root: swiftc apple/SwipeTennis/Core/*.swift apple/Tools/ExportPracticePoses.swift -o /tmp/export-practice-poses
/// /tmp/export-practice-poses > src/practice-poses.json
@main struct ExportPracticePoses {
  struct Frame: Encodable {
    let t: Double
    let joints: [[Int]]
    let heel: Int
    init(_ time: Double, _ pose: AthletePose, feet: Vec, side: Int) {
      t = time
      let sign = side == 0 ? 1 : -1
      joints = BodyJoint.allCases.map { joint in
        let p = pose[joint] - feet.world()
        return [Int((p.x * 1000).rounded()) * sign, Int((p.y * 1000).rounded()), Int((-p.z * 1000).rounded()) * sign]
      }
      heel = Int((pose.heelPitch * 1000).rounded())
    }
  }

  static func stroke(offset: Double, volley: Bool = false, serve: Bool = false) -> [Frame] {
    var game = PracticeEngine(settings: .init(local: true))
    game.phase = .live
    let feet = Vec(x: 4, y: volley ? 15 : 23.4)
    game.players[0].pos = feet
    game.players[0].destination = feet
    let incoming = BallFlight(from: Vec(x: 4+offset, y: 1), landing: Vec(x: 4+offset, y: 22.3),
      contact: Vec(x: 4+offset, y: 23.4), duration: 2, hitter: 1, fault: nil, explanation: "", loft: 1)
    game.flight = incoming
    let entry = game.contactWindow(0)!.entry
    var motion = AthleteMotion()
    let times = [-0.74,-0.55,-0.38,-0.34,-0.30,-0.23,-0.145,-0.105,-0.085,-0.065,-0.035,0,0.04,0.085,0.15,0.22,0.35,0.42,0.48,0.60,0.70]
    var prior = times[0]
    return times.map { t in
      game.time = 2 + t
      if serve && t < 0 {
        game.phase = .serving
        var preparation = ServePreparation(server: 0, target: .zero, destination: .zero)
        preparation.elapsed = 2
        preparation.tossElapsed = ServePreparation.tossDuration + t
        game.servePreparation = preparation
      } else if t <= 0 { game.flight!.elapsed = entry * incoming.duration + t }
      if t == 0 {
        game.phase = .live
        game.servePreparation = nil
        game.launch(0, aim: Vec(x: 6, y: 2), kind: .cross, serve: serve, stroke: volley ? .volley : .groundstroke)
      }
      if serve && t > 0 {
        game.serveLanding?.elapsed = t
        if t >= ServeLanding.duration { game.serveLanding = nil }
      }
      let pose = motion.sample(game: game, side: 0, hit: t == 0, dt: t == 0 ? 0 : t - prior, reduceMotion: false)
      prior = t
      return Frame(t, pose, feet: feet, side: 0)
    }
  }

  static func main() throws {
    var game = PracticeEngine(settings: .init())
    var motion = AthleteMotion()
    let feet = game.players[1].pos
    func capture(_ t: Double) -> Frame {
      Frame(t, motion.sample(game: game, side: 1, hit: false, dt: 1.0 / 120, reduceMotion: false), feet: feet, side: 1)
    }
    let rest = capture(0)
    game.phase = .live
    let ready = capture(0)
    game.phase = .point
    game.pointResolution = PointResolution(impact: nil, reaction: .init(frustration: 1))
    let reaction = [0.0,0.09,0.20,0.31,0.40,0.48,0.55,0.70,0.85].map { t in
      game.pointResolution!.elapsed = t
      return capture(t)
    }
    struct Clips: Encodable {
      let joints = BodyJoint.allCases.map { String(describing: $0) }
      let rest, ready: Frame
      let backhand, forehand, backVolley, foreVolley, serve, reaction: [Frame]
    }
    let clips = Clips(rest: rest, ready: ready, backhand: stroke(offset: -0.58), forehand: stroke(offset: 0.58),
      backVolley: stroke(offset: -0.58, volley: true), foreVolley: stroke(offset: 0.58, volley: true),
      serve: stroke(offset: 0.58, serve: true), reaction: reaction)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    FileHandle.standardOutput.write(try encoder.encode(clips))
    print()
  }
}
