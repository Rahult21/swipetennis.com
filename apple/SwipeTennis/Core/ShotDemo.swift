import Foundation

enum DemoLesson: String, Codable, CaseIterable, Identifiable {
  case rallyRecovery, recoverySplit
  case crosscourt, downLine, shortAngle, centerLob, dropShot, slice
  case approachVolley, overhead, firstReturn, secondReturn, serveWide, serveCenter, serveBody
  var id: String { rawValue }
  static let courtEntrySkills: [DemoLesson] = [.rallyRecovery, .recoverySplit, .crosscourt, .downLine, .shortAngle]
  var isFootwork: Bool { self == .rallyRecovery || self == .recoverySplit }
  var number: Int { Self.allCases.firstIndex(of: self)! + 1 }
  var title: String {
    switch self {
    case .rallyRecovery: return "Rally & recovery"
    case .recoverySplit: return "Recover & split step"
    case .crosscourt: return "Crosscourt"
    case .downLine: return "Down the line"
    case .shortAngle: return "Short angle"
    case .centerLob: return "Center lob"
    case .dropShot: return "Drop shot"
    case .slice: return "Crosscourt slice"
    case .approachVolley: return "Approach & volley"
    case .overhead: return "Overhead"
    case .firstReturn: return "First-serve return"
    case .secondReturn: return "Second-serve return"
    case .serveWide: return "Serve wide"
    case .serveCenter: return "Serve down the T"
    case .serveBody: return "Body serve"
    }
  }
  var symbol: String {
    switch self {
    case .rallyRecovery: return "arrow.left.arrow.right"
    case .recoverySplit: return "figure.tennis"
    case .crosscourt, .secondReturn: return "arrow.up.right"
    case .downLine, .firstReturn: return "arrow.up"
    case .shortAngle: return "arrow.left.and.right"
    case .centerLob: return "arrow.down"
    case .dropShot: return "arrow.clockwise"
    case .slice: return "arrow.down.right"
    case .approachVolley: return "figure.tennis"
    case .overhead: return "arrow.up.to.line"
    default: return "scope"
    }
  }
  var instruction: String {
    switch self {
    case .rallyRecovery: return "Swipe toward yellow to receive. After the automatic hit, swipe toward white and reach it. Repeat for \(ShotDemoRun.exchangesPerAttempt) exchanges. No shot swipe needed."
    case .recoverySplit: return "Swipe toward yellow to receive, then toward white to recover. At white, tap again as your shot bounces across the net (within 3 m). Repeat \(ShotDemoRun.exchangesPerAttempt) times."
    case .crosscourt: return "Swipe toward yellow. While moving, swipe diagonally from your player toward the opposite side."
    case .downLine: return "Swipe toward yellow. While moving, swipe straight toward the net from your player."
    case .shortAngle: return "Swipe toward yellow, then swipe sideways from your player toward the opposite sideline."
    case .centerLob: return "Swipe toward yellow behind the baseline. Swipe straight back from your player to lob through center."
    case .dropShot: return "Swipe toward yellow first. Draw a quick, closed circle before the ball arrives."
    case .slice: return "Swipe toward yellow. Swipe from either net post to the diagonally opposite end of your baseline."
    case .approachVolley: return "Swipe toward gold, then swipe up from your moving player. After the hit, swipe forward to approach. Tap in position for the volley."
    case .overhead: return "Swipe a little toward yellow to get under the lob. Once there, tap to prepare the overhead smash."
    case .firstReturn: return "Swipe toward yellow early. Swipe up from your player to return straight back at the server."
    case .secondReturn: return "Swipe toward yellow inside the baseline. Swipe diagonally from your player and meet the second serve early."
    default: return "Drag blue into the mint target, then tap your half of the court to serve."
    }
  }
  var shot: ShotKind {
    switch self {
    case .rallyRecovery, .recoverySplit, .crosscourt, .secondReturn: return .cross
    case .shortAngle: return .angle
    case .centerLob: return .lob
    case .dropShot: return .drop
    case .slice: return .slice
    default: return .line
    }
  }
  var placement: ServePlacement? {
    switch self { case .serveWide: return .wide; case .serveCenter: return .center; case .serveBody: return .body; default: return nil }
  }
  var isReturn: Bool { self == .firstReturn || self == .secondReturn }
}

