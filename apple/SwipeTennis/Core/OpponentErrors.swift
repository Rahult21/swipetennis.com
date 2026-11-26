import Foundation

enum OpponentError: String, Codable, CaseIterable {
  case net, wide, unreachable, long
}

extension Difficulty {
  var title: String { self == .tough ? "Hard" : rawValue }
  var errorInterval: ClosedRange<Int> {
    switch self {
    case .easy: return 4...8
    case .medium: return 6...12
    case .tough: return 10...16
    }
  }
}

/// Counts ordinary opponent return opportunities across points; controlled lob feeds are excluded.
struct OpponentErrors: Codable {
  private(set) var remaining: Int?

  mutating func next(
    difficulty: Difficulty, canMissByFootwork: Bool, random: () -> Double
  ) -> OpponentError? {
    if remaining == nil {
      let range = difficulty.errorInterval
      remaining = range.lowerBound + Int(clamp(random(), 0, 0.999999) * Double(range.count))
    }
    remaining! -= 1
    guard remaining == 0 else { return nil }
    remaining = nil
    let choices = OpponentError.allCases.filter { canMissByFootwork || $0 != .unreachable }
    return choices[Int(clamp(random(), 0, 0.999999) * Double(choices.count))]
  }

  mutating func resetAfterMiss() { remaining = nil }
}

extension PracticeEngine {
  mutating func prepareOpponentReply(random: () -> Double) {
    guard !settings.local else { return }
    if prepareApproachReply(random: random) { return }
    guard !settings.local, let incoming = flight, incoming.hitter == 0,
      incoming.fault == nil, !incoming.opponentReplyPrepared else { return }
    flight!.opponentReplyPrepared = true
    if incoming.kind == .drop || incoming.kind == .slice {
      let isDrop = incoming.kind == .drop
      let speed = (isDrop ? 7.0 : settings.style.speed) * settings.botSpeed
      let travel = CourtTactics.travelTime(distance: players[1].pos.distance(to: incoming.contact), speed: speed)
      let succeeds = !isDrop || dropReturns.next(difficulty: settings.difficulty, random: random)
      let reaction = isDrop ? 0.06 : settings.botReaction
      flight!.duration = max(incoming.duration, (travel + reaction + 0.2) / 0.86)
      if isDrop {
        flight!.dropReachable = succeeds
        // Every drop is chased. A missed read begins late and arrives after the low second bounce.
        if !succeeds { reactAt = time + max(0.2, flight!.duration - travel + 0.2) }
        else { reactAt = time + reaction }
      }
      return // Protected touch-shot returns do not consume an ordinary-error opportunity.
    }
    guard !incoming.trainingApproach else { return }
    let error = opponentErrors.next(
      difficulty: settings.difficulty,
      canMissByFootwork: players[1].pos.distance(to: incoming.contact) > 2.2,
      random: random)
    flight!.opponentError = error
    if error == .unreachable {
      // A late chase stops short of contact. Keep a real, visible gap instead of faking a hit.
      let contact = incoming.contact
      let from = players[1].pos
      let distance = from.distance(to: contact)
      flight!.missedChaseTarget = Self.own(1, Vec(
        x: contact.x + (from.x - contact.x) / distance * 1.9,
        y: contact.y + (from.y - contact.y) / distance * 1.9))
    }
  }
}
