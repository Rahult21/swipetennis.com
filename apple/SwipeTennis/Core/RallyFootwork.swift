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

  // A committed lateral or forward chase can finish in a dive beyond ordinary racket reach.
  mutating func attemptRunningDive(_ side: Int, incoming: BallFlight) {
    let p = players[side]
    guard demo == nil, assist == nil, queuedPower == nil, incoming.power == nil, incoming.fault == nil,
          !incoming.trainingApproach, incoming.opponentError == nil, incoming.dropReachable != false, incoming.kind != .drop,
          p.netEffort == nil, p.diveDecision != contactSerial, incoming.progress >= 0.84,
          !BallContactWindow.inServiceBox(p.pos, side: side), p.velocity.length > 1.8 else { return }
    let remaining = incoming.duration - incoming.elapsed
    guard remaining > 0, remaining <= 0.22 else { return }
    let to = incoming.contact
    let gap = p.pos.distance(to: to)
    let toward = (p.velocity.x * (to.x - p.pos.x) + p.velocity.y * (to.y - p.pos.y)) / max(0.001, gap)
    let residual = gap - max(0, toward) * remaining
    guard toward > 1.2, residual > 1.15, residual <= 1.85 else { return }
    let ahead = (p.pos.y - to.y) * (side == 0 ? 1.0 : -1.0)
    guard ahead >= -0.15 || abs(to.x - p.pos.x) >= abs(ahead) else { return }
    players[side].diveDecision = contactSerial
    let landing = Self.own(side, Vec(x: to.x - (to.x - p.pos.x) * 0.62 / gap,
                                    y: to.y - (to.y - p.pos.y) * 0.62 / gap))
    players[side].netEffort = NetEffort(stroke: .dive, serial: contactSerial, startTime: time,
      impactTime: time + remaining, progress: 1, from: p.pos, landing: landing,
      target: incoming.worldBall(at: 1), reachable: true, afterBounce: true)
    players[side].destination = landing
  }
}