struct DemoOutcome: Equatable {
  let id: UUID
  let success: Bool
  let message: String
  let demonstration: Bool
}

struct DemoMastery: Codable, Equatable {
  static let target = 6
  var streak = 0
  var attempts = 0
  var recentAttempts: [UUID] = []
  private(set) var earnedMastery = false
  var isMastered: Bool { earnedMastery || streak >= Self.target }
  var completedAttempts: Int { min(streak, Self.target) }
  enum CodingKeys: String, CodingKey { case streak, attempts, recentAttempts, earnedMastery }
  init() {}
  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    streak = try values.decode(Int.self, forKey: .streak)
    attempts = try values.decode(Int.self, forKey: .attempts)
    recentAttempts = try values.decode([UUID].self, forKey: .recentAttempts)
    // Older saves used a two-attempt target. Preserve earned skills without
    // treating new two-to-five-attempt streaks as completed after a relaunch.
    earnedMastery = try values.decodeIfPresent(Bool.self, forKey: .earnedMastery) ?? (streak >= 2)
  }
  @discardableResult mutating func record(_ outcome: DemoOutcome) -> Bool {
    guard !outcome.demonstration, !isMastered, !recentAttempts.contains(outcome.id) else { return false }
    attempts += 1
    streak = outcome.success ? min(Self.target, streak + 1) : 0
    earnedMastery = streak >= Self.target
    recentAttempts.append(outcome.id)
    if recentAttempts.count > 32 { recentAttempts.removeFirst(recentAttempts.count - 32) }
    return true
  }
}

struct DemoProgress: Codable, Equatable {
  var lessons: [String: DemoMastery] = [:]
  var lastLesson: DemoLesson?
  func mastery(_ lesson: DemoLesson) -> DemoMastery { lessons[lesson.rawValue] ?? DemoMastery() }
  var remaining: [DemoLesson] { DemoLesson.allCases.filter { !mastery($0).isMastered } }
  var requiredRemaining: [DemoLesson] { DemoLesson.courtEntrySkills.filter { !mastery($0).isMastered } }
  var unlocksCourt: Bool { requiredRemaining.isEmpty }
  var requiredMasteredCount: Int { DemoLesson.courtEntrySkills.count - requiredRemaining.count }
  var next: DemoLesson? {
    if !unlocksCourt {
      if let lastLesson, requiredRemaining.contains(lastLesson) { return lastLesson }
      return requiredRemaining.first
    }
    if let lastLesson, !mastery(lastLesson).isMastered { return lastLesson }
    return remaining.first
  }
  @discardableResult mutating func record(_ result: DemoOutcome, lesson: DemoLesson) -> Bool {
    var value = mastery(lesson)
    guard value.record(result) else { return false }
    lessons[lesson.rawValue] = value
    lastLesson = lesson
    return true
  }
}

struct DemoProgressArchive: Codable {
  static let guest = "guest"
  var profiles: [String: DemoProgress] = [:]
  var guestClaimedBy: String?
  static func profile(for userID: String?) -> String { userID.map { "apple:\($0)" } ?? guest }
  mutating func claimGuest(for profile: String) {
    guard profile != Self.guest, guestClaimedBy == nil else { return }
    var owned = profiles[profile] ?? DemoProgress()
    let guest = profiles[Self.guest] ?? DemoProgress()
    for lesson in DemoLesson.allCases {
      let previous = guest.mastery(lesson), current = owned.mastery(lesson)
      if (previous.isMastered && !current.isMastered)
        || (previous.isMastered == current.isMastered
          && (previous.streak > current.streak || (previous.streak == current.streak && previous.attempts > current.attempts))) {
        owned.lessons[lesson.rawValue] = previous
      }
    }
    if owned.lastLesson == nil { owned.lastLesson = guest.lastLesson }
    profiles[profile] = owned
    profiles[Self.guest] = DemoProgress()
    guestClaimedBy = profile
  }
}

