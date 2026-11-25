import Foundation

struct TacticalStats: Codable {
  var approaches = 0
  var splitSteps = 0
  var timedSplits = 0
  var volleys = 0
  var overheads = 0
  var openCourtShots = 0
  var netWinners = 0
}

enum CourtTactics {
  static func travelTime(distance: Double, speed: Double) -> Double {
    let acceleration = 11.0
    let ramp = speed / acceleration
    let rampDistance = speed * speed / (2 * acceleration)
    return distance <= rampDistance
      ? sqrt(2 * distance / acceleration)
      : ramp + (distance - rampDistance) / speed + 0.2
  }

  static func netCoverage(side: Int, opponentContact: Vec) -> Vec {
    let baseline = side == 0 ? PracticeEngine.length : 0
    let y = PracticeEngine.net + (side == 0 ? 2.8 : -2.8)
    let depth = max(1, abs(baseline - opponentContact.y))
    let angle =
      (atan2(-opponentContact.x, depth) + atan2(PracticeEngine.width - opponentContact.x, depth))
      / 2
    let x = opponentContact.x + tan(angle) * abs(y - opponentContact.y)
    return Vec(x: clamp(x, 1, PracticeEngine.width - 1), y: y)
  }

  static func practiceLob(side: Int, opponentContact: Vec) -> Vec {
    let cover = netCoverage(side: 1 - side, opponentContact: opponentContact)
    return Vec(x: cover.x, y: PracticeEngine.net + (side == 1 ? 6.5 : -6.5))
  }

  static func openCourt(side: Int, opponent: Vec, overhead: Bool) -> Vec {
    Vec(
      x: opponent.x < PracticeEngine.width / 2 ? 6.73 : 1.5,
      y: side == 0 ? (overhead ? 3 : 2) : PracticeEngine.length - (overhead ? 3 : 2))
  }
}

extension PracticeEngine {
  func inSplitWindow(_ side: Int) -> Bool {
    guard phase == .live, let flight, flight.hitter == side, flight.fault == nil else { return false }
    let onReceivingSide = side == 0 ? flight.position.y < Self.net : flight.position.y > Self.net
    return onReceivingSide && flight.position.distance(to: flight.landing) <= 3
  }

  private func advancingToNet(_ side: Int) -> Bool {
    let player = players[side]
    let forward = (player.pos.y - player.destination.y) * (side == 0 ? 1 : -1)
    return followingApproach[side] || (forward > 0.15 && abs(player.destination.y - Self.net) < abs(player.pos.y - Self.net))
  }

  mutating func plantApproachAtBounce(_ side: Int) {
    guard (side == 0 || settings.local), advancingToNet(side), inSplitWindow(side) else { return }
    beginSplit(side)
  }

  mutating func beginSplit(_ side: Int) {
    guard phase.isPlaying,
      phase != .serving || servePreparation?.server != side else { return }
    let atBounce = inSplitWindow(side)
    let planting = atBounce && advancingToNet(side)
    if planting {
      players[side].destination = players[side].pos
      players[side].velocity = .zero
      followingApproach[side] = false
    }
    if atBounce {
      noteDemoSplit(side)
      if side == 0, let white = coach.recovery?.white,
        players[0].pos.distance(to: white) <= Self.contactRadius {
        updateCoachRecovery()
        coach.noteRecoverySplit()
      }
    }
    guard planting || time - splitStarted[side] >= 0.28 else {
      if atBounce { splitTimed[side] = true }
      return
    }
    let serveSplit = phase == .serving && (opponentContactDue(side).map { $0 <= 0.3 } ?? false)
    splitTimed[side] = atBounce || serveSplit
    splitStarted[side] = time
    tactics[side].splitSteps += 1
    if splitTimed[side] { tactics[side].timedSplits += 1 }
  }

  func opponentContactDue(_ side: Int) -> Double? {
    if phase == .serving, let serve = servePreparation, serve.server != side, let elapsed = serve.tossElapsed {
      return max(0, ServePreparation.tossDuration - elapsed)
    }
    guard let flight, flight.hitter == side, flight.fault == nil,
      let window = contactWindow(1 - side) else { return nil }
    return window.entry * flight.duration - flight.elapsed
  }

  func splitProgress(_ side: Int) -> Double? {
    let elapsed = time - splitStarted[side]
    return elapsed >= 0 && elapsed <= 0.18 ? elapsed / 0.18 : nil
  }

}
