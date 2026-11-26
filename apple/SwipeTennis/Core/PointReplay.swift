import Foundation

struct RallyFrame {
  let near: AthletePose
  let far: AthletePose
  let ball: CourtPoint3D

  func blended(to next: Self, by u: Float) -> Self {
    Self(near: near.blended(to: next.near, by: u), far: far.blended(to: next.far, by: u),
      ball: ball + (next.ball - ball) * u)
  }
}

struct RecordedStrike {
  let time: Double
  let hitter: Int
  let point: CourtPoint3D
  let gain: Double
  let power: CourtPower?
}

/// Only the active point is retained. All three cameras read the same fixed-step samples.
struct PointReplay {
  static let tick = 1.0 / 120
  static let speed = 0.5
  private(set) var frames: [RallyFrame] = []
  private(set) var strikes: [RecordedStrike] = []
  private var cuts: Set<Int> = []
  private var gap = true
  private(set) var ceremonyStart: Double?
  var duration: Double { Double(max(0, frames.count - 1)) * Self.tick }
  var canPlay: Bool { !strikes.isEmpty && frames.count > 1 }
  var opening: Double {
    if let winner = strikes.last, let power = winner.power {
      return max(0, winner.time - (power == .ace ? 1.05 : 0.85))
    }
    return max(0, strikes.dropLast().last.map { $0.time - 0.65 } ?? 0)
  }

  mutating func record(_ frame: RallyFrame, game: PracticeEngine, hit: Bool) {
    guard game.demo == nil else { return }
    let active = game.phase == .live || game.servePreparation?.isTossing == true ||
      (game.pointResolution?.elapsed ?? .infinity) <= PointResolution.resultDelay
    guard active else { gap = true; return }
    if gap { cuts.insert(frames.count); gap = false }
    frames.append(frame)
    if hit, let flight = game.flight {
      strikes.append(RecordedStrike(time: duration, hitter: flight.hitter, point: frame.ball,
        gain: flight.power?.contactGain ?? 1, power: flight.power))
    }
  }

  func suffix(from first: Int) -> Self {
    var clip = Self()
    clip.frames = Array(frames.dropFirst(first))
    let origin = Double(first) * Self.tick
    clip.strikes = strikes.filter { $0.time >= origin - 0.000001 }.map {
      RecordedStrike(time: max(0,$0.time-origin), hitter: $0.hitter, point: $0.point, gain: $0.gain, power: $0.power)
    }
    clip.cuts = Set(cuts.filter { $0 >= first }.map { $0 - first })
    return clip
  }

  func frame(at seconds: Double) -> RallyFrame? {
    guard !frames.isEmpty else { return nil }
    let index = clamp(seconds, 0, duration) / Self.tick
    let left = min(Int(index), frames.count - 1)
    let right = min(left + 1, frames.count - 1)
    let fraction = Float(index - Double(left))
    if left == right || fraction <= 0.00001 || cuts.contains(right) { return frames[left] }
    return frames[left].blended(to: frames[right], by: fraction)
  }
}

struct CourtPerformance {
  private var athletes = [AthleteMotion(), AthleteMotion()]
  private var serial: Int
  private(set) var frame: RallyFrame?
  private(set) var replay = PointReplay()

  init(game: PracticeEngine) { serial = game.contactSerial }

  mutating func update(game: PracticeEngine, dt: Double, reduceMotion: Bool = false) {
    let hit = serial != game.contactSerial && game.flight != nil
    serial = game.contactSerial
    let near = athletes[0].sample(game: game, side: 0, hit: hit && game.flight?.hitter == 0, dt: dt, reduceMotion: reduceMotion)
    let far = athletes[1].sample(game: game, side: 1, hit: hit && game.flight?.hitter == 1, dt: dt, reduceMotion: reduceMotion)
    let next = RallyFrame(near: near, far: far, ball: game.worldBall)
    frame = next
    if dt > 0 { replay.record(next, game: game, hit: hit) }
  }
}

extension PointReplay {
  /// Cut to the final two steps at the net. This ceremony never advances the match clock.
  mutating func appendHandshake() {
    guard let last = frames.last else { return }
    cuts.insert(frames.count)
    let start = duration + Self.tick
    ceremonyStart = start
    var model = PracticeEngine(settings:.init(local:true))
    var athletes = [AthleteMotion(),AthleteMotion()]
    for sample in 0..<270 {
      let t = Double(sample)*Self.tick
      let walk = StrokeAnimation.ease(t/1.05)
      let reach = Float(StrokeAnimation.ease((t-0.78)/0.45) * (1-StrokeAnimation.ease((t-1.82)/0.41)))
      var pair = [AthletePose]()
      for side in 0...1 {
        let sign:Double = side == 0 ? 1 : -1
        let distance = 0.54 + 1.18*(1-walk)
        let feet = Vec(x:4.115-sign*0.14,y:PracticeEngine.net+sign*distance)
        model.players[side].pos = feet
        model.players[side].destination = Vec(x:feet.x,y:PracticeEngine.net+sign*0.54)
        model.players[side].velocity = Vec(x:0,y: -sign*1.18*6*max(0,t/1.05)*max(0,1-t/1.05)/1.05)
        var pose = athletes[side].sample(game:model,side:side,hit:false,dt:Self.tick,reduceMotion:false)
        let grip = pose[.grip]
        let meet = CourtPoint3D(4.115,1.19 + 0.027*sin(Float(t-1.22)*15),Float(PracticeEngine.net))
        pose[.grip] += (meet-grip)*reach
        pose[.rightElbow] += (meet-grip)*reach*0.44
        pair.append(pose)
      }
      frames.append(RallyFrame(near:pair[0],far:pair[1],ball:last.ball))
    }
  }
}