/// A stable presented learning flow replaces its lesson in place. Late callbacks
/// from the previous lesson cannot advance (or stop) the new lesson.
struct DemoLessonFlow {
  private(set) var current: DemoLesson?
  init(first: DemoLesson) { current = first }
  @discardableResult mutating func advance(after finished: DemoLesson, progress: DemoProgress) -> Bool {
    guard current == finished, progress.mastery(finished).isMastered else { return false }
    current = progress.next
    return true
  }
}

enum DemoPace {
  static let initialSpeedMultiplier = 1.2

  /// Blend ball speed, not seconds. Start 20% faster than the old training
  /// feed and remove its remaining slowdown evenly across the curriculum.
  /// Match timing is supplied by launch(), preserving each shot's own physics.
  static func duration(match: Double, training: Double, lesson: DemoLesson) -> Double {
    let start = max(match, training / initialSpeedMultiplier)
    let progress = Double(lesson.number - 1) / Double(max(1, DemoLesson.allCases.count - 1))
    return 1 / ((1 - progress) / start + progress / match)
  }
}

enum DemoStage { case receive, rallyRecovery, approachFlight, volleyReceive, finishFlight }
struct ShotDemoRun {
  static let exchangesPerAttempt = 4
  let lesson: DemoLesson
  let id = UUID()
  let demonstration: Bool
  let attempt: Int
  var stage: DemoStage = .receive
  var stageTime = 0.0
  var chosenShot: ShotKind?
  var chosenEpoch: Int?
  var serveAdjusted = false
  var target: Vec?
  var initialBlue: Vec?
  var approached = false
  var failure: String?
  var result: DemoOutcome?
  var scriptTap = false
  var scriptShot = false
  var completedExchanges = 0
  var recoveryTarget: Vec?
  var recoveredAt: Double?
  var bounceWindowOpen = false
  var splitAfterRecovery = false
  var instruction: String {
    if stage == .rallyRecovery {
      if recoveredAt == nil { return "Return sent. Swipe toward WHITE now and reach the recovery circle." }
      if lesson == .recoverySplit && !splitAfterRecovery {
        return bounceWindowOpen ? "Tap NOW to split. Your shot is within 3 m of its bounce." : "At white, watch the far court. Tap as your shot bounces."
      }
      return "Ready at white. Watch your opponent, then swipe toward the next yellow circle."
    }
    if lesson.isFootwork && stage == .receive {
      return "Swipe toward YELLOW and reach it before the ball. Your player returns automatically; then go back to white."
    }
    if stage == .approachFlight { return "Your shot is away. Swipe forward before it bounces to follow it in." }
    if stage == .volleyReceive { return "Swipe toward yellow if you need to move. Once in position, tap for a volley before the bounce." }
    if stage == .finishFlight { return "Watch your shot land." }
    return lesson.instruction
  }
}

extension PracticeEngine {
  mutating func beginShotDemo(_ lesson: DemoLesson, attempt: Int, demonstration: Bool) {
    self = PracticeEngine(settings: .init(difficulty: .easy, surface: .hard, allCourtTraining: false))
    let run = ShotDemoRun(lesson: lesson, demonstration: demonstration, attempt: attempt)
    if lesson.placement != nil || lesson.isReturn {
      scoring = PracticeScore(format: .tennis, firstServer: lesson.placement == nil ? 1 : 0)
      start(random: { 0.5 })
      demo = run
      if let placement = lesson.placement {
        let target = ServeGeometry.target(placement, from: players[0].pos, receiver: players[1].pos, server: 0, fromRight: true)
        let initial = ServeGeometry.target(placement == .body ? .wide : .body,
          from: players[0].pos, receiver: players[1].pos, server: 0, fromRight: true)
        servePreparation?.target = initial
        servePreparation?.destination = initial
        demo?.target = target
        demo?.initialBlue = initial
      } else if lesson == .secondReturn {
        servePreparation?.number = 2
      }
      return
    }
    demo = run
    phase = .live
    let x = attempt.isMultiple(of: 2) ? 2.1 : 6.13
    players[0].pos = Vec(x: Self.width / 2, y: lesson == .overhead ? 16 : 24.5)
    players[0].destination = players[0].pos
    players[1].pos = Vec(x: Self.width - x, y: 1)
    players[1].destination = players[1].pos
    let y = lesson == .centerLob ? 23.5 : lesson == .approachVolley || lesson == .dropShot ? 17.6 : 22.3
    launch(1, aim: Vec(x: x, y: y), kind: lesson == .overhead ? .lob : .cross)
    applyDemoPace(trainingDuration: 3.8)
    if lesson == .overhead {
      attacking[0] = true
      flight?.landing.y = 23
      flight?.contact.y = 24.1
    }
  }

