import Foundation

/// Keep only recent observations. Career memory uses service-box-relative lanes so that
/// a wide serve from the ad side reinforces a wide serve from the deuce side.
struct RivalReads: Codable {
  var serves: [Int] = []
  var approaches: [Int] = []
  var recentAttacks: [Bool]?

  static func pattern(_ history: [Int]) -> Int? {
    guard history.count >= 3, let last = history.last,
          history.suffix(4).filter({ $0 == last }).count >= 3 else { return nil }
    return last
  }

  static func serveLane(_ x: Double) -> Int {
    let width = abs(x - PracticeEngine.width / 2)
    return width < 1.3 ? 0 : width < 2.8 ? 1 : 2
  }

  mutating func observeServe(_ lane: Int) { serves = Array((serves + [lane]).suffix(5)) }
  mutating func observeApproach(_ lane: Int) {
    approaches = Array((approaches + [lane]).suffix(5))
    if let last = recentAttacks?.indices.last { recentAttacks?[last] = true }
  }
}

struct ScoutedReply: Codable {
  let stretched: Bool
  let short: Bool
  let backhand: Bool
}

extension PracticeEngine {
  mutating func readCareerShot(serve: Bool, from: Vec, aim: Vec) {
    guard let rival = settings.clubEncounter?.rival, !settings.local else { return }
    var reads = rivalReads ?? RivalReads()
    let pattern = RivalReads.pattern(serve ? reads.serves : reads.approaches)
    // A habitual net rusher can draw an early lean even from the baseline.
    let isAttack = from.y < Self.length - Self.shortBallDepth || (reads.recentAttacks ?? []).filter { $0 }.count >= 3
    if let pattern, serve || isAttack {
      let expectedX: Double
      let actual: Int
      if serve {
        let sign = scoring.serveFromRight ? -1.0 : 1.0
        expectedX = Self.width / 2 + sign * [0.65, 2.05, 3.60][pattern]
        actual = RivalReads.serveLane(aim.x)
      } else {
        expectedX = pattern == 0 ? 1.2 : 7.03
        actual = aim.x < Self.width / 2 ? 0 : 1
      }
      let strength = rival == .morgan ? 0.85 : rival == .casey ? 1.05 : 0.95
      players[1].destination.x = clamp(players[1].pos.x + clamp(expectedX - players[1].pos.x, -1, 1)*strength, 0, Self.width)
      reactAt = max(time, reactAt + (actual == pattern ? -0.12 : 0.19)*strength)
    }
    if serve { reads.observeServe(RivalReads.serveLane(aim.x)) }
    else { reads.recentAttacks = Array(((reads.recentAttacks ?? []) + [false]).suffix(4)) }
    rivalReads = reads
  }

  var scoutingNote: String? {
    let recent = (scoutedReplies ?? []).suffix(8)
    guard !recent.isEmpty else {
      let points = coach.records.suffix(6)
      guard !points.isEmpty else { return nil }
      return "You won \(points.filter { $0.winner == 0 }.count) of the last \(points.count) points."
    }
    let stressed = recent.filter { $0.stretched && $0.backhand }
    if stressed.count >= 2 {
      return "\(stressed.filter(\.short).count) of \(stressed.count) stretched backhands from \(name(1)) landed short."
    }
    let short = recent.filter(\.short).count
    return "\(name(1)) left \(short) of the last \(recent.count) returns at least 5 m inside your baseline."
  }

  var changeoverNote: String? {
    let points = scoring.points.reduce(0,+)
    guard scoring.lastAward != .point || (scoring.format == .tiebreak && points > 0 && points.isMultiple(of: 6)) else { return nil }
    return scoutingNote
  }
}

struct ContactReading {
  let height: Float
  let zone: String
  let cue: String
  init(frame: RallyFrame, hitter: Int, flight: BallFlight) {
    let body = hitter == 0 ? frame.near : frame.far
    height = (flight.strikeOrigin ?? frame.ball).y
    let hips = (body[.leftHip].y + body[.rightHip].y)/2
    let shoulders = (body[.leftShoulder].y + body[.rightShoulder].y)/2
    if height < hips - 0.09 {
      zone = "Below hip"; cue = "Bend through the knees and give the ball net clearance."
    } else if height > shoulders + 0.05 {
      zone = "Above shoulder"; cue = "Take the next rising ball earlier or create room to let it drop."
    } else {
      zone = "Hip to shoulder"; cue = "This height gives you room to drive through the ball."
    }
  }
  var label: String { String(format: "%@ · %.2f m", zone, height) }
}

struct DecisionSnapshot {
  let game: PracticeEngine
  let frame: RallyFrame
  let receiver: Int
  var feet: Vec { game.players[receiver].pos }
  var opponent: Vec { game.flight?.from ?? game.players[1-receiver].pos }
  var recovery: Vec {
    if BallContactWindow.inServiceBox(feet, side: receiver) || game.attacking[receiver] {
      return CourtTactics.netCoverage(side: receiver, opponentContact: opponent)
    }
    return PracticeEngine.recovery(receiver, opponent)
  }
}

enum TrainingLane: String, CaseIterable {
  case left = "Left", middle = "Middle", right = "Right"
  var x: Double {
    switch self { case .left: return 1.15; case .middle: return PracticeEngine.width/2; case .right: return 7.08 }
  }
}

enum TrainingExercise: String, Identifiable {
  case retry = "Retry this ball", servePlusOne = "Serve + 1", net = "Net positioning"
  var id: Self { self }
}

enum TrainingFeed {
  static func serve(_ placement: ServePlacement, surface: CourtSurface) -> PracticeEngine {
    var game = PracticeEngine(settings: .init(surface: surface, allCourtTraining: false))
    game.scoring = PracticeScore(format: .tennis, firstServer: 0)
    game.start()
    game.chooseServe(placement, side: 0)
    return game
  }

  static func net(surface: CourtSurface, lob: Bool, right: Bool) -> PracticeEngine {
    var game = PracticeEngine(settings: .init(surface: surface, allCourtTraining: false))
    game.phase = .live
    game.players[0].pos = Vec(x: 4.1, y: PracticeEngine.net + 3.5)
    game.players[1].pos = Vec(x: right ? 1.1 : 7.1, y: 1)
    for side in 0...1 { game.players[side].destination = game.players[side].pos }
    game.attacking[0] = true
    game.launch(1, aim: Vec(x: right ? 6.7 : 1.5, y: lob ? 23.15 : 21.7), kind: lob ? .lob : .line)
    return game
  }

  static func split(_ position: Vec, into game: inout PracticeEngine) {
    let feet = Vec(x: clamp(position.x, 0.2, PracticeEngine.width-0.2),
                   y: clamp(position.y, PracticeEngine.net+1, PracticeEngine.length-5.48))
    game.players[0].pos = feet
    game.players[0].destination = feet
    game.players[0].velocity = .zero
    game.players[0].settled = 0.2
    game.splitStarted[0] = game.time
    game.splitTimed[0] = true
    game.players[0].splitForReturn = game.contactSerial
  }
}

/// Device-local practice statistics are independent of scored matches and career progress.
struct TacticalPracticeRecord: Codable, Equatable {
  private(set) var attempts = 0
  private(set) var successes = 0
  private(set) var streak = 0
  private(set) var bestStreak = 0

  mutating func finish(success: Bool) {
    attempts += 1
    if success { successes += 1; streak += 1 } else { streak = 0 }
    bestStreak = max(bestStreak, streak)
  }
}
