import Foundation

struct Vec: Codable, Equatable {
  var x: Double
  var y: Double
  static let zero = Vec(x: 0, y: 0)
  func distance(to p: Vec) -> Double { hypot(x - p.x, y - p.y) }
  var length: Double { hypot(x, y) }
}
func clamp(_ v: Double, _ low: Double, _ high: Double) -> Double { max(low, min(high, v)) }
enum Difficulty: String, Codable, CaseIterable {
  case easy = "Easy"
  case medium = "Medium"
  case tough = "Tough"
  var accuracy: Double { self == .easy ? 1 : self == .medium ? 0.9 : 0.8 }
  var reaction: Double { self == .easy ? 0.52 : self == .medium ? 0.32 : 0.19 }
  var speed: Double { self == .easy ? 0.9 : self == .medium ? 1 : 1.07 }
}
enum BotStyle: String, Codable, CaseIterable {
  case baseline = "Baseline"
  case aggressive = "Aggressive baseliner"
  case volley = "Serve & volley"
  case allcourt = "All-court player"
  case retriever = "Retriever"
  var detail: String {
    switch self {
    case .baseline: return "Steady depth. Crosscourt patterns. Patient construction."
    case .aggressive: return "Takes time away and attacks the open corners."
    case .volley: return "Closes the net. Pass with precision or lift a lob."
    case .allcourt: return "Builds from deep and approaches a short ball."
    case .retriever: return "Runs down width. Uses height. Waits for an opening."
    }
  }
  var symbol: String {
    switch self {
    case .baseline: return "arrow.left.arrow.right"
    case .aggressive: return "bolt.fill"
    case .volley: return "arrow.up.forward"
    case .allcourt: return "arrow.up.left.and.arrow.down.right"
    case .retriever: return "figure.run"
    }
  }
  var speed: Double {
    switch self {
    case .baseline: return 5.3
    case .aggressive: return 5.6
    case .volley: return 5.5
    case .allcourt: return 5.7
    case .retriever: return 6.1
    }
  }
  var pace: Double {
    switch self {
    case .baseline: return 1
    case .aggressive: return 1.22
    case .volley: return 1.1
    case .allcourt: return 1.08
    case .retriever: return 0.82
    }
  }
  var risk: Double {
    switch self {
    case .baseline: return 0.12
    case .aggressive: return 0.58
    case .volley: return 0.36
    case .allcourt: return 0.3
    case .retriever: return 0.06
    }
  }
  var depth: Double {
    switch self {
    case .baseline: return 1.5
    case .aggressive: return 0.7
    case .volley: return 3
    case .allcourt: return 1.8
    case .retriever: return 1.6
    }
  }
}
enum ShotKind: String, Codable, CaseIterable {
  case cross = "Crosscourt"
  case line = "Down the line"
  case angle = "Short angle"
  case lob = "Lob"
  case drop = "Drop shot"
  case slice = "Crosscourt slice"
  var symbol: String {
    switch self {
    case .cross: return "arrow.up.left"
    case .line: return "arrow.up"
    case .angle: return "arrow.turn.up.left"
    case .lob: return "arrow.up.forward.circle"
    case .drop: return "arrow.clockwise"
    case .slice: return "arrow.down.right"
    }
  }
}
enum CourtSurface: String, Codable, CaseIterable {
  case grass = "Grass"
  case clay = "Clay"
  case hard = "Hard"
  var pace: Double { self == .grass ? 1.08 : self == .clay ? 0.87 : 1 }
  var bounce: Double { self == .grass ? 0.7 : self == .clay ? 1.3 : 1 }
}
struct PracticeSettings: Codable {
  var local = false
  var tournament = false
  var botST: Double?
  var clubEncounter: ClubEncounter?
  var pressureDay: Int?
  var botSpeed: Double { botST.map { 0.85 + clamp($0,1,10)*0.026 } ?? difficulty.speed }
  static let opponentMovementMultiplier = 1.2
  func opponentRunSpeed(chasingDrop: Bool = false) -> Double {
    Self.opponentMovementMultiplier * botSpeed * (chasingDrop ? 7 : style.speed)
  }
  var botReaction: Double { botST.map { 0.60 - clamp($0,1,10)*0.044 } ?? difficulty.reaction }
  var difficulty: Difficulty = .easy
  var style: BotStyle = .baseline
  var venue: TennisVenue?
  var surface: CourtSurface = .grass
  var allCourtTraining = true
  var scoring: PracticeScoring = .tennis
  var playerName = ""
  var opponentName = ""

  enum CodingKeys: String, CodingKey {
    case local, tournament, botST, pressureDay, clubEncounter, venue, difficulty, style, surface, allCourtTraining, scoring, playerName, opponentName
  }
  init(
    local: Bool = false, difficulty: Difficulty = .easy, style: BotStyle = .baseline,
    surface: CourtSurface = .grass, allCourtTraining: Bool = true,
    scoring: PracticeScoring = .tennis, playerName: String = "", opponentName: String = ""
  ) {
    self.local = local
    self.difficulty = difficulty
    self.style = style
    self.surface = surface
    self.allCourtTraining = allCourtTraining
    self.scoring = scoring
    self.playerName = playerName
    self.opponentName = opponentName
  }
  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    local = try values.decodeIfPresent(Bool.self, forKey: .local) ?? false
    botST = try values.decodeIfPresent(Double.self, forKey: .botST)
    clubEncounter = try values.decodeIfPresent(ClubEncounter.self, forKey: .clubEncounter)
    pressureDay = try values.decodeIfPresent(Int.self, forKey: .pressureDay)
    tournament = try values.decodeIfPresent(Bool.self, forKey: .tournament) ?? false
    difficulty = try values.decodeIfPresent(Difficulty.self, forKey: .difficulty) ?? .easy
    style = try values.decodeIfPresent(BotStyle.self, forKey: .style) ?? .baseline
    venue = try values.decodeIfPresent(TennisVenue.self, forKey: .venue)
    surface = try values.decodeIfPresent(CourtSurface.self, forKey: .surface) ?? .grass
    allCourtTraining = try values.decodeIfPresent(Bool.self, forKey: .allCourtTraining) ?? true
    scoring = try values.decodeIfPresent(PracticeScoring.self, forKey: .scoring) ?? .tennis
    playerName = try values.decodeIfPresent(String.self, forKey: .playerName) ?? ""
    opponentName = try values.decodeIfPresent(String.self, forKey: .opponentName) ?? ""
  }
  func name(_ side: Int) -> String {
    let entered = (side == 0 ? playerName : opponentName)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return entered.isEmpty ? (side == 0 ? "You" : "Opponent") : entered
  }
}
struct CourtPlayer: Codable {
  var pos: Vec
  var destination: Vec
  var velocity = Vec.zero
  var settled = 0.0
  var aim: Vec?
  var kind: ShotKind = .cross
  var madeNetVolley: Bool?
  var splitForReturn: Int?
  var lastReturn: ReturnDecision?
  var netEffort: NetEffort?
  var energy: Double?
  var runPace: Double?
  var tappedLanding: Vec?
  var swingStrength: Double?
  var swipeDepth: Double?
  var recoveryFlight: Int?
  var diveDecision: Int?
}
/// The court position an incoming shot is expected to reach at a given flight progress.
struct CourtIntercept: Codable {
  let point: Vec
  let progress: Double
}