  mutating func finishShotDemo(success: Bool, message: String) {
    guard let run = demo, run.result == nil else { return }
    demo?.result = DemoOutcome(id: run.id, success: success, message: message, demonstration: run.demonstration)
    phase = .point
    pointResolution = nil
    for side in 0...1 { players[side].destination = players[side].pos; players[side].velocity = .zero }
  }

  mutating func applyDemoPace(trainingDuration: Double) {
    guard let run = demo, let current = flight else { return }
    flight?.duration = DemoPace.duration(match: current.duration, training: trainingDuration, lesson: run.lesson)
  }

  /// Uses the same movement, input, serve, contact windows and return physics as match play.
  /// Footwork drills continue through four return/recovery cycles; shot drills evaluate
  /// the actual bounce. Neither kind awards match scores or Coachability points.
  mutating func stepShotDemo(_ delta: Double) {
    guard demo?.result == nil, phase.isPlaying else { return }
    let dt = clamp(delta, 0, 0.04)
    time += dt
    demo?.stageTime += dt
    if demo?.demonstration == true { performDemoScript() }
    if phase == .serving {
      stepServe(dt, random: { 0.5 })
      if phase == .live, flight?.hitter == 1 { applyDemoPace(trainingDuration: 3.2) }
      if phase == .live, flight?.hitter == 0 {
        demo?.stage = .finishFlight
        demo?.stageTime = 0
        if demo?.serveAdjusted != true { demo?.failure = "Drag blue to choose your serve placement first." }
        else if let target = demo?.target, flight!.landing.distance(to: target) > 0.5 {
          demo?.failure = "Bring the center of blue into the mint target before serving."
        }
      }
      return
    }
    guard let previous = flight, let run = demo else { return }
    if previous.hitter == 1 { prepareNetEffort(0, flight: previous, dt: dt) }
    updateFootwork(dt)
    updateDemoRecovery()
    flight!.elapsed += dt
    let receive = previous.hitter == 1 ? contactWindow(0, after: previous.progress) : nil
    if let receive, receive.netStroke != nil, flight!.progress >= receive.entry {
      flight!.elapsed = min(flight!.progress, receive.exit) * previous.duration
    }
    let current = flight!
    let world = current.worldBall(at: current.progress)
    ball = Vec(x: Double(world.x), y: Double(world.z))
    let windowOpen = inSplitWindow(0)
    demo?.bounceWindowOpen = windowOpen
    if previous.progress < 0.8 && current.progress >= 0.8 {
      bounceSerial += 1
      plantApproachAtBounce(current.hitter)
    }
    if current.hitter == 0 {
      guard current.progress >= 0.8 else { return }
      let inBounds = current.fault == nil && current.landing.x >= 0 && current.landing.x <= Self.width
        && current.landing.y >= 0 && current.landing.y < Self.net
      if let failure = run.failure { finishShotDemo(success: false, message: failure); return }
      guard inBounds else { finishShotDemo(success: false, message: "Reach yellow before contact and keep your shot inside the lines."); return }
      if run.stage == .rallyRecovery {
        // Give the player the full outgoing flight to recover and split. The
        // opponent must also physically reach the ball before sending the next feed.
        guard current.progress >= 0.9 else { return }
        guard demo?.recoveredAt != nil else {
          finishShotDemo(success: false, message: "After each return, swipe toward white and reach it before the opponent hits."); return
        }
        guard run.lesson != .recoverySplit || demo?.splitAfterRecovery == true else {
          finishShotDemo(success: false, message: "At white, tap again as your shot bounces on the far court (within 3 m)."); return
        }
        guard let window = BallContactWindow.next(flight: current, player: players[1].pos, side: 1, after: previous.progress),
          current.progress + 0.000001 >= window.entry else {
          if current.progress >= 1 { finishShotDemo(success: false, message: "Keep the rally simple: swipe toward yellow, let the return happen, then swipe toward white.") }
          return
        }
        demo?.completedExchanges += 1
        if demo!.completedExchanges == ShotDemoRun.exchangesPerAttempt {
          finishShotDemo(success: true, message: run.demonstration ? "\(ShotDemoRun.exchangesPerAttempt) exchanges. Your turn."
            : run.lesson == .recoverySplit ? "\(ShotDemoRun.exchangesPerAttempt) returns, recoveries, and split steps!"
            : "\(ShotDemoRun.exchangesPerAttempt) clean returns and recoveries!")
          return
        }
        let x = (run.attempt + demo!.completedExchanges).isMultiple(of: 2) ? 2.1 : 6.13
        launch(1, aim: Vec(x: x, y: 22.3), kind: .cross)
        applyDemoPace(trainingDuration: 3.8)
        players[0].kind = .cross
        players[0].aim = nil
        demo?.stage = .receive
        demo?.stageTime = 0
        demo?.chosenShot = nil
        demo?.chosenEpoch = nil
        demo?.recoveryTarget = nil
        demo?.recoveredAt = nil
        demo?.splitAfterRecovery = false
        demo?.scriptTap = false
        demo?.scriptShot = false
      } else if run.stage == .approachFlight {
        guard run.approached else { finishShotDemo(success: false, message: "After contact, start and finish a new forward swipe before the far bounce."); return }
        players[1].pos = current.landing
        players[1].destination = current.landing
        let cover = CourtTactics.netCoverage(side: 0, opponentContact: players[1].pos)
        launch(1, aim: Vec(x: cover.x, y: 21), kind: .cross)
        applyDemoPace(trainingDuration: 3.8)
        flight?.loft = 0.75
        attacking[0] = true
        demo?.stage = .volleyReceive
        demo?.stageTime = 0
        demo?.chosenShot = nil
        demo?.chosenEpoch = nil
        demo?.scriptTap = false
        demo?.scriptShot = false
      } else { finishShotDemo(success: true, message: run.demonstration ? "That's the motion. Your turn." : "Clean shot. Well played!") }
      return
    }
    if let window = receive,
      current.progress + 0.000001 >= window.entry {
      let explicitlyChosen = run.chosenShot == run.lesson.shot && run.chosenEpoch == shotGestureEpoch(0)
      var failure: String?
      if !explicitlyChosen && !run.lesson.isFootwork { failure = "Choose the shot with the shown gesture BEFORE the ball reaches you." }
      if run.lesson.isFootwork && (window.volley || players[0].pos.distance(to: current.contact) > Self.contactRadius + 0.000001) {
        failure = "Reach the yellow circle and let the ball bounce for this baseline rally."
      }
      if run.lesson == .overhead && !window.overhead { failure = "Get under yellow earlier and meet the lob above your head." }
      if run.stage == .volleyReceive && (!window.volley || window.overhead) { failure = "Move closer to the net and meet the reply before it bounces." }
      if run.lesson == .secondReturn && players[0].pos.y >= Self.length { failure = "Swipe toward yellow early and meet the second serve INSIDE the baseline." }
      let hittingX = players[0].pos.x
      returnBall(0, volley: window.volley, overhead: window.overhead, random: { 0.5 })
      if let outgoing = flight {
        if [.crosscourt, .shortAngle, .secondReturn].contains(run.lesson),
          (hittingX - Self.width / 2) * (outgoing.landing.x - Self.width / 2) >= 0 {
          failure = "Swipe toward the OPPOSITE side of the court."
        }
        if run.lesson == .centerLob && abs(outgoing.landing.x - Self.width / 2) > 0.5 {
          failure = "Swipe straight back, without a sideways angle, for a center lob."
        }
      }
      demo?.failure = failure
      demo?.stage = run.lesson.isFootwork ? .rallyRecovery
        : run.lesson == .approachVolley && run.stage == .receive ? .approachFlight : .finishFlight
      if run.lesson.isFootwork, let outgoing = flight {
        demo?.recoveryTarget = Self.recovery(0, outgoing.contact)
        demo?.recoveredAt = nil
        demo?.splitAfterRecovery = false
        applyDemoPace(trainingDuration: 3.8)
        players[1].destination = Self.own(1, outgoing.contact)
      }
      if demo?.stage == .approachFlight { approachAvailable[0] = true }
      demo?.stageTime = 0
      demo?.scriptTap = false
      demo?.scriptShot = false
    } else if current.progress >= 1 {
      finishShotDemo(success: false, message: run.lesson.isFootwork
        ? "Swipe toward yellow sooner and reach it before the ball arrives."
        : "Swipe toward yellow sooner, then choose your shot while your player runs.")
    }
  }

