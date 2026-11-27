import Foundation

enum CoachRule: Int, Codable, CaseIterable, Identifiable {
  case shortBallApproach = 1, deepCenterLob, firstServeBody, secondServeRise, wideServeCross, changeDirectionApproach, recoveryAndSplit
  var id: Int { rawValue }
  var title: String {
    switch self {
    case .shortBallApproach: return "Follow a short ball in"
    case .deepCenterLob: return "Lob deep balls to center"
    case .firstServeBody: return "First serve: back at server"
    case .secondServeRise: return "Second serve: step in early"
    case .wideServeCross: return "Serve wide, then crosscourt"
    case .changeDirectionApproach: return "Change direction, follow in"
    case .recoveryAndSplit: return "Recover and split all point"
    }
  }
  var instruction: String {
    switch self {
    case .shortBallApproach:
      return "A ball bouncing at least 5 metres inside your baseline is short. Its contact ring turns thick, blinking gold. Reach it, hit, then make a new forward swipe to follow the ball to the net."
    case .deepCenterLob:
      return "For a rally ball behind your baseline, reach yellow and swipe straight down from your player for a center lob."
    case .firstServeBody:
      return "Return a first serve right back at the server: reach yellow and swipe up from your player before contact."
    case .secondServeRise:
      return "Swipe toward yellow early on a second serve. Meet the ball at yellow or step inside the baseline to take it earlier."
    case .wideServeCross:
      return "Place your first serve wide, then hit the opponent’s return crosscourt with a diagonal shot swipe."
    case .changeDirectionApproach:
      return "After deliberately changing the ball’s direction, make a new forward swipe after contact to follow it to the net."
    case .recoveryAndSplit:
      return "On every baseline exchange, reach white, then tap anywhere on court—including white—as your shot comes within 3 m of its bounce on the far court. Keep it up for the whole point for one +2 award. Intentional net attacks are exempt."
    }
  }
}

struct CoachEvent: Codable, Identifiable, Equatable {
  let rule: CoachRule
  let opportunity: Int
  let success: Bool
  var detail: String? = nil
  var id: String { "\(opportunity):\(rule.rawValue)" }
  var points: Int { success ? 2 : -1 }
}

struct CoachPointRecord: Codable, Identifiable {
  let id: UUID
  let sessionID: UUID
  let pointIndex: Int
  let gameIndex: Int
  let winner: Int
  let format: String
  let events: [CoachEvent]
  let gameCompleted: Bool
  let setCompleted: Bool
  var points: Int { events.reduce(0) { $0 + $1.points } }
}

struct CoachReceiving: Codable {
  let opportunity: Int
  let shortBall: Bool
  let deepBall: Bool
  let serveNumber: Int?
  let wideServe: Bool?
}

struct CoachApproach: Codable {
  let rule: CoachRule
  let opportunity: Int
  let from: Vec
  let createdAt: Double
  var commanded = false
}

struct CoachRecovery: Codable {
  var white: Vec
  let from: Vec
  var reachedWhite = false
  var splitAfterRecovery = false
  var receivedReply = false
  var exempt = false
  var missReported = false
}

struct Coachability: Codable {
  private(set) var sessionID = UUID()
  private(set) var events: [CoachEvent] = []
  private(set) var records: [CoachPointRecord] = []
  private(set) var gameScore = 0
  private(set) var setScore = 0
  private(set) var gameIndex = 1
  var receiving: CoachReceiving?
  var approaches: [CoachApproach] = []
  var firstServeWasWide: Bool?
  var recovery: CoachRecovery?
  private(set) var recoveryCycles = 0
  private(set) var consistentRecovery = true
  private var recoveryFailure: String?
  private(set) var misses: [CoachMiss] = []
  private var missSerial = 0
  var lastEventAt = -10.0
  var pointScore: Int { events.reduce(0) { $0 + $1.points } }

  mutating func startPoint() {
    events = []; receiving = nil; approaches = []; firstServeWasWide = nil
    recovery = nil; recoveryCycles = 0; consistentRecovery = true
    recoveryFailure = nil
    lastEventAt = -10
  }

  mutating func record(_ rule: CoachRule, opportunity: Int, success: Bool, time: Double, detail: String? = nil) {
    let event = CoachEvent(rule: rule, opportunity: opportunity, success: success, detail: detail)
    guard !events.contains(where: { $0.id == event.id }) else { return }
    events.append(event)
    lastEventAt = time
    if !success && rule != .recoveryAndSplit {
      reportMiss(rule, correction: rule.missedCorrection, points: -1)
    }
  }

