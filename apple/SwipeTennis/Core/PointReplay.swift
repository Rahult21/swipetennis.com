import Foundation
import simd

struct BounceImpression {
  let serial: Int
  let position: Vec
  let direction: Float
  let surface: CourtSurface
  var age: Double

  var lifetime: Double {
    switch surface { case .clay: return 3.8; case .grass: return 0.68; case .hard: return 0.24 }
  }
  var visibility: Float { Float(clamp((lifetime - age) / (lifetime * 0.45), 0, 1)) }
}

struct RallyFrame {
  let near: AthletePose
  let far: AthletePose
  let ball: CourtPoint3D
  var bounce: BounceImpression? = nil
  var ballRotation = simd_quatf(angle:0,axis:[0,1,0])

  func blended(to next: Self, by u: Float) -> Self {
    var mark = u >= 1 ? next.bounce : bounce
    if let old = bounce, let new = next.bounce, old.serial == new.serial {
      mark?.age = old.age + (new.age - old.age) * Double(u)
    }
    return Self(near: near.blended(to: next.near, by: u), far: far.blended(to: next.far, by: u),
      ball: ball + (next.ball - ball) * u, bounce:mark,ballRotation:simd_slerp(ballRotation,next.ballRotation,u))
  }
}

struct RecordedStrike {
  let time: Double
  let hitter: Int
  let point: CourtPoint3D
  let gain: Double
  let power: CourtPower?
  var blocked = false
}

/// Only the active point is retained. All three cameras read the same fixed-step samples.
struct PointReplay {
  static let tick = 1.0 / 120
  static let speed = 0.5
  private(set) var frames: [RallyFrame] = []
  private(set) var strikes: [RecordedStrike] = []
  private(set) var bounceTimes: [Double] = []
  private var recordedBounce: Int?
  /// The final bounce belongs to this strike only if it happens after contact.
  var lastShotBounceTime: Double? {
    guard let hit = strikes.last else { return nil }
    return bounceTimes.first { $0 >= hit.time }
  }
  var contactWindow: ClosedRange<Double>? {
    guard let strike = strikes.last else { return nil }
    let low = max(0,strike.time-0.43), high = min(duration,strike.time+0.36)
    return high-low >= Self.tick ? low...high : nil
  }
  static func loopTime(_ seconds: Double, in range: ClosedRange<Double>) -> Double {
    let length = range.upperBound-range.lowerBound
    guard length >= tick else { return range.lowerBound }
    return range.lowerBound + max(0,seconds-range.lowerBound).truncatingRemainder(dividingBy:length)
  }

  private(set) var decisions: [Int: DecisionSnapshot] = [:]
  private(set) var heights: [Int: ContactReading] = [:]
  private(set) var serviceRetry: PracticeEngine?
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
    if game.phase == .serving, game.scoring.server == 0, let preparation = game.servePreparation,
       !preparation.requested, !preparation.isTossing { serviceRetry = game }
    let active = game.phase == .live || game.servePreparation?.isTossing == true ||
      (game.pointResolution?.elapsed ?? .infinity) <= PointResolution.resultDelay
    guard active else { gap = true; return }
    if gap { cuts.insert(frames.count); gap = false }
    frames.append(frame)
    if let mark = frame.bounce, mark.serial != recordedBounce {
      recordedBounce = mark.serial
      bounceTimes.append(duration)
    }
    if hit, let flight = game.flight {
      if flight.fault == nil {
        let receiver = 1-flight.hitter
        decisions[receiver] = DecisionSnapshot(game: game, frame: frame, receiver: receiver)
      }
      if !flight.serve { heights[flight.hitter] = ContactReading(frame: frame, hitter: flight.hitter, flight: flight) }
      strikes.append(RecordedStrike(time: duration, hitter: flight.hitter, point: frame.ball,
        gain: flight.power?.contactGain ?? 1, power: flight.power, blocked: flight.contactQuality == .stretched || flight.contactQuality == .diving))
    }
  }

  func suffix(from first: Int) -> Self {
    var clip = Self()
    clip.decisions = decisions
    clip.heights = heights
    clip.serviceRetry = serviceRetry
    clip.frames = Array(frames.dropFirst(first))
    let origin = Double(first) * Self.tick
    clip.bounceTimes = bounceTimes.filter { $0 >= origin }.map { $0 - origin }
    clip.strikes = strikes.filter { $0.time >= origin - 0.000001 }.map {
      RecordedStrike(time: max(0,$0.time-origin), hitter: $0.hitter, point: $0.point, gain: $0.gain, power: $0.power, blocked: $0.blocked)
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

struct ShoeContact {
  let x: Double
  let intensity: Double
  let surface: CourtSurface
}

struct CourtPerformance {
  private var shoeRaised = Array(repeating: false,count:4)
  private var lastStep = [-1.0,-1.0]
  private(set) var steps: [ShoeContact] = []
  private var athletes = [AthleteMotion(), AthleteMotion()]
  private var serial: Int
  private var bounceSerial: Int
  private var previousFlight: BallFlight?
  private var spin = BallRotation()
  private var mark: BounceImpression?
  private(set) var frame: RallyFrame?
  private(set) var replay = PointReplay()

  init(game: PracticeEngine) {
    serial = game.contactSerial
    bounceSerial = game.bounceSerial
    previousFlight = game.flight
  }

  mutating func update(game: PracticeEngine, dt: Double, reduceMotion: Bool = false) {
    let hit = serial != game.contactSerial && game.flight != nil
    serial = game.contactSerial
    let near = athletes[0].sample(game: game, side: 0, hit: hit && game.flight?.hitter == 0, dt: dt, reduceMotion: reduceMotion)
    let far = athletes[1].sample(game: game, side: 1, hit: hit && game.flight?.hitter == 1, dt: dt, reduceMotion: reduceMotion)
    mark?.age += dt
    if let current = mark, current.age >= current.lifetime { mark = nil }
    if bounceSerial != game.bounceSerial {
      // A return can follow a ground impact within one simulation step.
      let bounced = hit ? previousFlight : game.flight
      if let bounced, bounced.fault != "net" {
        let bearing = atan2(bounced.landing.x - bounced.from.x,bounced.landing.y - bounced.from.y)
        mark = BounceImpression(serial:game.bounceSerial,position:bounced.landing,direction:Float(bearing),
                                surface:game.settings.surface,age:0)
      }
      bounceSerial = game.bounceSerial
    }
    previousFlight = game.flight
    spin.advance(game,dt:dt)
    let next = RallyFrame(near:near,far:far,ball:game.worldBall,bounce:mark,ballRotation:spin.orientation)
    steps.removeAll(keepingCapacity:true)
    if dt > 0 && game.phase.isPlaying {
      for side in 0...1 {
        let body = side == 0 ? near : far
        let speed = game.players[side].velocity.length
        for foot in 0...1 {
          let index = side*2+foot
          let shoe = body[foot == 0 ? .leftShoe : .rightShoe]
          let lift = shoe.y - 0.06 - 0.14*sin(body.heelPitch)
          if lift > 0.048 { shoeRaised[index] = true }
          if lift < 0.022 && shoeRaised[index] {
            shoeRaised[index] = false
            if speed > 1 && game.time-lastStep[side] > 0.15 {
              steps.append(ShoeContact(x:Double(shoe.x),intensity:min(1,speed/5),surface:game.settings.surface))
              lastStep[side] = game.time
            }
          }
        }
      }
    }
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
