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
  var difficulty: Difficulty = .easy
  var style: BotStyle = .baseline
  var surface: CourtSurface = .grass
  var allCourtTraining = true
  var scoring: PracticeScoring = .tennis
  var playerName = ""
  var opponentName = ""

  enum CodingKeys: String, CodingKey {
    case local, difficulty, style, surface, allCourtTraining, scoring, playerName, opponentName
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
    difficulty = try values.decodeIfPresent(Difficulty.self, forKey: .difficulty) ?? .easy
    style = try values.decodeIfPresent(BotStyle.self, forKey: .style) ?? .baseline
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
}
struct BallFlight: Codable {
  var from: Vec, landing: Vec, contact: Vec
  var strikeOrigin: CourtPoint3D?
  var elapsed = 0.0
  var duration: Double
  var hitter: Int
  var fault: String?
  var explanation: String
  var loft: Double
  var power: CourtPower?
  var acknowledge = false
  var serve = false
  var serveNumber = 1
  var serveProfile: ServeProfile?
  var receiverWrongFooted: Bool?
  var kind: ShotKind = .cross
  var stroke: TennisStrokeStyle = .groundstroke
  var trainingApproach = false
  var trainingReply = false
  var opponentReplyPrepared = false
  var opponentError: OpponentError?
  var missedChaseTarget: Vec?
  var dropReachable: Bool?
  var approachReply: ApproachReply?
  var progress: Double {
    // Smashes rebound all the way past the baseline. Give that longer leg its own flight time.
    if power == .overhead && elapsed > duration * 0.8 {
      let reboundTime = max(duration * 0.2, landing.distance(to: contact) / 21)
      return min(1, 0.8 + 0.2 * (elapsed - duration * 0.8) / reboundTime)
    }
    return min(1, elapsed / duration)
  }
  var position: Vec {
    let t = progress
    if t < 0.8 {
      return Vec(
        x: from.x + (landing.x - from.x) * t / 0.8, y: from.y + (landing.y - from.y) * t / 0.8)
    }
    return Vec(
      x: landing.x + (contact.x - landing.x) * (t - 0.8) / 0.2,
      y: landing.y + (contact.y - landing.y) * (t - 0.8) / 0.2)
  }
  var height: Double {
    if progress >= 0.8, let power {
      let t = (progress - 0.8) / 0.2
      if power == .overhead { return 5.5 * sin(t * .pi / 2) }
      let rise = sin(t * .pi / 2) * 0.6
      return power == .ace ? rise * 1.25 * (serveProfile?.kick ?? 1) : rise
    }
    if progress >= 0.8 && kind == .drop {
      let bounce = (progress - 0.8) / 0.2
      return 0.28 * 4 * bounce * (1 - bounce)
    }
    return progress < 0.8
      ? sin(progress / 0.8 * .pi) * loft * 1.7 : sin((progress - 0.8) / 0.2 * .pi / 2) * (kind == .slice ? 0.35 : 0.6) * (serveProfile?.kick ?? 1)
  }
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
    case landingSerial, ball, rally, bestRally, time, reactAt, approach, balanced, attempts, feedback
    case history, contactSerial, bounceSerial, attacking, followingApproach, approachAvailable
    case splitStarted, splitTimed, tactics, opponentErrors, coach, dropGestureEpoch, dropReturns
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
  var phase: PracticePhase = .ready
  var flight: BallFlight?
  var pointResolution: PointResolution?
  var servePreparation: ServePreparation?
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
    tip: "Tap your half to move. Swipe toward the other half to aim. Swings are assisted.")
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
    scoring = PracticeScore(format: settings.scoring)
  }
  func name(_ side: Int) -> String { settings.name(side) }
  static func own(_ side: Int, _ p: Vec) -> Vec {
    Vec(
      x: clamp(p.x, -1.6, 9.83), y: side == 0 ? clamp(p.y, 12.585, 26.27) : clamp(p.y, -2.5, 11.185)
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
  static func recovery(_ side: Int, _ contact: Vec) -> Vec {
    let center = width / 2
    let crosscourtOffset = clamp(center - contact.x, -recoveryOffsetLimit, recoveryOffsetLimit)
    return Vec(x: center + crosscourtOffset, y: side == 0 ? length : 0)
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
    guard phase != .serving || servePreparation?.server != side else { return }
    players[side].kind = kind
    players[side].aim = Self.preset(side, kind, players[side].pos)
    if side == 0, demo != nil, canChooseShot(side) {
      let epoch = shotGestureEpoch(side)
      demo?.chosenShot = kind
      demo?.chosenEpoch = epoch
    }
  }
  mutating func recover(_ side: Int) {
    attacking[side] = false
    followingApproach[side] = false
    approachAvailable[side] = false
    players[side].destination = Self.recovery(side, flight?.contact ?? players[1 - side].pos)
  }
  mutating func move(_ side: Int, to point: Vec) {
    guard phase != .serving || servePreparation?.server != side else { return }
    followingApproach[side] = false
    players[side].destination = Self.own(side, point)
  }
  mutating func start(random: () -> Double = { Double.random(in: 0..<1) }) {
    guard phase == .ready || phase == .point else { return }
    for i in 0...1 {
      let p = Vec(x: 4.115, y: i == 0 ? 24.6 : -0.8)
      players[i].pos = p
      players[i].destination = p
      players[i].velocity = .zero
      players[i].settled = 0
      players[i].aim = nil
      if players[i].kind == .drop || players[i].kind == .slice { players[i].kind = .cross }
    }
    phase = .serving
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
        : "Drag blue to aim; tap your side of the court to serve.")
  }

  mutating func launch(
    _ side: Int, aim: Vec, kind: ShotKind, fault: String? = nil, explanation: String = "",
    serve: Bool = false, serveNumber: Int = 1, serveProfile: ServeProfile? = nil, stroke: TennisStrokeStyle = .groundstroke,
    trainingApproach: Bool = false, trainingReply: Bool = false
  ) {
    let from = players[side].pos
    var landing = aim
    if fault == "wide" { landing.x = aim.x < 4.115 ? -0.5 : 8.73 }
    if fault == "long" {
      landing.y = serve ? (side == 0 ? ServeGeometry.serviceLine - 0.45 : Self.length - ServeGeometry.serviceLine + 0.45)
        : (side == 0 ? -0.6 : 24.37)
    }
    if fault == "net" {
      // Hit the mesh along the intended shot's line, not the far landing target's x position.
      let depth = aim.y - from.y
      let fraction = abs(depth) > 0.000001 ? clamp((Self.net - from.y) / depth, 0, 1) : 0
      landing = Vec(x: from.x + (aim.x - from.x) * fraction, y: Self.net)
    }
    var contact = Vec(
      x: landing.x, y: landing.y + (side == 0 ? -1 : 1) * (kind == .drop ? 0.3 : kind == .angle ? 0.45 : 1.1))
    if serve { contact = ServeGeometry.contact(from: from, landing: landing, server: side, number: serveNumber) }
    let bot = side == 1 && !settings.local
    let pace = (bot ? settings.style.pace * settings.difficulty.speed : 1) * settings.surface.pace
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
      duration = clamp(from.distance(to: landing) / (24 * pace) + 0.35, 0.95, 1.8) / profile.pace
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
      let speed = settings.style.speed * settings.difficulty.speed * (wrongFooted ? 0.6 : 1)
      let travel = CourtTactics.travelTime(
        distance: players[1].pos.distance(to: contact), speed: speed)
      duration = max(duration, (travel + 0.15) / 0.86)
    }
    // The next flight leaves the exact 3D point reached by the incoming ball on this tick.
    let impact = serve ? serviceImpact(at: from, side: side, explosive: queuedPower == .ace)
      : flight.flatMap { $0.hitter != side ? $0.worldBall(at: $0.progress) : nil } ?? from.world(height: 0.93)
    pointResolution = nil
    flight = BallFlight(
      from: from, landing: landing, contact: contact, strikeOrigin: impact, duration: duration, hitter: side,
      fault: fault, explanation: explanation, loft: loft, serve: serve, serveNumber: serveNumber,
      serveProfile: profile, receiverWrongFooted: wrongFooted, kind: kind, stroke: serve ? .serve : kind == .drop ? .drop : kind == .slice ? .slice : stroke, trainingApproach: trainingApproach,
      trainingReply: trainingReply)
    ball = from
    players[1 - side].settled = 0
    reactAt = time + (trainingApproach ? 0.08 : settings.difficulty.reaction)
    rally += 1
    bestRally = max(bestRally, rally)
    contactSerial += 1
    dropGestureEpoch = [nil, nil]
    if bot {
      approach = settings.style == .volley || (settings.style == .allcourt && from.y > 3)
      players[1].destination =
        approach ? Vec(x: clamp(aim.x, 2, 6.23), y: 8) : Self.recovery(1, contact)
      if settings.style == .retriever { players[1].destination.y = -1.7 }
    }
    let receiver = 1 - side
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
    let p = players[side].pos
    if attacking[side] || abs(p.y - Self.net) < 6.5,
      let overhead = BallContactWindow.overheadTarget(flight: f, side: side),
      f.progress <= overhead.progress
    {
      return overhead.point
    }
    if (side == 0 ? p.y < 19 : p.y > 4.77) && !f.serve {
      let t = (p.y - f.from.y) / (f.landing.y - f.from.y)
      let height = sin(t * .pi) * f.loft * 1.7
      if t > 0 && t < 0.95 && (f.loft < 2 || (t > 0.5 && height <= 1.7)) {
        return Vec(x: f.from.x + (f.landing.x - f.from.x) * t, y: p.y)
      }
    }
    return f.contact
  }

  func contactGuide(_ side: Int) -> Vec? {
    if let target = serveReceiveTarget(side) { return target }
    if let target = outBallChaseTarget(side) { return target }
    guard phase == .live, let flight, flight.hitter != side, flight.fault == nil else { return nil }
    return intercept(side)
  }

  func contactWindow(_ side: Int) -> BallContactWindow? {
    guard let flight, flight.power == nil else { return nil }
    if side == 1 && flight.hitter == 0 && flight.opponentError == .unreachable { return nil }
    if side == 1 && flight.dropReachable == false { return nil }
    return BallContactWindow.next(flight: flight, player: players[side].pos, side: side)
  }
  mutating func end(_ winner: Int, reason: String, tip: String,
    random: () -> Double = { Double.random(in: 0..<1) }) {
    guard phase == .live else { return }
    let reaction = momentum.finishPoint(winner: winner, game: coach.gameIndex,
      againstOpponent: !settings.local, random: random)
    queuedPower = nil
    assist = nil
    if winner == 0 { awardPowerIfDue(random: random) }
    pointResolution = PointResolution(impact: flight.flatMap(FaultImpact.init), reaction: reaction)
    for side in 0...1 where outBallChaseTarget(side) == nil {
      players[side].destination = players[side].pos
    }
    if flight?.hitter == winner && (flight?.stroke == .volley || flight?.stroke == .overhead) {
      tactics[winner].netWinners += 1
    }
    scoring.award(winner)
    coach.finishPoint(award: scoring.lastAward, winner: winner, format: scoring.format, time: time)
    phase = scoring.winner == nil ? .point : .finished
    feedback = Coaching(
      title: "\(name(winner)) won the \(scoring.lastAward.rawValue).", reason: reason,
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
    let gap = p.pos.distance(to: contact)
    let speed = p.velocity.length
    let bot = side == 1 && !settings.local
    let easyBot = bot && settings.difficulty == .easy
    let netReply = bot ? f.approachReply : nil
    let dropReply = bot && f.kind == .drop
    var aim = p.aim ?? Self.preset(side, p.kind, p.pos)
    var kind = p.kind
    if dropReply {
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
    } else if easyBot {
      aim = Self.preset(side, .cross, p.pos)
      kind = .cross
    } else if bot {
      let open = players[0].pos.x < 4.115 ? 7.73 : 0.5
      var x = random() < settings.style.risk ? open : (p.pos.x < 4.115 ? 6.6 : 1.6)
      if settings.style == .retriever { x = clamp(8.23 - players[0].pos.x, 1.5, 6.73) }
      aim = Vec(
        x: clamp(x + (random() - 0.5) * 0.5, 0.2, 8.03),
        y: 23.77 - (approach && p.pos.y > 5 ? 5 : settings.style.depth))
      if settings.style == .retriever { kind = .lob }
    }
    if bot && !dropReply && netReply == nil {
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
    if bot && !easyBot && kind == .cross && !dropReply && netReply == nil {
      let diagonal = (p.pos.x - Self.width / 2) * (aim.x - Self.width / 2) < 0
      if !diagonal { kind = .line }
      else if aim.y < Self.length - 5 && min(aim.x, Self.width - aim.x) < 1 { kind = .angle }
    }
    let guideGap = p.pos.distance(to: intercept(side))
    let onTime = guideGap <= Self.contactRadius + 0.000001
    let lineApproach =
      settings.allCourtTraining && !settings.local && side == 0
      && onTime && kind == .line && !f.serve && !volley && !overhead
    if !bot && kind == .line {
      aim = f.serve && f.serveNumber == 1
        ? Self.aim(side, players[1 - side].pos) : Self.preset(side, .line, p.pos)
    }
    if !bot && (kind == .drop || kind == .slice) {
      aim = Self.preset(side, kind, p.pos)
    }
    if !bot && (volley || overhead) && p.aim == nil {
      aim = CourtTactics.openCourt(side: side, opponent: players[1 - side].pos, overhead: overhead)
    }
    let risk = Self.red(aim)
    let settled = onTime && p.settled >= 0.18 && speed < 2.2
    attempts[side] += 1
    if settled { balanced[side] += 1 }
    // Reaching the ring guarantees a swing. Placement is a separate decision for both players.
    let contactChance = bot || onTime ? 1 : Self.contactChance(
      settings.difficulty, settled: p.settled, gap: gap, speed: speed, risky: risk)
    let controlledFeed = bot && (dropReply || f.kind == .slice || f.trainingApproach
      || netReply == .volley || queuedPower == .overhead)
    let redirect = !f.serve && CourtTactics.redirects(from: f.from, at: p.pos, to: aim)
    let placementChance = demo != nil || controlledFeed ? 1 : CourtTactics.landingChance(kind: kind, redirects: redirect)
    let forcedMiss = bot && f.opponentError != nil && queuedPower != .overhead
    let miss = forcedMiss || (contactChance < 1 && random() >= contactChance)
      || (placementChance < 1 && random() < 1 - placementChance)
    let reason =
      miss ? "\(name(side)) missed the \(kind.rawValue.lowercased()) shot."
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
    if !bot && (kind == .drop || kind == .slice) { players[side].kind = .cross }
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
      stroke: (bot && kind == .lob) ? .lob : overhead ? .overhead : volley ? .volley : .groundstroke,
      trainingApproach: lineApproach && !miss, trainingReply: netReply != nil || dropReply)
    if netReply == .volley {
      flight!.duration = max(flight!.duration, settings.difficulty == .easy ? 2.5 : 2.15)
      flight!.loft = 0.9
    } else if netReply == .passing {
      flight!.duration *= settings.difficulty == .tough ? 0.82 : 0.93
      flight!.loft = 0.85
    }
    if !bot {
      // Offer the path, but only a subsequent player movement command can start the approach.
      approachAvailable[side] = lineApproach && !miss
      followingApproach[side] = false
    }
  }

  mutating func updateFootwork(_ dt: Double) {
    for i in 0...1 {
      if phase == .serving && servePreparation?.server == i { continue }
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
      var p = players[i]
      let d = p.pos.distance(to: p.destination)
      let shortBallBoost = (i == 0 || settings.local) && showsGoldenContact(i) ? 1.5 : 1.0
      let baseSpeed = i == 1 && !settings.local
        ? (flight?.hitter == 0 && flight?.kind == .drop ? 7.0 : settings.style.speed) * settings.difficulty.speed : 6
      let turning = flight?.receiverWrongFooted == true && flight?.hitter == 1 - i && phase == .live
      let maxSpeed = baseSpeed * shortBallBoost * (turning ? 0.6 : 1)
      let acceleration = 11 * shortBallBoost
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
      p.pos = Self.own(i, Vec(x: p.pos.x + p.velocity.x * dt, y: p.pos.y + p.velocity.y * dt))
      p.settled =
        p.pos.distance(to: intercept(i)) <= 0.85 && p.velocity.length < 2.2 ? p.settled + dt : 0
      players[i] = p
    }
  }

  mutating func step(_ delta: Double, random: () -> Double = { Double.random(in: 0..<1) }) {
    if demo != nil { stepShotDemo(delta); return }
    guard needsSimulation else { return }
    let dt = clamp(delta, 0, 0.04)
    time += dt
    if isResolvingPoint { stepPointResolution(dt); return }
    if phase == .serving { stepServe(dt, random: random); return }
    if assist != nil { stepAssistedContact(dt, random: random); return }
    if queuedPower == .overhead, flight?.hitter == 1, flight?.fault == nil {
      alignForPower(.overhead)
      stepAssistedContact(dt, random: random)
      return
    }
    guard flight != nil else { return }
    if flight?.power == nil { prepareOpponentReply(random: random) }
    let current = flight!
    let receiver = 1 - current.hitter
    if current.power == nil && !settings.local && receiver == 1 && time >= reactAt {
      players[1].destination = current.missedChaseTarget ?? Self.own(1, intercept(1))
    }
    updateFootwork(dt)
    updateCoachApproaches()
    updateCoachRecovery()
    flight!.elapsed += dt
    let f = flight!
    let progress = f.progress
    if current.progress < 0.8 && progress >= 0.8 {
      bounceSerial += 1
      plantApproachAtBounce(f.hitter)
    }
    ball = f.position
    if let power = f.power {
      if progress >= 1 { end(0, reason: "\(power.rawValue) winner.", tip: "", random: random) }
      return
    }
    if let fault = f.fault, progress >= 0.8 {
      // Preserve the exact impact frame. Presentation continues independently after the point ends.
      flight!.elapsed = f.duration * 0.8
      ball = f.landing
      if f.serve && f.serveNumber == 1 {
        phase = .serveFault
        pointResolution = PointResolution(impact: FaultImpact(flight: f))
        coach.receiving = nil
        coach.firstServeWasWide = nil
        for side in 0...1 where outBallChaseTarget(side) == nil {
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
          : "Aim farther inside the lines on your next shot.")
      return
    }
    if current.opponentError != .unreachable, current.dropReachable != false, let window = BallContactWindow.next(
      flight: f, player: players[receiver].pos, side: receiver, after: current.progress),
      progress + 0.000001 >= window.entry
    {
      returnBall(receiver, volley: window.volley, overhead: window.overhead, random: random)
      return
    }
    if progress < 1 { return }
    let gap = players[receiver].pos.distance(to: f.contact)
    if gap > 1.35 || current.opponentError == .unreachable || current.dropReachable == false {
      if receiver == 1 && !settings.local { opponentErrors.resetAfterMiss() }
      end(
        f.hitter,
        reason: current.dropReachable == false ? "Opponent couldn't lift the drop shot before its second bounce." : "\(name(receiver)) didn't reach the ball in time.",
        tip: receiver == 0
          ? "Tap yellow sooner for the next ball."
          : "Keep using the open court to move your opponent.")
      return
    }
    returnBall(receiver, volley: false, random: random)
  }
}
