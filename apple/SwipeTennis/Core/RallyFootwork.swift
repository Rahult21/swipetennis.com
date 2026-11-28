import Foundation

enum RallyContact: String, Codable {
  case neutral, planted, stretched, diving
  var pace: Double {
    switch self {
    case .planted: return 1.2
    case .stretched, .diving: return 0.8
    case .neutral: return 1
    }
  }
}

extension CourtPlayer {
  var energyLevel: Double { energy ?? 1 }

  func rallyContact(gap: Double) -> RallyContact {
    if gap <= PracticeEngine.contactRadius, settled >= 0.18, velocity.length < 2.2 { return .planted }
    if gap > PracticeEngine.contactRadius || velocity.length > 3.2 || (settled > 0 && settled < 0.075) { return .stretched }
    return .neutral
  }

  mutating func expendEnergy(pace: Double, distance: Double, dt: Double, late: Bool) {
    let excess = max(0, pace - 1)
    let spent = distance * excess * (late ? 0.036 : 0.024)
    let recovered = excess < 0.06 ? dt * 0.005 : 0
    energy = clamp(energyLevel - spent + recovered, 0, 1)
  }
}

extension PracticeEngine {
  var lateMatch: Bool {
    if scoring.format == .tiebreak {
      return (scoring.points.max() ?? 0) >= (settings.clubEncounter == nil ? 4 : 5)
    }
    return scoring.games.reduce(0, +) >= 5
  }

  func runningLimits(_ side: Int, toward target: Vec, distance: Double) -> (speed: Double, acceleration: Double, effort: Double) {
    let p = players[side], bot = side == 1 && !settings.local
    let chasing = bot && flight?.hitter == 0 && phase == .live
    let effort = bot ? (chasing ? 1+0.5*clamp((distance-2)/5,0,1) : 1) : p.runPace ?? 1
    let gait: Double
    if !bot && p.receiveFlight == contactSerial { gait = 1 }
    else if bot { gait = min(1,0.90*effort) }
    else if quickNetFeet(side) { gait = 2*min(1,effort) }
    else { gait = (showsGoldenContact(side) ? 1.5 : 1)*clamp(effort,0.6,1.5) }
    let fatigue = 0.70+0.30*min(1,p.energyLevel/0.9)
    let turning = flight?.receiverWrongFooted == true && flight?.hitter == 1-side && phase == .live
    let base = bot ? settings.opponentRunSpeed(chasingDrop:flight?.hitter == 0 && flight?.kind == .drop) : 6
    let forwardVelocity = p.velocity.x*(target.x-p.pos.x)+p.velocity.y*(target.y-p.pos.y)
    let braking = p.velocity.length > 1 && (forwardVelocity < 0 || distance < p.velocity.length*p.velocity.length/18)
    let traction = settings.surface == .clay ? (braking ? 0.71 : 0.96) : settings.surface == .hard ? 1.07 : (braking ? 0.89 : 1)
    let acceleration = 11*(bot ? PracticeSettings.opponentMovementMultiplier : gait)*fatigue*traction
    return (base*gait*fatigue*(turning ? 0.6 : 1),acceleration,effort)
  }

  /// Horizontal distance a runner can cover before a specific ball arrives.
  /// A wrong-footed first step uses time to reverse the existing velocity.
  func runningReach(_ side: Int, toward target: Vec, in seconds: Double) -> Double {
    let p = players[side], distance = p.pos.distance(to:target)
    guard distance > 0.001, seconds > 0 else { return 0 }
    let (cap,acceleration,_) = runningLimits(side,toward:target,distance:distance)
    let toward = min(cap,(p.velocity.x*(target.x-p.pos.x)+p.velocity.y*(target.y-p.pos.y))/distance)
    let ramp = min(seconds,(cap-toward)/acceleration)
    return max(0,toward*ramp+0.5*acceleration*ramp*ramp+cap*(seconds-ramp))
  }