struct BallFlight: Codable {
  var from: Vec, landing: Vec, contact: Vec
  var strikeOrigin: CourtPoint3D?
  var reboundDepth: Double?
  var extendedReboundDuration: Double?
  var elapsed = 0.0
  var duration: Double
  var hitter: Int
  var fault: String?
  var explanation: String
  var loft: Double
  var power: CourtPower?
  var powerBackhand: Bool?
  var acknowledge = false
  var serve = false
  var serveNumber = 1
  var serveAim: Vec?
  var serveSwipeStrength: Double?
  var serveReleaseTime: Double?
  // Flight-local times keep completed strokes tied to this incoming ball.
  static let swingLead = 0.35
  var expectedContactTime: Double?
  var swipeFinishedAt: Double?
  var missedSwingWindow: Bool?
  var isFirstServeFault: Bool { serve && serveNumber == 1 && fault != nil }
  func hasTimelySwing(at contactTime: Double) -> Bool {
    guard missedSwingWindow != true, let swipeFinishedAt else { return false }
    let lead = contactTime - swipeFinishedAt
    return lead > 0 && lead <= Self.swingLead
  }
  var bounceDestinations: [Vec]?
  var swingStrength: Double?
  var serveProfile: ServeProfile?
  var contactQuality: RallyContact?
  var jumpLob: Bool?
  var opponentIntercept: CourtIntercept?
  var receiverWrongFooted: Bool?
  var kind: ShotKind = .cross
  var stroke: TennisStrokeStyle = .groundstroke
  var trainingApproach = false
  var trainingReply = false
  var returnedShortBall: Bool?
  var opponentReplyPrepared = false
  var opponentError: OpponentError?
  var missedChaseTarget: Vec?
  var dropReachable: Bool?
  var approachReply: ApproachReply?
  var progress: Double {
    if elapsed <= 0.8*duration { return elapsed/duration }
    return min(1,0.8+0.2*(elapsed-0.8*duration)/reboundDuration)
  }
  var position: Vec { courtPosition(at: progress) }
  var height: Double { altitude(at: progress) }
}
struct Coaching: Codable, Identifiable {
  var id = UUID()
  var title: String
  var reason: String
  var tip: String
}
enum PracticePhase: String, Codable { case ready, serving, serveFault, live, point, finished }
struct PracticeEngine: Codable {
  // The saved match contains simulation state. Guided lessons have a separate progress store.
  private enum CodingKeys: String, CodingKey {
    case settings, players, scoring, phase, flight, pointResolution, servePreparation, serveLanding
    case serveExplanation, landingSerial, ball, rally, bestRally, time, reactAt, approach, balanced, attempts, feedback
    case history, contactSerial, bounceSerial, attacking, followingApproach, approachAvailable
    case splitStarted, splitTimed, tactics, opponentErrors, coach, dropGestureEpoch, dropReturns
    case scoutedReplies, rivalReads
    case inventory, powerEarnedThisPoint, queuedPower, assist, momentum
  }

  static let width = 8.23, length = 23.77, net = 11.885
  static let contactRadius = 0.85
  static let recoveryOffsetLimit = 3 * 0.3048  // Three feet in the court's meter coordinates.
  var settings: PracticeSettings
  var players: [CourtPlayer] = [24.6, -0.8].map {
    CourtPlayer(pos: Vec(x: 4.115, y: $0), destination: Vec(x: 4.115, y: $0))
  }
  var scoring: PracticeScore
  var scoutedReplies: [ScoutedReply]?
  var rivalReads: RivalReads?
  var phase: PracticePhase = .ready
  var flight: BallFlight?
  var pointResolution: PointResolution?
  var servePreparation: ServePreparation?
  var serveExplanation: String?
  var serveLanding: ServeLanding?
  var landingSerial = 0
  var ball = Vec(x: 4.115, y: -0.8)
  var rally = 0, bestRally = 0
  var time = 0.0, reactAt = 0.0
  var approach = false
  var balanced = [0, 0], attempts = [0, 0]
  var feedback = Coaching(
    title: "Read. Move. Settle.",
    reason: "Move to the contact ring early, then brake before the ball arrives.",
    tip: "Swipe toward yellow to receive and white to recover. Tap in position to split, volley, or smash.")
  var history: [Coaching] = []
  var contactSerial = 0
  var bounceSerial = 0
  var attacking = [false, false]
  var followingApproach = [false, false]
  var approachAvailable = [false, false]
  var splitStarted = [-10.0, -10.0]
  var splitTimed = [false, false]
  var tactics = [TacticalStats(), TacticalStats()]
  var opponentErrors = OpponentErrors()
  var coach = Coachability()
  var dropGestureEpoch: [Int?] = [nil, nil]
  var dropReturns = DropShotReturns()
  var inventory = PowerInventory()
  var powerEarnedThisPoint: CourtPower?
  var queuedPower: CourtPower?
  var assist: AssistedContact?
  var momentum = PointMomentum()
  var demo: ShotDemoRun?

  init(settings: PracticeSettings) {
    self.settings = settings
    scoring = settings.clubEncounter?.openingScore ?? PracticeScore(format: settings.scoring)
    if let day = settings.pressureDay, settings.scoring == .tiebreak {
      for _ in 0..<5 { scoring.award(0); scoring.award(1) }
      switch day % 3 {
      case 0: scoring.award(1)
      case 1: scoring.award(0)
      default: scoring.award(0); scoring.award(1)
      }
    }
  }
  func name(_ side: Int) -> String { settings.name(side) }
  func quickNetFeet(_ side: Int) -> Bool {
    phase == .live && (side == 0 || settings.local) && players[side].madeNetVolley == true
      && abs(players[side].pos.y - Self.net) <= Self.net - ServeGeometry.serviceLine
      && flight?.fault == nil
  }
  static func own(_ side: Int, _ p: Vec) -> Vec {
    Vec(
      x: clamp(p.x, -1.6, 9.83), y: side == 0 ? clamp(p.y, 12.585, CourtRunoff.depth.upperBound - 1) : clamp(p.y, CourtRunoff.depth.lowerBound + 1, 11.185)
    )
  }
  static func aim(_ side: Int, _ p: Vec) -> Vec {
    Vec(
      x: clamp(p.x, 0.15, 8.08), y: side == 0 ? clamp(p.y, 0.15, 11.385) : clamp(p.y, 12.385, 23.62)
    )
  }
  static func red(_ p: Vec) -> Bool {
    min(p.x, 8.23 - p.x) < 0.85 || min(p.y, 23.77 - p.y) < 0.8
      || (abs(p.y - 11.885) < 5 && min(p.x, 8.23 - p.x) < 2)
  }
  // Saved rallies keep their original rebound, even when the footwork guide changes.
  mutating func restoreReceiveMark() {
    guard phase == .live, var shot = flight, shot.power == nil, shot.reboundDepth == nil else { return }
    let receiver = 1 - shot.hitter
    let previous = shot.contact
    if shot.serve {
      shot.contact = ServeGeometry.returnMark(through: shot.landing, from: shot.launchPosition, server: shot.hitter, number: shot.serveNumber)
    } else {
      shot.reboundDepth = abs(previous.y - shot.landing.y)
      shot.contact = Self.receiveMark(landing: shot.landing, receiver: receiver)
    }
    if players[receiver].destination == previous {
      players[receiver].destination = Self.own(receiver, shot.contact)
    }
    flight = shot
  }

  static let bounceSpacing = 2.0
  static let recoveryDistance = length + 4 * 0.3048
  static let maxRecoveryBehindBaseline = 4.0

  static func receiveMark(landing: Vec, receiver: Int) -> Vec {
    Vec(x: landing.x, y: landing.y + (receiver == 0 ? bounceSpacing : -bounceSpacing))
  }

