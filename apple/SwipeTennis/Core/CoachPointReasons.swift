import Foundation

struct ReturnDecision: Codable {
  let shot: ShotKind
  let redirected: Bool
  let shorterSide: Bool
  let split: Bool
  let baseAccuracy: Double
  var accuracy: Double { min(1, baseAccuracy * (split ? 1.2 : 1)) }

  var splitSummary: String {
    let base = Int((baseAccuracy * 100).rounded()), final = Int((accuracy * 100).rounded())
    if split && final == base { return "Timed split on your last shot · already at \(final)%" }
    return split ? "Timed split on your last shot · \(base)% → \(final)%"
      : "No timed split on your last shot · \(base)% placement"
  }
  var lesson: String {
    if redirected {
      let change = shorterSide ? "Changing direction to the shorter side was the lower-percentage play." : "Changing direction was the lower-percentage play."
      return change + " Rally crosscourt and wait for a short ball."
    }
    switch shot {
    case .angle: return "The short angle left little room. Aim deeper crosscourt."
    case .line: return "Down the line leaves less margin. Wait for a short ball to attack."
    case .drop: return "The drop shot missed its target. Give it more net clearance."
    case .lob: return "Aim your lob higher and toward the middle."
    default: return "Give your crosscourt target more room inside the lines."
    }
  }
}

extension PracticeEngine {
  var pointSplitSummary: String {
    if let flight, flight.hitter == 1, flight.fault == nil, coach.records.last?.winner == 1 {
      return players[0].splitForReturn == contactSerial
        ? "Timed split · ball stayed out of reach" : "No timed split before the missed return"
    }
    if let last = players[0].lastReturn { return last.splitSummary }
    return "No rally shot to apply a split bonus"
  }
}

extension CoachEvent {
  var compactReason: String {
    if let detail {
      if detail.hasPrefix("You did not return the ball") { return "Missed return: \(rule.resultAction.lowercased())" }
      switch detail {
      case "You did not reach the white recovery circle on a baseline exchange.": return "Missed the white recovery circle"
      case "You reached white, but did not tap to split before the next ball.": return "Reached white; missed the split step"
      case "Your short-ball return missed before you could follow it in.": return "Short-ball return missed"
      case "Your deep-ball return missed.": return "Deep-ball return missed"
      case "Your first-serve return missed.": return "First-serve return missed"
      case "Your second-serve return missed.": return "Second-serve return missed"
      case "Your first serve was not wide.": return "First serve was not wide"
      case "Your shot after the wide serve missed.": return "Wide serve: next shot missed"
      default: return detail
      }
    }
    switch rule {
    case .shortBallApproach: return success ? "Followed the short ball in" : "Short ball: stayed back"
    case .deepCenterLob: return success ? "Lobbed the deep ball to center" : "Deep ball: missed the center lob"
    case .firstServeBody: return success ? "Returned first serve at the server" : "First return went away from server"
    case .secondServeRise: return success ? "Took second serve early, inside baseline" : "Second serve: missed the early return"
    case .wideServeCross: return success ? "Served wide, then hit crosscourt" : "Wide serve: missed the crosscourt shot"
    case .changeDirectionApproach: return success ? "Changed direction and followed in" : "Changed direction but stayed back"
    case .recoveryAndSplit: return success ? "Recovered and split all point" : "Missed recovery or the split step"
    }
  }

  var reason: String {
    if let detail { return detail }
    switch rule {
    case .shortBallApproach:
      return success ? "You followed the short ball toward the net."
        : "You returned the short ball but did not follow it toward the net."
    case .deepCenterLob:
      return success ? "You lobbed a ball behind your baseline deep through center."
        : "The ball was behind your baseline; your return was not a center lob."
    case .firstServeBody:
      return success ? "You returned the first serve back at the server."
        : "Your first-serve return went away from the server."
    case .secondServeRise:
      return success ? "You returned the second serve inside the baseline, on the rise."
        : "You did not meet the second serve inside the baseline on the rise."
    case .wideServeCross:
      return success ? "You served wide, then played the next shot crosscourt."
        : "After serving wide, your next shot was not a crosscourt drive."
    case .changeDirectionApproach:
      return success ? "You changed direction and followed your shot toward the net."
        : "You changed direction but did not follow your shot toward the net."
    case .recoveryAndSplit:
      return success ? "You recovered to white, then split on every baseline exchange."
        : "You missed recovery to white or the split step before a baseline return."
    }
  }
}

extension CoachRule {
  var resultAction: String {
    switch self {
    case .shortBallApproach: return "Short ball: follow in"
    case .deepCenterLob: return "Deep ball: center lob"
    case .firstServeBody: return "First return: at server"
    case .secondServeRise: return "Second return: early, inside baseline"
    case .wideServeCross: return "Wide serve, then crosscourt"
    case .changeDirectionApproach: return "Change direction, follow in"
    case .recoveryAndSplit: return "Recover to white and split"
    }
  }
}

/// At most seven rows, even after a long rally. Keep gains and losses separate
/// so repeated successes never conceal a missed opportunity for the same rule.
struct CoachPointSummary: Identifiable {
  let rule: CoachRule
  let events: [CoachEvent]
  var id: Int { rule.rawValue }
  var successes: Int { events.filter(\.success).count }
  var misses: Int { events.count - successes }
  var points: Int { successes * 2 - misses }
  var score: String {
    [successes > 0 ? "+\(successes * 2)" : nil, misses > 0 ? "−\(misses)" : nil]
      .compactMap { $0 }.joined(separator: " / ")
  }
  var reason: String {
    let reasons = Set(events.map(\.compactReason))
    return reasons.count == 1 ? events.first!.compactReason : rule.resultAction
  }
  var tally: String? {
    guard events.count > 1 else { return nil }
    return [successes > 0 ? "\(successes) followed" : nil, misses > 0 ? "\(misses) missed" : nil]
      .compactMap { $0 }.joined(separator: " · ")
  }
  static func rows(for events: [CoachEvent]) -> [Self] {
    CoachRule.allCases.compactMap { rule in
      let matching = events.filter { $0.rule == rule }
      return matching.isEmpty ? nil : Self(rule: rule, events: matching)
    }
  }
}

enum ApplePlayerName {
  static func display(_ mask: String?) -> String {
    guard let mask, !mask.contains("•") else { return "You" }
    let local = mask.split(separator: "@", omittingEmptySubsequences: false).first ?? ""
    let prefix = String(local.prefix(5))
    return prefix.isEmpty ? "You" : prefix
  }
}