  /// Take the last running steps toward a wide ball, then leave the court
  /// to lift it. An ordinary stroke in racket reach keeps its input window.
  mutating func prepareJumpLob(_ side: Int, incoming: BallFlight, dt: Double) {
    let p = players[side]
    guard demo == nil, queuedPower == nil, assist == nil, incoming.hitter != side,
          incoming.fault == nil, incoming.power == nil, incoming.missedSwingWindow != true,
          p.netEffort == nil, incoming.progress < 0.98 else { return }
    let impact = incoming.kind == .drop ? 0.91 : 0.99
    let remaining = incoming.time(at: impact)-incoming.elapsed
    guard remaining > 0.07 && remaining <= 0.82 else { return }
    let ball = incoming.worldBall(at: impact)
    let target = ball.courtPosition
    let dx = target.x-p.pos.x, dy = target.y-p.pos.y
    let gap = hypot(dx,dy)
    guard gap > Self.contactRadius+0.30, gap <= 4.0 else { return }
    let direction = Vec(x: dx/gap,y: dy/gap)
    let ordinaryTravel = runningReach(side,toward:target,in:remaining)
    // If the current position already offers a normal stroke, the player
    // keeps that timing window even when the end of the rebound is farther away.
    guard gap-ordinaryTravel > Self.contactRadius, contactWindow(side) == nil else { return }
    // Pick a landing behind the string bed. At most a racket's reach is
    // supplied by the airborne stroke; the rest is covered by moving feet.
    var landing = Self.own(side,Vec(x: target.x-0.76*direction.x,y: target.y-0.76*direction.y))
    if side == 0 || settings.local { landing.y = receivingDepth(landing.y,side:side) }
    let travel = p.pos.distance(to:landing)
    guard landing.distance(to:target) <= 0.91,
          remaining <= max(0.34,0.16+travel/5.2), travel <= 7.1*remaining else { return }
    players[side].netEffort = NetEffort(stroke:.jumpLob,serial:contactSerial,startTime:time-dt,
      impactTime:time-dt+remaining,progress:impact,from:p.pos,landing:landing,target:ball,
      reachable:true,afterBounce:true,entryVelocity:p.velocity)
    players[side].destination = landing
    players[side].recoveryFlight = nil
  }

  // A committed lateral or forward chase can finish in a dive beyond ordinary racket reach.
  mutating func attemptRunningDive(_ side: Int, incoming: BallFlight, guided: Bool = false) {
    let p = players[side]
    guard demo == nil, assist == nil, queuedPower == nil, incoming.power == nil, incoming.fault == nil,
          !incoming.trainingApproach, incoming.opponentError == nil, incoming.dropReachable != false, (guided || incoming.kind != .drop),
          p.netEffort == nil, p.diveDecision != contactSerial, incoming.progress >= 0.84,
          (guided || !BallContactWindow.inServiceBox(p.pos, side: side)) else { return }
    let remaining = incoming.time(at: 1) - incoming.elapsed
    guard remaining > 0, remaining <= 0.22 else { return }
    let impact = incoming.worldBall(at: 1)
    let to = guided ? impact.courtPosition : incoming.contact
    let gap = p.pos.distance(to: to)
    let toward = (p.velocity.x * (to.x - p.pos.x) + p.velocity.y * (to.y - p.pos.y)) / max(0.001, gap)
    let residual = gap - (guided ? runningReach(side, toward: to, in: remaining) : max(0, toward) * remaining)
    if guided {
      guard residual > Self.contactRadius, residual <= 1.85, contactWindow(side) == nil else { return }
    } else {
      guard p.velocity.length > 1.8, toward > 1.2, residual > 1.15, residual <= 1.85 else { return }
    }
    let ahead = (p.pos.y - to.y) * (side == 0 ? 1.0 : -1.0)
    guard guided || ahead >= -0.15 || abs(to.x - p.pos.x) >= abs(ahead) else { return }
    players[side].diveDecision = contactSerial
    let landing = Self.own(side, Vec(x: to.x - (to.x - p.pos.x) * 0.62 / gap,
                                    y: to.y - (to.y - p.pos.y) * 0.62 / gap))
    players[side].netEffort = NetEffort(stroke: .dive, serial: contactSerial, startTime: time,
      impactTime: time + remaining, progress: 1, from: p.pos, landing: landing,
      target: impact, reachable: true, afterBounce: true)
    players[side].destination = landing
  }
}