  static func recovery(_ side: Int, _ opponent: Vec) -> Vec {
    let center = width / 2
    let x = center + clamp(center - opponent.x, -recoveryOffsetLimit, recoveryOffsetLimit)
    let dx = opponent.x - x
    let depth = sqrt(max(0, recoveryDistance * recoveryDistance - dx * dx))
    let y = side == 0 ? min(opponent.y + depth, length + maxRecoveryBehindBaseline)
                      : max(opponent.y - depth, -maxRecoveryBehindBaseline)
    return own(side, Vec(x: x, y: y))
  }
  static func preset(_ side: Int, _ kind: ShotKind, _ p: Vec) -> Vec {
    var x = p.x < 4.115 ? 6.83 : 1.4
    if kind == .line { x = clamp(p.x, 0.5, 7.73) }
    if kind == .angle { x = x < 4 ? 0.55 : 7.68 }
    let depth = kind == .drop ? net - 1.6 : kind == .angle ? 8.4 : kind == .lob ? 2.2 : 1.8
    return Vec(x: x, y: side == 0 ? depth : 23.77 - depth)
  }
  static func contactChance(
    _ difficulty: Difficulty, settled: Double, gap: Double, speed: Double, risky: Bool
  ) -> Double {
    if gap > 1.35 { return 0 }
    if gap <= 0.85 && settled >= 0.18 && speed < 2.2 { return difficulty.accuracy }
    return clamp(
      difficulty.accuracy - 0.22 - max(0, gap - 0.6) * 0.3 - (speed > 3 ? 0.13 : 0)
        - (risky ? 0.14 : 0), 0.12, 0.78)
  }
  mutating func choose(_ side: Int, _ kind: ShotKind) {
    guard side != 0 || queuedPower == nil else { return }
    guard phase != .serving || servePreparation?.server != side else { return }
    players[side].tappedLanding = nil
    players[side].swipeDepth = nil
    if phase == .live, let incoming = flight, incoming.hitter == 1 - side {
      flight?.swipeFinishedAt = incoming.elapsed
    }
    players[side].swingStrength = 0.5
    players[side].kind = kind
    players[side].aim = Self.preset(side, kind, players[side].pos)
    if side == 0, demo != nil, canChooseShot(side) {
      let epoch = shotGestureEpoch(side)
      demo?.chosenShot = kind
      demo?.chosenEpoch = epoch
    }
  }
  func committedRun(_ side: Int) -> Vec? {
    guard phase == .live, let routes = flight?.bounceDestinations, routes.indices.contains(side) else { return nil }
    return routes[side]
  }

  private mutating func lockRunsAtBounce() {
    guard flight?.bounceDestinations == nil, flight?.fault == nil, flight?.power == nil else { return }
    let routes = players.map { player -> Vec in
      let dx = player.destination.x - player.pos.x, dy = player.destination.y - player.pos.y
      let distance = hypot(dx, dy), speed = player.velocity.length
      if let effort = player.netEffort, effort.serial == contactSerial { return effort.landing }
      guard distance > 0.02, speed > 0.05,
        player.velocity.x * dx + player.velocity.y * dy >= 0.7 * speed * distance else { return player.pos }
      return player.destination
    }
    flight?.bounceDestinations = routes
    for side in players.indices {
      players[side].destination = routes[side]
      if routes[side] == players[side].pos { players[side].velocity = .zero }
    }
  }

  mutating func recover(_ side: Int) {
    guard committedRun(side) == nil else { return }
    guard side != 0 || queuedPower == nil else { return }
    attacking[side] = false
    followingApproach[side] = false
    approachAvailable[side] = false
    players[side].recoveryFlight = contactSerial
    players[side].destination = Self.recovery(side, players[1-side].pos)
  }
  mutating func move(_ side: Int, to point: Vec) {
    guard committedRun(side) == nil else { return }
    guard side != 0 || queuedPower == nil else { return }
    guard phase != .serving || servePreparation?.server != side else { return }
    followingApproach[side] = false
    players[side].recoveryFlight = nil
    players[side].destination = Self.own(side, point)
  }
  // Free steering can still chase an incoming ball or recover laterally after the bounce.
  mutating func steer(_ side: Int, to target: Vec) {
    guard phase.isPlaying, flight?.fault == nil else { return }
    var destination = target
    if !canFollowShot(side) {
      let here = players[side].pos.y
      let meet = contactGuide(side)?.y ?? here
      destination.y = side == 0 ? max(target.y, min(here, meet)) : min(target.y, max(here, meet))
    }
    move(side, to: destination)
  }
  mutating func start(random: () -> Double = { Double.random(in: 0..<1) }) {
    guard phase == .ready || phase == .point else { return }
    for i in 0...1 {
      let p = Vec(x: 4.115, y: i == 0 ? 24.6 : -0.8)
      players[i].pos = p
      players[i].destination = p
      players[i].velocity = .zero
      players[i].madeNetVolley = nil
      players[i].splitForReturn = nil
      players[i].lastReturn = nil
      players[i].netEffort = nil
      players[i].runPace = nil
      players[i].swingStrength = nil
      players[i].swipeDepth = nil
      players[i].tappedLanding = nil
      players[i].settled = 0
      players[i].aim = nil
      if players[i].kind == .drop || players[i].kind == .slice { players[i].kind = .cross }
    }
    phase = .serving
    serveExplanation = nil
    coach.startPoint()
    powerEarnedThisPoint = nil
    flight = nil
    pointResolution = nil
    serveLanding = nil
    rally = 0
    approach = false
    attacking = [false, false]
    followingApproach = [false, false]
    approachAvailable = [false, false]
    splitStarted = [-10, -10]
    splitTimed = [false, false]
    dropGestureEpoch = [nil, nil]
    let server = scoring.server
    let fromRight = scoring.serveFromRight
    // Each server keeps serving for the game, alternating deuce/ad service courts.
    let serverX = server == 0 ? (fromRight ? 4.8 : 3.43) : (fromRight ? 3.43 : 4.8)
    players[server].pos.x = serverX
    players[server].destination = players[server].pos
    let receiver = 1 - server
    let receiverX = serverX < Self.width / 2 ? 6.1 : Self.width - 6.1
    players[receiver].pos.x = receiverX
    players[receiver].destination = players[receiver].pos
    let initial = ServeGeometry.target(.body, from: players[server].pos,
      receiver: players[receiver].pos, server: server, fromRight: fromRight)
    let bot = server == 1 && !settings.local
    let choice = bot ? ServePlacement.allCases[Int(clamp(random(), 0, 0.999999) * 3)] : .body
    let target = ServeGeometry.target(choice, from: players[server].pos,
      receiver: players[receiver].pos, server: server, fromRight: fromRight)
    servePreparation = ServePreparation(server: server, target: initial, destination: target,
      placement: choice)
    ball = players[server].pos
    feedback = Coaching(title: "Set up the serve.",
      reason: "Blue is the serve's bounce target. Yellow is the receiver's contact position.",
      tip: bot ? "Read the blue target and move to yellow before the toss."
        : "Set blue, wait for the toss, then swipe toward blue.")
  }