  mutating func updateDemoRecovery() {
    guard let run = demo, run.stage == .rallyRecovery, run.result == nil,
      let white = run.recoveryTarget, players[0].pos.distance(to: white) <= 0.55 else { return }
    if run.recoveredAt == nil { demo?.recoveredAt = time }
  }

  mutating func noteDemoSplit(_ side: Int) {
    guard side == 0, let run = demo, run.lesson == .recoverySplit,
      run.stage == .rallyRecovery, run.result == nil, run.recoveredAt != nil,
      let white = run.recoveryTarget, players[0].pos.distance(to: white) <= 0.55 else { return }
    demo?.splitAfterRecovery = true
  }

  mutating func performDemoScript() {
    guard let run = demo, run.result == nil else { return }
    if phase == .serving, let target = run.target {
      if run.stageTime >= 0.4 && !run.scriptTap { aimServe(at: target, side: 0); demo?.scriptTap = true }
      if run.stageTime >= 1.8 && !run.scriptShot { requestServe(0); demo?.scriptShot = true }
      return
    }
    if run.stage == .approachFlight {
      if run.stageTime >= 0.4 && !run.approached { swipeCourt(0, delta: Vec(x: 0, y: -3)) }
      return
    }
    if run.stage == .rallyRecovery {
      if run.stageTime >= 0.3 && !run.scriptTap, let white = run.recoveryTarget {
        swipeCourt(0, delta: Vec(x: white.x - players[0].pos.x, y: white.y - players[0].pos.y))
        demo?.scriptTap = true
      }
      if run.lesson == .recoverySplit, let reached = run.recoveredAt,
        time >= reached && inSplitWindow(0) && !run.splitAfterRecovery, let white = run.recoveryTarget {
        tapCourt(0, at: white)
      }
      return
    }
    guard run.stage == .receive || run.stage == .volleyReceive else { return }
    if run.stageTime >= 0.3 && !run.scriptTap, let yellow = contactGuide(0) {
      swipeCourt(0, delta: Vec(x: yellow.x - players[0].pos.x, y: yellow.y - players[0].pos.y))
      demo?.scriptTap = true
    }
    if run.lesson == .overhead || run.stage == .volleyReceive {
      if !run.scriptShot && canTapNetShot(0) {
        tapCourt(0, at: players[0].pos)
        demo?.scriptShot = true
      }
      return
    }
    // At faster volley pace the old fixed delay could demonstrate a late swing.
    let shotCueTime = phase == .serving ? 1.25 : min(1.25, (flight?.duration ?? 3.8) * 0.24)
    if !run.lesson.isFootwork && run.stageTime >= shotCueTime && !run.scriptShot {
      let opposite = players[0].pos.x < Self.width / 2 ? 1.0 : -1.0
      switch run.lesson.shot {
      case .cross: selectShotSwipe(Vec(x: 40 * opposite, y: -40), side: 0)
      case .angle: selectShotSwipe(Vec(x: 50 * opposite, y: 0), side: 0)
      case .line: selectShotSwipe(Vec(x: 0, y: -50), side: 0)
      case .lob: selectShotSwipe(Vec(x: 0, y: 50), side: 0)
      case .drop, .slice: selectTouchShot(run.lesson.shot, side: 0, epoch: shotGestureEpoch(0))
      }
      demo?.scriptShot = true
    }
  }
}