  private mutating func reportMiss(_ rule: CoachRule, correction: String, points: Int?) {
    missSerial += 1
    misses.append(CoachMiss(id: missSerial, rule: rule, correction: correction, points: points))
    if misses.count > 16 { misses.removeFirst(misses.count - 16) }
  }

  mutating func reportRecoveryMiss() {
    guard let recovery, recovery.receivedReply, !recovery.exempt, !recovery.missReported,
      !recovery.reachedWhite || !recovery.splitAfterRecovery else { return }
    self.recovery?.missReported = true
    reportMiss(.recoveryAndSplit,
      correction: recovery.reachedWhite ? "Tap at white as your shot bounces on the far court." : "Reach white, then tap to split.",
      points: nil) // Rule 7 still scores only once, when the point finishes.
  }

  mutating func finishRecoveryCycle() {
    defer { recovery = nil }
    guard let recovery, recovery.receivedReply, !recovery.exempt else { return }
    reportRecoveryMiss()
    recoveryCycles += 1
    if recoveryFailure == nil {
      if !recovery.reachedWhite { recoveryFailure = "You did not reach the white recovery circle on a baseline exchange." }
      else if !recovery.splitAfterRecovery { recoveryFailure = "You reached white but missed the split at the far bounce." }
    }
    consistentRecovery = consistentRecovery && recovery.reachedWhite && recovery.splitAfterRecovery
  }

  mutating func noteRecoverySplit() {
    if recovery?.reachedWhite == true { recovery?.splitAfterRecovery = true }
  }

  mutating func finishApproaches(time: Double) {
    for pending in approaches where time - pending.createdAt >= 0.35 {
      record(pending.rule, opportunity: pending.opportunity, success: false, time: time)
    }
    approaches = []
  }

  mutating func finishReceiving(time: Double) {
    guard let incoming = receiving else { return }
    let rules: [CoachRule] = (incoming.shortBall ? [.shortBallApproach] : [])
      + (incoming.deepBall ? [.deepCenterLob] : [])
      + (incoming.serveNumber == 1 ? [.firstServeBody] : [])
      + (incoming.serveNumber == 2 ? [.secondServeRise] : [])
      + (incoming.wideServe != nil ? [.wideServeCross] : [])
    for rule in rules { record(rule, opportunity: incoming.opportunity, success: false, time: time,
      detail: "You did not return the ball to complete: \(rule.title.lowercased()).") }
    receiving = nil
  }

  mutating func finishPoint(award: PracticeAward, winner: Int, format: PracticeScoring, time: Double) {
    finishReceiving(time: time)
    finishApproaches(time: time)
    finishRecoveryCycle()
    if recoveryCycles > 0 {
      record(.recoveryAndSplit, opportunity: 0, success: consistentRecovery, time: time, detail: recoveryFailure)
    }
    gameScore += pointScore
    setScore += pointScore
    let gameDone = award == .game || award == .set
    records.append(CoachPointRecord(id: UUID(), sessionID: sessionID, pointIndex: (records.last?.pointIndex ?? 0) + 1,
      gameIndex: gameIndex, winner: winner, format: format == .tennis ? "tennis" : "tiebreak",
      events: events, gameCompleted: gameDone, setCompleted: award == .set))
    if gameDone { gameScore = 0; gameIndex += 1 }
  }

  var cupSnapshot: Coachability {
    var copy = self
    // Only the latest winner is needed by point explanations. Cup games do not
    // submit Coachability records, so old points need not cross the network.
    copy.records = Array(records.suffix(1))
    return copy
  }
}

extension PracticeEngine {
  mutating func registerCoachFlight() {
    guard demo == nil else { return }
    guard let f = flight else { return }
    if f.hitter == 0 {
      coach.recovery = f.fault == nil ? CoachRecovery(white: Self.recovery(0, players[1].pos),
        from: players[0].pos, exempt: f.stroke == .volley || f.stroke == .overhead
          || (attacking[0] && players[0].pos.y < Self.net + 5.5)) : nil
      updateCoachRecovery()
      if f.serve && f.serveNumber == 1 {
        coach.firstServeWasWide = f.fault == nil && min(f.landing.x, Self.width - f.landing.x) <= 1.2
      }
      return
    }
    coach.finishApproaches(time: time)
    guard f.fault == nil else { coach.firstServeWasWide = nil; coach.recovery = nil; return }
    if !f.serve { coach.recovery?.receivedReply = true }
    let yellow = intercept(0)
    coach.receiving = CoachReceiving(opportunity: contactSerial,
      shortBall: Self.isShortBall(f, receiving: 0),
      deepBall: !f.serve && yellow.y > Self.length,
      serveNumber: f.serve ? f.serveNumber : nil, wideServe: f.serve ? nil : coach.firstServeWasWide)
    coach.firstServeWasWide = nil
  }