  mutating func launch(
    _ side: Int, aim: Vec, kind: ShotKind, fault: String? = nil, explanation: String = "",
    serve: Bool = false, serveNumber: Int = 1, serveProfile: ServeProfile? = nil, stroke: TennisStrokeStyle = .groundstroke,
    trainingApproach: Bool = false, trainingReply: Bool = false
  ) {
    let from = players[side].pos
    // The next flight leaves the exact 3D point reached by the incoming ball on this tick.
    let impact = serve ? serviceImpact(at: from, side: side, explosive: queuedPower == .ace)
      : flight.flatMap { $0.hitter != side ? $0.worldBall(at: $0.progress) : nil } ?? from.world(height: 0.93)
    let origin = impact.courtPosition
    var landing = aim
    if fault == "wide" { landing.x = aim.x < 4.115 ? -0.5 : 8.73 }
    if fault == "long" {
      landing.y = serve ? (side == 0 ? ServeGeometry.serviceLine - 0.45 : Self.length - ServeGeometry.serviceLine + 0.45)
        : (side == 0 ? -0.6 : 24.37)
    }
    if fault == "net" {
      // Hit the mesh along the intended shot's line, not the far landing target's x position.
      let depth = aim.y - origin.y
      let fraction = abs(depth) > 0.000001 ? clamp((Self.net - origin.y) / depth, 0, 1) : 0
      landing = Vec(x: origin.x + (aim.x - origin.x) * fraction, y: Self.net)
    }
    // Yellow is a footwork target. The rendered ball continues along its
    // incoming bearing and can meet the racket beside that stance.
    let contact = serve ? ServeGeometry.returnMark(through: landing, from: origin, server: side, number: serveNumber)
      : Self.receiveMark(landing: landing, receiver: 1-side)
    let bot = side == 1 && !settings.local
    let pace = (bot ? settings.style.pace * settings.botSpeed : 1) * settings.surface.pace
    var loft =
      serve ? 0.4 : stroke == .overhead
      ? 0.45
      : kind == .lob
        ? 2.5
        : stroke == .volley
          ? 0.65
          : kind == .lob ? 2.5 : bot && settings.style == .retriever ? 1.7 : 1
    var duration = clamp(
      from.distance(to: landing) / (15 * pace) + 0.35 + (loft - 1) * 0.45, 0.85, 2.65)
    if !serve && kind == .drop {
      let netFraction = clamp(abs((Self.net - from.y) / (landing.y - from.y)), 0.05, 0.95)
      loft = max(0.95, 1.08 / (sin(netFraction * .pi) * 1.7))
      duration = clamp(from.distance(to: landing) / 10 + 0.55, 1.1, 2.8)
    } else if !serve && kind == .slice {
      loft = 0.8
      duration *= 1.35
    }
    let profile = serve ? (serveProfile ?? .standard(serveNumber)) : nil
    if let profile {
      if fault != "net" {
        let netProgress = (Self.net - origin.y) / (landing.y - origin.y)
        if netProgress > 0 && netProgress < 1 {
          let clearance = 1.04 - Double(impact.y) * (1 - netProgress)
          loft = max(loft, clearance / (1.7 * sin(.pi * netProgress)))
        }
      }
      loft += 0.18 * Double(profile.spin.rawValue)
    }
    if (stroke == .volley && kind != .lob && kind != .drop && kind != .slice) || stroke == .overhead {
      duration = clamp(
        from.distance(to: landing) / (stroke == .overhead ? 23 : 18) + 0.2, 0.65, 1.9)
    }
    let wrongFooted = !serve && fault == nil && demo == nil && (side == 0 || settings.local)
      && CourtTactics.hitsBehind(players[1 - side], target: contact)
    if trainingApproach {
      // Give the practice partner enough flight time to reach the approach with ordinary footwork.
      let speed = settings.opponentRunSpeed() * (wrongFooted ? 0.6 : 1)
      let travel = CourtTactics.travelTime(
        distance: players[1].pos.distance(to: contact), speed: speed)
      duration = max(duration, (travel + 0.15) / 0.86)
    }
    let receiver = 1 - side
    let closeRun = (receiver == 0 || settings.local) && flight?.hitter == receiver
      && (followingApproach[receiver] || ((flight?.progress ?? 1) < 0.8 && advancingToNet(receiver)))
    let returnedShort = !serve && fault == nil && stroke != .volley && stroke != .overhead
      && flight.map { Self.isShortBall($0, receiving: side) } == true
    pointResolution = nil
    flight = BallFlight(
      from: from, landing: landing, contact: contact, strikeOrigin: impact, reboundDepth: serve ? nil : 1.83, duration: duration, hitter: side,
      fault: fault, explanation: explanation, loft: loft, serve: serve, serveNumber: serveNumber,
      serveProfile: profile, receiverWrongFooted: wrongFooted, kind: kind,
      stroke: serve ? .serve : stroke == .groundstroke ? kind.strokeStyle : stroke, trainingApproach: trainingApproach,
      trainingReply: trainingReply, returnedShortBall: returnedShort)
    if let profile { flight?.setLaunchSpeed(kph: profile.launchSpeedKPH) }
    ball = origin
    players[1 - side].settled = 0
    reactAt = time + (trainingApproach ? 0.08 : settings.botReaction)
    if side == 0 && fault == nil { readCareerShot(serve: serve, from: from, aim: landing) }
    rally += 1
    bestRally = max(bestRally, rally)
    contactSerial += 1
    dropGestureEpoch = [nil, nil]
    if bot {
      approach = settings.style == .volley || (settings.style == .allcourt && from.y > 3)
      let white = Self.recovery(1, players[0].pos)
      // A baseline bot holds its court after sending the opponent forward.
      // Otherwise it backpedals away from the overhead on the next reply.
      let hold = Vec(x: white.x, y: settings.style == .retriever ? -1.7 : max(0,white.y))
      players[1].destination = approach ? Vec(x: clamp(aim.x, 2, 6.23), y: 8) : hold
    }
    let chasesOut = botChasesOut
    if (closeRun || followingApproach[receiver]) && !chasesOut {
      // An opponent volley can close the approach window before there is a bounce.
      players[receiver].destination = players[receiver].pos
      players[receiver].velocity = .zero
    }
    if fault != nil {
      for index in 0...1 where !(chasesOut && index == receiver) {
        players[index].destination = players[index].pos
        players[index].velocity = .zero
        followingApproach[index] = false
      }
    } else if !serve && !bot && advancingToNet(side) {
      // The run to the incoming ball ends at contact. A fresh swipe starts the approach.
      players[side].destination = players[side].pos
      players[side].velocity = .zero
    }
    followingApproach[receiver] = false
    approachAvailable[receiver] = false
    if serve {
      let landing = Vec(x: from.x, y: side == 0 ? Self.length - 0.65 : 0.65)
      serveLanding = ServeLanding(server: side, from: from, to: landing)
      // Landing inside the baseline belongs to the serve. A net approach still needs a swipe.
      if !bot { players[side].destination = landing }
    }
    registerCoachFlight()
  }
  func intercept(_ side: Int) -> Vec {
    if let target = serveReceiveTarget(side) { return target }
    guard let f = flight else { return players[side].pos }
    if let effort = players[side].netEffort, effort.serial == contactSerial { return effort.landing }
    if side == 1, !settings.local, f.hitter == 0, let read = f.opponentIntercept {
      return f.progress <= read.progress ? read.point : f.contact
    }
    return readInterception(side,flight:f).point
  }

