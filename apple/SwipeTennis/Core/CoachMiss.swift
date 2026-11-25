import Foundation

struct CoachMiss: Identifiable, Equatable {
  let id: Int
  let rule: CoachRule
  let correction: String
  let points: Int?
  var label: String { points == nil ? "RULE 7 · RECOVERY MISSED" : "−1 CP · RULE \(rule.rawValue) MISSED" }
}

extension CoachRule {
  var missedCorrection: String {
    switch self {
    case .shortBallApproach: return "Short ball: hit, then swipe in."
    case .deepCenterLob: return "Deep ball: swipe down to lob."
    case .firstServeBody: return "First serve: swipe up at server."
    case .secondServeRise: return "Second serve: tap yellow early."
    case .wideServeCross: return "Serve wide, then swipe crosscourt."
    case .changeDirectionApproach: return "New direction: hit, then swipe in."
    case .recoveryAndSplit: return "Reach white, then tap to split."
    }
  }
}

/// Presentation time keeps running between points, and freezes when the scene is paused.
/// Queue simultaneous misses so none disappear behind the last event of the frame.
struct CoachMissPresentation {
  static let duration = 2.4
  static let ringDuration = 0.85
  private(set) var current: CoachMiss?
  private(set) var elapsed = 0.0
  private var pending: [CoachMiss] = []
  private var sessionID: UUID?
  private var lastSerial = 0
  private var ringElapsed: Double?

  var ringProgress: Double? {
    guard let ringElapsed, ringElapsed < Self.ringDuration else { return nil }
    return ringElapsed / Self.ringDuration
  }

  mutating func update(coach: Coachability, delta: Double) {
    if sessionID != coach.sessionID {
      self = CoachMissPresentation()
      sessionID = coach.sessionID
    }
    let incoming = coach.misses.filter { $0.id > lastSerial }
    pending += incoming
    // The feet react immediately, even while earlier captions are still being read.
    if !incoming.isEmpty { ringElapsed = 0 }
    else if let ringElapsed { self.ringElapsed = ringElapsed + max(0, delta) }
    lastSerial = coach.misses.last?.id ?? lastSerial
    if current != nil {
      elapsed += max(0, delta)
      if elapsed >= Self.duration { current = nil }
    }
    if current == nil, !pending.isEmpty {
      current = pending.removeFirst()
      elapsed = 0
    }
  }
}