  mutating func assessCoachReturn(incoming f: BallFlight, aim: Vec, kind: ShotKind, clean: Bool, explicit: Bool) {
    guard demo == nil else { return }
    updateCoachRecovery()
    coach.finishRecoveryCycle()
    if let incoming = coach.receiving {
      if incoming.shortBall {
        if clean {
          coach.approaches.append(CoachApproach(rule: .shortBallApproach, opportunity: incoming.opportunity,
            from: players[0].pos, createdAt: time))
        } else { coach.record(.shortBallApproach, opportunity: incoming.opportunity, success: false, time: time,
          detail: "Your short-ball return missed before you could follow it in.") }
      }
      if incoming.deepBall {
        coach.record(.deepCenterLob, opportunity: incoming.opportunity,
          success: clean && kind == .lob && abs(aim.x - Self.width / 2) <= Self.recoveryOffsetLimit, time: time,
          detail: !clean ? "Your deep-ball return missed." : nil)
      }
      if incoming.serveNumber == 1 {
        coach.record(.firstServeBody, opportunity: incoming.opportunity,
          success: clean && abs(aim.x - players[1].pos.x) <= 0.85, time: time,
          detail: !clean ? "Your first-serve return missed." : nil)
      }
      if incoming.serveNumber == 2 {
        let reachedYellow = players[0].pos.distance(to: f.contact) <= Self.contactRadius + 0.000001
        let atBaselineMark = reachedYellow && f.contact.y <= Self.length
        let steppedIn = players[0].pos.y < Self.length && players[0].pos.distance(to: ball) <= Self.contactRadius + 0.000001
        coach.record(.secondServeRise, opportunity: incoming.opportunity,
          success: clean && (atBaselineMark || steppedIn),
          time: time, detail: !clean ? "Your second-serve return missed." : nil)
      }
      if let wide = incoming.wideServe {
        let cross = (players[0].pos.x - Self.width / 2) * (aim.x - Self.width / 2) < 0
        coach.record(.wideServeCross, opportunity: incoming.opportunity,
          success: wide && clean && kind == .cross && cross, time: time,
          detail: !wide ? "Your first serve was not wide." : !clean ? "Your shot after the wide serve missed." : nil)
      }
      coach.receiving = nil
    }
    if explicit && !f.serve {
      if CourtTactics.redirects(from: f.from, at: players[0].pos, to: aim) {
        if clean {
          coach.approaches.append(CoachApproach(rule: .changeDirectionApproach, opportunity: contactSerial,
            from: players[0].pos, createdAt: time))
        } else {
          coach.record(.changeDirectionApproach, opportunity: contactSerial, success: false, time: time,
            detail: "Your change of direction missed before you could follow it in.")
        }
      }
    }
  }

  mutating func updateCoachRecovery() {
    if coach.recovery != nil, let white = recoveryGuide(0) { coach.recovery?.white = white }
    guard let recovery = coach.recovery else { return }
    if players[0].pos.distance(to: recovery.white) <= Self.contactRadius {
      coach.recovery?.reachedWhite = true
    }
    let advanced = recovery.from.y - players[0].pos.y >= 0.5
    let atNet = abs(players[0].pos.y - Self.net) <= 3.3
    if followingApproach[0] && (advanced || atNet) { coach.recovery?.exempt = true }
    // Settle the baseline cycle when the next return is assessed.
  }

  mutating func updateCoachApproaches() {
    var waiting: [CoachApproach] = []
    for pending in coach.approaches {
      let advanced = pending.from.y - players[0].pos.y >= 0.5
      let atNet = abs(players[0].pos.y - Self.net) <= 3.3
      if pending.commanded && (advanced || atNet) {
        coach.record(pending.rule, opportunity: pending.opportunity, success: true, time: time)
      } else { waiting.append(pending) }
    }
    coach.approaches = waiting
  }
}