  private func readInterception(_ side: Int, flight f: BallFlight) -> CourtIntercept {
    let p = players[side].pos
    if f.kind == .drop, !attacking[side] { return CourtIntercept(point:f.contact,progress:1) }
    if attacking[side] || abs(p.y - Self.net) < 6.5 || f.isDefensiveLob || (side == 1 && !settings.local && f.kind == .lob),
      let overhead = BallContactWindow.overheadTarget(flight: f, side: side),
      f.progress <= overhead.progress
    {
      let bot = side == 1 && !settings.local
      let timeLeft = f.time(at:overhead.progress)-f.elapsed
      if !bot || p.distance(to:overhead.point) <= Self.contactRadius+runningReach(side,toward:overhead.point,in:timeLeft) {
        return CourtIntercept(point:overhead.point,progress:overhead.progress)
      }
      // An overhead already beyond the runner is a rebound chase. Picking
      // the old air contact would take the defender away from the next bounce.
      return CourtIntercept(point:f.contact,progress:1)
    }
    // Keep a groundstroke run aimed behind the bounce as the player moves
    // through midcourt. Only an attacking player needs an airborne intercept.
    if !f.serve && (attacking[side] || BallContactWindow.inServiceBox(p, side: side)) {
      let origin = f.worldBall(at: 0)
      let dy = f.landing.y - Double(origin.z)
      let t = abs(dy) > 0.001 ? (p.y - Double(origin.z)) / dy : -1
      if BallContactWindow.inServiceBox(p, side: side), f.hitter != side, f.progress < 0.8, t > 0 {
        let at = min(0.94,t)*0.8
        let intercept = f.worldBall(at:at)
        if f.progress <= at && (f.loft < 2 || intercept.y < 3.12) {
          return CourtIntercept(point:Self.own(side,intercept.courtPosition),progress:at)
        }
      }
      let height = sin(t * .pi) * f.loft * 1.7
      if t > 0 && t < 0.95 && f.progress <= t*0.8 && (f.loft < 2 || (t > 0.5 && height <= 1.7)) {
        return CourtIntercept(point:f.courtPosition(at:t*0.8),progress:t*0.8)
      }
    }
    return CourtIntercept(point:f.contact,progress:1)
  }

  func contactGuide(_ side: Int) -> Vec? {
    if let target = serveReceiveTarget(side) { return target }
    if let target = outBallChaseTarget(side) { return target }
    guard phase == .live, let flight, flight.hitter != side, flight.fault == nil else { return nil }
    return intercept(side)
  }

  func contactWindow(_ side: Int, after progress: Double? = nil) -> BallContactWindow? {
    guard let flight, flight.power == nil else { return nil }
    if side == 1 && !settings.local && flight.hitter == 0 && time < reactAt &&
      (flight.stroke == .volley || flight.stroke == .overhead) { return nil }
    if side == 1 && flight.hitter == 0 && flight.opponentError == .unreachable { return nil }
    if side == 1 && flight.dropReachable == false { return nil }
    if let effort = players[side].netEffort {
      if effort.serial == contactSerial {
        guard effort.reachable, (progress ?? flight.progress) <= effort.progress + 0.000001 else { return nil }
        return BallContactWindow(entry: effort.progress, exit: effort.progress, volley: effort.afterBounce != true,
          overhead: effort.stroke.overhead, netStroke: effort.stroke)
      }
      if time < effort.impactTime + effort.stroke.recovery { return nil }
    }
    let window = BallContactWindow.next(flight: flight, player: players[side].pos, side: side, after: progress)
    if window?.netStroke == .dive && players[side].diveDecision == contactSerial { return nil }
    return window
  }

