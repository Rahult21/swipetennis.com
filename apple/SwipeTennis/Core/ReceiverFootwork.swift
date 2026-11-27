import Foundation
import simd

/// Presentation only. Positions are metres in the receiver's right/up/courtward frame.
/// The service clock continues across contact via the outgoing serve's flight time.
struct ReceiverFootwork {
  var left = CourtPoint3D.zero
  var right = CourtPoint3D.zero
  var hips = CourtPoint3D.zero
  var lean: Float = 0
  var heel: Float = 0
  var readyHands: Float = 0
  var landing = false
  var finalFlight = false

  static func pose(game: PracticeEngine, side: Int, reduceMotion: Bool) -> Self {
    let clock: Float
    let sinceImpact: Float
    if game.phase == .serving, let serve = game.servePreparation, serve.server != side {
      clock = Float(serve.elapsed)
      let tossRate: Double = game.queuedPower == .ace ? 1.25 : 1
      sinceImpact = serve.tossElapsed.map { Float(($0 - ServePreparation.tossDuration) / tossRate) } ?? -10
    } else if game.phase == .live, let ball = game.flight, ball.serve, ball.hitter != side, ball.elapsed <= 0.54 {
      // The pre-toss rhythm has completely yielded to the split by contact.
      clock = 4
      sinceImpact = Float(ball.elapsed)
    } else { return Self() }

    func ease(_ value: Float, _ start: Float, _ end: Float) -> Float {
      let t = max(0, min(1, (value - start) / (end - start)))
      return t*t*(3-2*t)
    }
    func arc(_ value: Float, _ start: Float, _ end: Float) -> Float {
      let t = max(0, min(1, (value - start) / (end - start)))
      return 4*t*(1-t)
    }
    let moving = ease(Float(game.players[side].velocity.length), 0.4, 2.8)
    let strength = (1-moving) * (reduceMotion ? 0 : 1)
    let posture = (1-0.8*moving) * (reduceMotion ? 0.4 : 1)
    let firstHop = arc(clock, 0.105, 0.34)
    let gather = ease(clock, 0, 0.09) * (1-ease(clock, 0.09, 0.17))
    let catchWeight = ease(clock, 0.26, 0.39) * (1-ease(clock, 0.39, 0.53))
    let waiting = ease(clock, 0.36, 0.60)
    let prepareSplit = ease(sinceImpact, -0.40, -0.18)
    let launch = ease(sinceImpact, -0.23, -0.105)
    let air = arc(sinceImpact, -0.133, 0.133)
    let travel = ease(sinceImpact, -0.133, 0.133)
    let absorb = ease(sinceImpact, 0.046, 0.16) * (1-ease(sinceImpact, 0.16, 0.45))
    // Alternate left and right pressure during a long service routine. Both
    // shoes settle before takeoff, independent of when the server starts.
    let rhythm = sin(max(0, clock-0.44) * 2 * .pi / 0.64)
    let steps = waiting * (1-prepareSplit)
    let leftStep = max(0,rhythm)*steps, rightStep = max(0,-rhythm)*steps
    let after = 1-ease(sinceImpact, 0.13, 0.50)
    let wide = 0.095*ease(clock, 0.12, 0.33)
    var result = Self()
    result.finalFlight = sinceImpact >= -0.133 && sinceImpact < 0.133 && strength > 0
    result.landing = sinceImpact >= 0.133
    if !result.landing {
      let lift = 0.069*firstHop + 0.091*air
      let span = wide + 0.047*travel
      result.left = [-span, lift + 0.045*leftStep, 0.17*travel + 0.042*leftStep]
      result.right = [span, lift + 0.045*rightStep, 0.17*travel + 0.042*rightStep]
      result.left *= strength; result.right *= strength
    }
    let load = 0.039*gather + 0.052*catchWeight + 0.12*waiting*(1-launch) + 0.115*absorb
    result.hips = [0.023*(rightStep-leftStep)*strength, (0.055*firstHop+0.066*air)*strength-load*posture, 0.055*travel*after*strength]
    result.lean = (0.144*waiting*(1-0.60*launch)*after + 0.046*absorb)*posture
    result.heel = (0.11*firstHop+0.075*waiting*(1-prepareSplit)+0.16*air)*strength
    result.readyHands = ease(clock, 0.11, 0.40)*after*(1-moving)
    return result
  }
}