  mutating func prepareNetEffort(_ side: Int, flight f: BallFlight, dt: Double) {
    guard players[side].netEffort == nil, assist == nil, queuedPower == nil,
      f.opponentError != .unreachable, f.dropReachable != false,
      let air = BallContactWindow.netOpportunity(flight: f, player: players[side].pos, side: side, after: f.progress),
      let stroke = air.netStroke, stroke.extended else { return }
    let remaining = max(0, f.time(at:air.entry) - f.elapsed)
    guard remaining <= (stroke == .jump ? 0.23 : 0.21) else { return }
    if stroke == .dive, remaining > 0 {
      // Let an approaching player run into an ordinary volley if there is still time.
      let player = players[side]
      let travel = min(remaining, player.pos.distance(to: player.destination) / max(0.001, player.velocity.length))
      let feet = Vec(x: player.pos.x + player.velocity.x * travel, y: player.pos.y + player.velocity.y * travel)
      if BallContactWindow.netOpportunity(flight: f, player: feet, side: side, after: f.progress)?.netStroke == .volley { return }
    }
    let target = f.worldBall(at: air.entry), from = players[side].pos
    let dx = Double(target.x) - from.x, dz = Double(target.z) - from.y
    let travel = min(stroke == .dive ? 0.94 : 0.34, hypot(dx, dz) * 0.55, (remaining + 0.1) * 3.75)
    let scale = travel / max(0.01, hypot(dx, dz))
    let landing = Self.own(side, Vec(x: from.x + dx * scale, y: from.y + dz * scale))
    let timeNeeded = stroke == .jump ? max(0, Double(target.y)-2.66)/3.2 : max(0, hypot(dx,dz)-0.94)/5.5
    let reachable = air.reachable && remaining + dt >= timeNeeded
    // A well-read drop can be lifted after the bounce. Keep chasing if this
    // earlier airborne interception would leave the receiver on the ground.
    if f.dropReachable == true && !reachable { return }
    players[side].netEffort = NetEffort(stroke: stroke, serial: contactSerial, startTime: time-dt,
      impactTime: time-dt+remaining, progress: air.entry, from: from, landing: landing,
      target: target, reachable: reachable)
    players[side].destination = landing
  }
  mutating func end(_ winner: Int, reason: String, tip: String,
    random: () -> Double = { Double.random(in: 0..<1) }) {
    guard phase == .live else { return }
    let reaction = momentum.finishPoint(winner: winner, game: coach.gameIndex,
      againstOpponent: !settings.local, random: random)
    queuedPower = nil
    assist = nil
    if winner == 0 { awardPowerIfDue(random: random) }
    pointResolution = PointResolution(impact: flight.flatMap(FaultImpact.init), reaction: reaction,
      celebration: WinnerCelebration.select(winner:winner,flight:flight,random:random))
    for side in 0...1 where outBallChaseTarget(side) == nil && !(side == 1 && botChasesOut) {
      players[side].destination = players[side].pos
      players[side].velocity = .zero
      followingApproach[side] = false
    }
    if flight?.hitter == winner && (flight?.stroke == .volley || flight?.stroke == .overhead) {
      tactics[winner].netWinners += 1
    }
    scoring.award(winner)
    if !settings.local && scoring.lastAward != .point { momentum.completedOpponentGame() }
    coach.finishPoint(award: scoring.lastAward, winner: winner, format: scoring.format, time: time)
    phase = scoring.winner == nil ? .point : .finished
    var explanation = reason
    if winner == 1, let f = flight {
      if f.hitter == 0, f.fault != nil {
        if f.serve { explanation += " Use more spin and aim inside the service box." }
        else if let decision = players[0].lastReturn { explanation += " " + decision.lesson }
      } else if f.hitter == 1 && f.fault == nil { explanation += " Move toward yellow earlier." }
    }
    if let serveExplanation { explanation += " " + serveExplanation }
    feedback = Coaching(
      title: "\(name(winner)) won the \(scoring.lastAward.rawValue).", reason: explanation,
      tip: phase == .finished
        ? "Play again to start a new \(scoring.format == .tennis ? "set" : "tiebreak")." : tip)
    history.insert(feedback, at: 0)
  }
  mutating func returnBall(_ side: Int, volley: Bool, overhead: Bool = false, random: () -> Double)
  {
    if side == 1 { prepareOpponentReply(random: random) }
    guard let f = flight else { return }
    if side == 1 && f.opponentError == .unreachable { return }
    if side == 1 && f.dropReachable == false { return }
    let p = players[side]
    let contact = volley ? ball : f.contact
    let gap = f.serve && !volley ? min(p.pos.distance(to: contact), p.pos.distance(to: ball)) : p.pos.distance(to: contact)
    let speed = p.velocity.length
    let bot = side == 1 && !settings.local
    let effort = p.netEffort.flatMap { $0.serial == contactSerial && $0.reachable ? $0 : nil }
    let jumpLob = effort?.stroke == .jumpLob
    let smashLob = bot && overhead && f.kind == .lob && queuedPower == nil && demo == nil
    let swipeLanding = !bot && !jumpLob && p.swipeDepth != nil ? p.aim : nil
    let easyBot = bot && settings.difficulty == .easy
    let ordinaryBot = bot && !jumpLob && !smashLob
    let netReply = ordinaryBot ? f.approachReply : nil
    let dropReply = ordinaryBot && f.kind == .drop
    var aim = p.aim ?? Self.preset(side, p.kind, p.pos)
    var kind = p.kind
    if smashLob {
      aim = CourtTactics.openCourt(side:side,opponent:players[0].pos,overhead:true)
      kind = .cross
    } else if dropReply {
      aim = Vec(x: Self.width / 2, y: Self.length - 0.55)
      kind = .lob
    } else if let netReply {
      switch netReply {
      case .lob:
        aim = Vec(x: clamp(players[0].pos.x + (random() - 0.5) * 2.6, 1.3, 6.93),
          y: Self.length - 0.4 - random() * 0.8)
        kind = .lob
      case .passing:
        let right = abs(players[0].pos.x - Self.width / 2) < 0.8
          ? random() < 0.5 : players[0].pos.x < Self.width / 2
        aim = Vec(x: right ? 7.1 + random() * 0.5 : 0.6 + random() * 0.5,
          y: Self.length - 0.8 - random() * 1.3)
        kind = .line
      case .volley, .miss:
        let cover = CourtTactics.netCoverage(side: 0, opponentContact: p.pos)
        aim = Vec(x: clamp(cover.x + (random() - 0.5) * 1.4, 1.2, 7.03),
          y: Self.net + 6.5 + random() * 1.2)
        kind = .cross
      }
    } else if easyBot && ordinaryBot {
      aim = Self.preset(side, .cross, p.pos)
      kind = .cross
    } else if ordinaryBot {
      let open = players[0].pos.x < 4.115 ? 7.73 : 0.5
      var x = random() < settings.style.risk ? open : (p.pos.x < 4.115 ? 6.6 : 1.6)
      if settings.style == .retriever { x = clamp(8.23 - players[0].pos.x, 1.5, 6.73) }
      aim = Vec(
        x: clamp(x + (random() - 0.5) * 0.5, 0.2, 8.03),
        y: 23.77 - (approach && p.pos.y > 5 ? 5 : settings.style.depth))
      if settings.style == .retriever { kind = .lob }
    }
    if ordinaryBot && !dropReply && netReply == nil {
      if random() < settings.difficulty.shortBallChance {
        aim.y = Self.length - 6.2 - random() * 1.8
        kind = .cross
      } else {
        aim.y = max(aim.y, Self.length - 3.2)
      }
    }
    if bot && queuedPower == .overhead {
      aim = Vec(x: players[0].pos.x, y: Self.net + 5)
      kind = .lob
    }
    if ordinaryBot && !easyBot && kind == .cross && !dropReply && netReply == nil {
      let diagonal = (p.pos.x - Self.width / 2) * (aim.x - Self.width / 2) < 0
      if !diagonal { kind = .line }
      else if aim.y < Self.length - 5 && min(aim.x, Self.width - aim.x) < 1 { kind = .angle }
    }
    let guideGap = p.pos.distance(to: intercept(side))
    let onTime = guideGap <= Self.contactRadius + 0.000001
    let lineApproach =
      settings.allCourtTraining && !settings.local && side == 0
      && p.swipeDepth == nil && p.tappedLanding == nil && onTime && kind == .line && !f.serve && !volley && !overhead
    if !bot && kind == .line && !(volley && p.aim != nil) {
      aim = f.serve && f.serveNumber == 1
        ? Self.aim(side, players[1 - side].pos) : Self.preset(side, .line, p.pos)
    }
    if !bot && (kind == .drop || kind == .slice) {
      aim = Self.preset(side, kind, p.pos)
    }
    if !bot && (volley || overhead) && p.aim == nil {
      aim = CourtTactics.openCourt(side: side, opponent: players[1 - side].pos, overhead: overhead)
    }
    if let target = p.tappedLanding { aim = target }
    var quality = demo == nil && !overhead ? p.rallyContact(gap: gap) : .neutral
    if volley && quality == .planted { quality = .neutral }
    if effort?.stroke == .dive { quality = .diving }
    if quality == .diving && !dropReply {
      kind = .lob
      aim = Vec(x: Self.width / 2, y: side == 0 ? 3.8 : Self.length - 3.8)
    } else if quality == .stretched && !dropReply && kind != .drop && queuedPower == nil {
      // A runner can borrow pace to block but cannot drive deep from full stretch.
      let depth = side == 0 ? aim.y : Self.length - aim.y
      let short = max(5.3, depth)
      aim.y = side == 0 ? short : Self.length - short
    }
    if let swipeLanding { aim = swipeLanding }
    if jumpLob {
      kind = .lob
      aim = Vec(x: Self.width/2, y: side == 0 ? 2.2 : Self.length-2.2)
      quality = .stretched
    }
    let risk = Self.red(aim)
    let settled = onTime && p.settled >= 0.18 && speed < 2.2
    attempts[side] += 1
    if settled { balanced[side] += 1 }
    // Reaching the ring guarantees a swing. Placement is a separate decision for both players.
    let contactChance = quality == .diving || bot || onTime || volley ? 1 : Self.contactChance(
      settings.difficulty, settled: p.settled, gap: gap, speed: speed, risky: risk)
    let controlledFeed = bot && ((overhead && f.isDefensiveLob) || dropReply || f.kind == .slice || f.trainingApproach
      || netReply == .volley || queuedPower == .overhead)
    let redirect = !f.serve && CourtTactics.redirects(from: f.from, at: p.pos, to: aim)
    let decision = ReturnDecision(shot: kind, redirected: redirect,
      shorterSide: redirect && CourtTactics.courtLength(from: p.pos, toward: aim, side: side) + 0.35
        < CourtTactics.courtLength(from: p.pos, toward: f.from, side: side),
      split: !bot && p.splitForReturn == contactSerial,
      baseAccuracy: swipeLanding != nil || quality == .diving || demo != nil || controlledFeed ? 1 : CourtTactics.landingChance(kind: kind, redirects: redirect))
    if !bot { players[side].lastReturn = decision }
    let placementChance = decision.accuracy
    let forcedMiss = bot && f.opponentError != nil && queuedPower != .overhead
    let missedContact = !jumpLob && contactChance < 1 && random() >= contactChance
    if !jumpLob && swipeLanding != nil && missedContact {
      end(f.hitter, reason: "\(name(side)) didn't reach the ball in time.",
          tip: "Move toward the contact circle earlier.", random: random)
      return
    }
    // A reachable lob smash gets a single placement decision. Stacking an
    // ordinary baseline error roll on top would reduce its 75% accuracy.
    let miss = smashLob ? random() < 0.25 : !jumpLob && (forcedMiss || missedContact
      || (placementChance < 1 && random() < 1 - placementChance))
    let reason =
      smashLob ? (miss ? "The opponent reached the lob but missed the overhead." : "The opponent read the lob early and smashed into the open court.")
      : miss ? "\(name(side)) missed the \(kind.rawValue.lowercased()) shot."
      : jumpLob ? "A running jump lifted a defensive lob."
      : quality == .diving ? "A full-stretch dive lifted a defensive lob."
      : quality == .stretched && !dropReply ? "A late contact took pace off the return."
      : dropReply
      ? "Opponent chased your drop shot and lifted a deep lob."
      : netReply != nil
        ? "Opponent read your approach and played \(netReply == .lob ? "a deep lob" : netReply == .passing ? "a passing shot" : netReply == .miss ? "a pressured error" : "a softer volley feed")."
      : easyBot ? "The Easy opponent played crosscourt."
        : onTime && !bot
          ? "On-time contact inside the yellow guide."
          : settled
            ? "Balanced contact with quiet feet."
            : gap > 0.85
              ? String(format: "Stretched %.1f m from the ball.", gap)
              : speed >= 2.2 ? "Still running through contact." : "Too late to settle the feet."
    var fault: String?
    if miss {
      if bot, let planned = f.opponentError { fault = planned.rawValue }
      else { fault = ["net", "wide", "long"][Int(clamp(random(), 0, 0.999999) * 3)] }
    }
    if side == 0 { assessCoachReturn(incoming: f, aim: aim, kind: kind, clean: fault == nil, explicit: p.aim != nil) }
    players[side].aim = nil
    players[side].tappedLanding = nil
    players[side].swipeDepth = nil
    players[side].swingStrength = nil
    if !bot { players[side].kind = .cross }
    if overhead { tactics[side].overheads += 1 } else if volley { tactics[side].volleys += 1 }
    if !bot && (volley || overhead)
      && (aim.x - Self.width / 2) * (players[1 - side].pos.x - Self.width / 2) < 0
    {
      tactics[side].openCourtShots += 1
    }
    feedback = Coaching(
      title: miss ? "Shot missed." : onTime && !bot
        ? "On time. Clean return."
        : settled ? "Early feet. Quiet contact." : "Give yourself more time.", reason: reason,
      tip: risk ? "A red-zone target leaves less margin." : "Recover toward the coverage ring.")
    launch(
      side, aim: aim, kind: kind, fault: fault,
      explanation: reason,
      stroke: overhead ? .overhead : quality == .diving ? .lob : volley ? .volley : kind == .lob ? .lob : .groundstroke,
      trainingApproach: lineApproach && !miss, trainingReply: netReply != nil || dropReply)
    if jumpLob {
      flight?.jumpLob = true
      flight!.loft = 3.3
      flight!.duration *= 1.12
    }
    if effort?.stroke == .dive && !miss {
      flight!.duration *= 1.18
      flight!.loft = max(flight!.loft, 2.65)
    }
    if quality != .diving && netReply == .volley && !volley {
      flight!.duration = max(flight!.duration, settings.difficulty == .easy ? 2.5 : 2.15)
      flight!.loft = 0.9
    } else if quality != .diving && netReply == .passing {
      flight!.duration *= settings.difficulty == .tough ? 0.82 : 0.93
      flight!.loft = 0.85
    }
    if side == 1 && demo == nil {
      let backhand = (flight!.strikeOrigin?.x ?? Float(p.pos.x)) > Float(p.pos.x)
      let reply = ScoutedReply(stretched: quality == .stretched || quality == .diving,
        short: Self.isShortBall(flight!, receiving: 0), backhand: backhand)
      scoutedReplies = Array(((scoutedReplies ?? []) + [reply]).suffix(12))
    }
    flight!.contactQuality = quality
    if demo == nil && !lineApproach {
      let forward = kind == .line ? 1.5 : 1
      flight!.duration /= forward * quality.pace
    }
    if !bot, !jumpLob, f.expectedContactTime != nil, let strength = p.swingStrength {
      let pace: Double
      switch kind {
      case .drop: pace = 28 + 20 * strength
      case .lob, .slice: pace = 44 + 32 * strength
      default: pace = 55 + 55 * strength
      }
      flight?.setLaunchSpeed(kph: pace)
      flight?.swingStrength = strength
    }
    if !bot {
      if volley && !overhead && !miss && abs(p.pos.y - Self.net) <= Self.net - ServeGeometry.serviceLine {
        players[side].madeNetVolley = true
      }
      // Offer the path, but only a subsequent player movement command can start the approach.
      approachAvailable[side] = flight?.returnedShortBall == true
      followingApproach[side] = false
    }
  }

  mutating func updateFootwork(_ dt: Double, humanReceiver: Int? = nil) {
    for i in 0...1 {
      if phase == .serving && servePreparation?.server == i { continue }
      if let flight, flight.isFirstServeFault, flight.hitter != i {
        players[i].destination = players[i].pos
        players[i].velocity = .zero
        players[i].netEffort = nil
        continue
      }
      if var landing = serveLanding, landing.server == i {
        landing.elapsed = min(ServeLanding.duration, landing.elapsed + dt)
        let fraction = StrokeAnimation.ease(landing.progress)
        let position = Vec(x: landing.from.x + (landing.to.x - landing.from.x) * fraction,
          y: landing.from.y + (landing.to.y - landing.from.y) * fraction)
        players[i].velocity = Vec(x: (position.x - players[i].pos.x) / max(dt, 0.000001),
          y: (position.y - players[i].pos.y) / max(dt, 0.000001))
        players[i].pos = position
        players[i].settled = 0
        serveLanding = landing.progress >= 1 ? nil : landing
        if landing.progress >= 1 { landingSerial += 1 }
        continue
      }
      let route = (i == 0 || settings.local) ? committedRun(i) : nil
      if let route {
        players[i].destination = route
      } else if players[i].recoveryFlight == contactSerial, let white = recoveryGuide(i) {
        players[i].destination = white
      }
      var p = players[i]
      if i == humanReceiver { p.destination.y = receivingDepth(p.destination.y, side: i) }
      if let effort = p.netEffort {
        if time < effort.impactTime + effort.stroke.recovery {
          var next = Self.own(i, effort.position(at: time))
          if i == humanReceiver { next.y = receivingDepth(next.y, side: i) }
          players[i].velocity = Vec(x: (next.x-p.pos.x)/max(0.00001,dt), y: (next.y-p.pos.y)/max(0.00001,dt))
          players[i].pos = next
          players[i].settled = 0
          continue
        }
        if effort.stroke == .jumpLob, p.destination.distance(to:effort.landing) < 0.02 {
          p.destination = p.pos
          players[i].destination = p.pos
        }
        players[i].netEffort = nil
        p.netEffort = nil
      }
      let d = p.pos.distance(to: p.destination)
      let (maxSpeed,acceleration,effort) = runningLimits(i,toward:p.destination,distance:d)
      // A tap can split and queue a run together; the hop must not stall that run.
      let splitting = d <= Self.contactRadius && time >= splitStarted[i] && time < splitStarted[i] + 0.18
      let speed = splitting ? 0 : min(maxSpeed, sqrt(2 * acceleration * d))
      let desired =
        d > 0.02
        ? Vec(
          x: (p.destination.x - p.pos.x) / d * speed, y: (p.destination.y - p.pos.y) / d * speed)
        : .zero
      let change = p.velocity.distance(to: desired)
      let fraction = change > 0 ? min(1, acceleration * dt / change) : 1
      p.velocity.x += (desired.x - p.velocity.x) * fraction
      p.velocity.y += (desired.y - p.velocity.y) * fraction
      if route != nil && (d <= 0.02 || dt * (p.velocity.x * (p.destination.x - p.pos.x) + p.velocity.y * (p.destination.y - p.pos.y)) >= d * d) {
        p.pos = p.destination
        p.velocity = .zero
      } else {
        p.pos = Self.own(i, Vec(x: p.pos.x + p.velocity.x * dt, y: p.pos.y + p.velocity.y * dt))
      }
      if i == humanReceiver {
        let allowed = receivingDepth(p.pos.y, side: i)
        if allowed != p.pos.y {
          p.pos.y = allowed
          p.velocity.y = 0
        }
      }
      if demo == nil && phase.isPlaying {
        p.expendEnergy(pace: effort, distance: p.pos.distance(to: players[i].pos), dt: dt, late: lateMatch)
      }
      if d < 0.15 { p.runPace = nil }
      if abs(p.pos.y - Self.net) > Self.net - ServeGeometry.serviceLine { p.madeNetVolley = nil }
      p.settled =
        p.pos.distance(to: intercept(i)) <= 0.85 && p.velocity.length < 2.2 ? p.settled + dt : 0
      players[i] = p
    }
  }

  mutating func step(_ delta: Double, interactiveRally: Bool = false, random: () -> Double = { Double.random(in: 0..<1) }) {
    if demo != nil { stepShotDemo(delta); return }
    guard needsSimulation else { return }
    let dt = clamp(delta, 0, 0.04)
    time += dt
    if isResolvingPoint { stepPointResolution(dt); return }
    startArmedPower()
    if phase == .serving { stepServe(dt, random: random); return }
    if assist != nil { stepAssistedContact(dt, random: random); return }
    if queuedPower == .overhead, flight?.hitter == 1, flight?.fault == nil {
      alignForPower(.overhead)
      stepAssistedContact(dt, random: random)
      return
    }
    guard flight != nil else { return }
    if flight?.power == nil { prepareOpponentReply(contestEveryBall: interactiveRally, random: random) }
    // Commit the first read to this incoming ball. A runner crossing the
    // service line should not repeatedly reverse between volley and bounce.
    // After an airborne chance passes, pursue the rebound.
    if interactiveRally, !settings.local, let incoming = flight, incoming.hitter == 0,
       incoming.opponentIntercept == nil, incoming.fault == nil, incoming.power == nil {
      let read = readInterception(1,flight:incoming)
      flight?.opponentIntercept = read
    }
    if interactiveRally, flight!.progress >= 0.8 { lockRunsAtBounce() }
    let receiver = 1 - flight!.hitter
    let humanReceiving = interactiveRally && (receiver == 0 || settings.local)
    let manualStrike = humanReceiving && flight!.power == nil && flight!.fault == nil && queuedPower == nil
    if manualStrike && flight!.expectedContactTime == nil {
      var shot = flight!
      if shot.elapsed == 0 && !showsGoldenContact(receiver) {
        shot.extendReceiveWindow(to: players[receiver].pos.y, side: receiver)
        flight = shot
      }
      let mark = committedRun(receiver) ?? intercept(receiver)
      let target = Self.own(receiver, Vec(x: mark.x, y: receivingDepth(mark.y, side: receiver)))
      players[receiver].destination = target
      dropGestureEpoch[receiver] = contactSerial
      players[receiver].recoveryFlight = nil
      let entry = BallContactWindow.next(flight: shot, player: target, side: receiver)?.entry ?? 1
      flight?.expectedContactTime = shot.time(at: entry)
    }
    let current = flight!
    if interactiveRally {
      prepareJumpLob(receiver, incoming: current, dt: dt)
    }
    let saving = players[receiver].netEffort.map { $0.serial == contactSerial && $0.stroke == .jumpLob } ?? false
    let swingReady = saving || !manualStrike || (current.swipeFinishedAt != nil && players[receiver].swingStrength != nil)
    if current.bounceDestinations == nil && swingReady && (settings.local || receiver == 0 || time >= reactAt) {
      prepareNetEffort(receiver, flight: current, dt: dt)
      attemptRunningDive(receiver, incoming: current)
    }
    if current.power == nil && !settings.local && receiver == 1 &&
      (interactiveRally || (current.bounceDestinations == nil && time >= reactAt)) {
      if botChasesOut { players[1].destination = Self.own(1, current.contact) }
      else if current.fault == nil {
        players[1].recoveryFlight = nil
        players[1].destination = Self.own(1, intercept(1))
        if !interactiveRally, let miss = current.missedChaseTarget { players[1].destination = miss }
      }
    }
    updateFootwork(dt, humanReceiver: humanReceiving ? receiver : nil)
    updateCoachApproaches()
    updateCoachRecovery()
    flight!.elapsed = current.elapsed + dt
    let f = flight!
    let progress = f.progress
    // Resolve a swept air contact before counting a bounce in the same display frame.
    let window = contactWindow(receiver, after: current.progress)
    var canStrike = swingReady
    if manualStrike, !saving, let window, progress + 0.000001 >= window.entry {
      canStrike = swingReady && f.hasTimelySwing(at: f.time(at: window.entry))
      if !canStrike { flight?.missedSwingWindow = true }
    }
    if canStrike, let window, window.netStroke != nil, progress + 0.000001 >= window.entry {
      let impact = min(progress, max(window.entry, window.exit))
      flight!.elapsed = f.time(at:impact)
      let hit = f.worldBall(at: impact)
      ball = Vec(x: Double(hit.x), y: Double(hit.z))
      returnBall(receiver, volley: window.volley, overhead: window.overhead, random: random)
      return
    }
    if current.progress < 0.8 && progress >= 0.8 {
      bounceSerial += 1
      plantApproachAtBounce(f.hitter)
      if interactiveRally { lockRunsAtBounce() }
    }
    ball = f.position
    if let power = f.power {
      if progress >= 1 { end(0, reason: "\(power.rawValue) winner.", tip: "", random: random) }
      return
    }
    if let fault = f.fault, progress >= 0.8 {
      // Preserve the exact impact frame. Presentation continues independently after the point ends.
      flight!.elapsed = f.time(at:0.8)
      ball = f.landing
      if f.serve && f.serveNumber == 1 {
        phase = .serveFault
        pointResolution = PointResolution(impact: FaultImpact(flight: f))
        coach.receiving = nil
        coach.firstServeWasWide = nil
        for side in 0...1 where outBallChaseTarget(side) == nil && !(side == 1 && botChasesOut) {
          players[side].destination = players[side].pos
        }
        return
      }
      end(
        receiver,
        reason: f.serve && f.serveNumber == 2 ? "Double fault. The second serve \(fault == "net" ? "hit the net" : "landed " + fault)."
          : "\(name(f.hitter) == "You" ? "Your" : name(f.hitter) + "'s") shot \(fault == "net" ? "hit the net" : "landed " + fault).",
        tip: receiver == 0
          ? "Keep moving early and aim into open court."
          : "Aim farther inside the lines on your next shot.", random: random)
      return
    }
    if canStrike, let window, window.netStroke == nil,
      progress + 0.000001 >= window.entry
    {
      returnBall(receiver, volley: window.volley, overhead: window.overhead, random: random)
      return
    }
    if progress < 1 { return }
    if manualStrike {
      end(f.hitter, reason: "\(name(receiver)) missed the return.",
        tip: "Reach yellow and finish your swipe just before the ball reaches your racket.", random: random)
      return
    }
    let gap = players[receiver].pos.distance(to: f.contact)
    if f.serve || (players[receiver].diveDecision == contactSerial && gap > Self.contactRadius) || gap > 1.35 || players[receiver].netEffort != nil || current.opponentError == .unreachable || current.dropReachable == false {
      if receiver == 1 && !settings.local { opponentErrors.resetAfterMiss() }
      end(
        f.hitter,
        reason: current.dropReachable == false ? "Opponent couldn't lift the drop shot before its second bounce." : "\(name(receiver)) didn't reach the ball in time.",
        tip: receiver == 0
          ? "Swipe toward yellow sooner for the next ball."
          : "Keep using the open court to move your opponent.", random: random)
      return
    }
    returnBall(receiver, volley: false, random: random)
  }
}
