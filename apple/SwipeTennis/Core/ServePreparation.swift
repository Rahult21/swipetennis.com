import Foundation

enum ServePlacement: String, CaseIterable {
  case wide = "Wide"
  case center = "Center / T"
  case body = "Body"
}

struct ServePreparation {
  static let tossDuration = 0.95
  static let opponentAimDuration = 3.0
  let server: Int
  var number = 1
  var target: Vec
  var destination: Vec
  var placement: ServePlacement?
  var elapsed = 0.0
  var settled = 0.0
  var tossElapsed: Double?
  var requested = false
  var pickedBlue = false
  var isTossing: Bool { tossElapsed != nil }
  var isSet: Bool { target.distance(to: destination) < 0.001 && settled >= 0.2 }
  var tossProgress: Double? { tossElapsed.map { clamp($0 / Self.tossDuration, 0, 1) } }
}

struct ServeLanding {
  static let duration = 0.42
  let server: Int
  let from: Vec
  let to: Vec
  var elapsed = 0.0
  var progress: Double { clamp(elapsed / Self.duration, 0, 1) }
}

enum ServeMotion {
  static func jumpHeight(tossProgress: Double?, landingProgress: Double?) -> Double {
    if let landingProgress { return 10 * (1 - StrokeAnimation.ease(landingProgress)) }
    return tossProgress.map { 10 * StrokeAnimation.ease(($0 - 0.76) / 0.24) } ?? 0
  }
}

/// Blue is the bounce in the diagonal service box; yellow is the same trajectory after it bounces.
enum ServeGeometry {
  static let serviceLine = 5.485

  static func contact(from: Vec, landing: Vec, server: Int, number: Int = 1) -> Vec {
    let y = number == 2 ? (server == 0 ? 1.1 : PracticeEngine.length - 1.1)
      : (server == 0 ? -0.45 : PracticeEngine.length + 0.45)
    let fraction = (y - from.y) / (landing.y - from.y)
    return Vec(x: from.x + (landing.x - from.x) * fraction, y: y)
  }

  static func bounded(_ point: Vec, from: Vec, server: Int, fromRight: Bool) -> Vec {
    let leftBox = (server == 0) == fromRight
    let center = PracticeEngine.width / 2
    let y = server == 0
      ? clamp(point.y, serviceLine + 0.4, PracticeEngine.net - 1.3)
      : clamp(point.y, PracticeEngine.net + 1.3, PracticeEngine.length - serviceLine - 0.4)
    let returnY = server == 0 ? -0.45 : PracticeEngine.length + 0.45
    let fraction = (returnY - from.y) / (y - from.y)
    // Keep even the most acute custom serve's yellow target within the playable runoff.
    let reachableMin = from.x + (-1.15 - from.x) / fraction
    let reachableMax = from.x + (PracticeEngine.width + 1.15 - from.x) / fraction
    return Vec(x: clamp(point.x,
      max(leftBox ? 0.4 : center + 0.22, reachableMin),
      min(leftBox ? center - 0.22 : PracticeEngine.width - 0.4, reachableMax)), y: y)
  }

  static func target(_ placement: ServePlacement, from: Vec, receiver: Vec,
    server: Int, fromRight: Bool) -> Vec
  {
    let leftBox = (server == 0) == fromRight
    let center = PracticeEngine.width / 2
    let y = server == 0 ? 6.2 : PracticeEngine.length - 6.2
    let x: Double
    switch placement {
    case .wide: x = leftBox ? 0.8 : PracticeEngine.width - 0.8
    case .center: x = center + (leftBox ? -0.28 : 0.28)
    case .body:
      let contactY = server == 0 ? -0.45 : PracticeEngine.length + 0.45
      x = from.x + (receiver.x - from.x) * (y - from.y) / (contactY - from.y)
    }
    return bounded(Vec(x: x, y: y), from: from, server: server, fromRight: fromRight)
  }
}

extension PracticePhase {
  var isPlaying: Bool { self == .serving || self == .live }
}

extension PracticeEngine {
  var humanServing: Bool {
    phase == .serving && (scoring.server == 0 || settings.local)
  }

  func canAimServe(_ side: Int) -> Bool {
    humanServing && servePreparation?.server == side && servePreparation?.isTossing == false
  }

  func canBeginServe(_ side: Int) -> Bool {
    canAimServe(side) && servePreparation?.isSet == true
      && (servePreparation?.elapsed ?? 0) >= 0.65
  }

  mutating func chooseServe(_ placement: ServePlacement, side: Int) {
    guard canAimServe(side) else { return }
    let target = ServeGeometry.target(placement, from: players[side].pos,
      receiver: players[1 - side].pos, server: side, fromRight: scoring.serveFromRight)
    aimServe(at: target, side: side)
    servePreparation?.placement = placement
  }

  mutating func aimServe(at point: Vec, side: Int) {
    guard canAimServe(side), point.x.isFinite, point.y.isFinite else { return }
    guard queuedPower != .ace else { return }
    if side == 0 { servePreparation?.pickedBlue = true }
    let target = ServeGeometry.bounded(point, from: players[side].pos,
      server: side, fromRight: scoring.serveFromRight)
    if target.distance(to: servePreparation!.destination) > 0.001 {
      if side == 0 { demo?.serveAdjusted = true }
      servePreparation?.requested = false
      servePreparation?.settled = 0
      servePreparation?.destination = target
      servePreparation?.placement = nil
    }
  }

  mutating func nudgeServe(_ delta: Vec, side: Int) {
    guard let servePreparation else { return }
    let direction = side == 0 ? 1.0 : -1.0
    aimServe(at: Vec(x: servePreparation.destination.x + delta.x * direction * 0.025,
      y: servePreparation.destination.y + delta.y * direction * 0.025), side: side)
  }

  mutating func beginServe(_ side: Int) {
    guard canBeginServe(side) else { return }
    servePreparation?.tossElapsed = 0
  }

  /// A tap is not lost while the blue target finishes its short settling movement.
  mutating func requestServe(_ side: Int) {
    guard canAimServe(side) else { return }
    servePreparation?.requested = true
    if canBeginServe(side) { beginServe(side) }
  }

  func serveReceiveTarget(_ side: Int) -> Vec? {
    guard phase == .serving, let servePreparation, servePreparation.server != side else { return nil }
    return ServeGeometry.contact(from: players[servePreparation.server].pos,
      landing: servePreparation.target, server: servePreparation.server, number: servePreparation.number)
  }

  mutating func stepServe(_ dt: Double, random: () -> Double = { Double.random(in: 0..<1) }) {
    guard var serve = servePreparation else { return }
    serve.elapsed += dt
    if let toss = serve.tossElapsed {
      serve.tossElapsed = toss + dt * (queuedPower == .ace ? 1.25 : 1)
    } else {
      let distance = serve.target.distance(to: serve.destination)
      let fraction = distance > 0 ? min(1, 3.2 * dt / distance) : 1
      serve.target.x += (serve.destination.x - serve.target.x) * fraction
      serve.target.y += (serve.destination.y - serve.target.y) * fraction
      serve.settled = serve.target.distance(to: serve.destination) < 0.001 ? serve.settled + dt : 0
      if !humanServing && serve.elapsed >= ServePreparation.opponentAimDuration && serve.settled >= 0.7 {
        serve.tossElapsed = 0
      } else if humanServing && serve.requested && serve.isSet && serve.elapsed >= 0.65 {
        serve.tossElapsed = 0
      }
    }
    servePreparation = serve
    let receiver = 1 - serve.server
    if queuedPower == .ace {
      players[receiver].destination = players[receiver].pos
    } else if receiver == 1 && !settings.local, let target = serveReceiveTarget(receiver) {
      players[receiver].destination = Self.own(receiver, target)
    }
    updateFootwork(dt)
    if (serve.tossElapsed ?? 0) + 0.000001 >= ServePreparation.tossDuration {
      phase = .live
      servePreparation = nil
      // A first-serve fault gives a real second-serve opportunity without awarding a point.
      // The slower second serve is kept in for the on-the-rise training pattern.
      let miss = queuedPower != .ace && serve.number == 1 && random() < 0.16
      let fault = miss ? ["net", "wide", "long"][Int(clamp(random(), 0, 0.999999) * 3)] : nil
      launch(serve.server, aim: serve.target, kind: .cross, fault: fault, serve: true, serveNumber: serve.number)
      if queuedPower == .ace { commitPowerFlight(.ace, random: random) }
      feedback = Coaching(title: "Serve in play.", reason: "Blue marked the bounce. Yellow marks the return.",
        tip: "Reach yellow after the bounce, then follow your shot or recover.")
    }
  }

  mutating func prepareSecondServe() {
    let server = scoring.server
    let x = server == 0 ? (scoring.serveFromRight ? 4.8 : 3.43) : (scoring.serveFromRight ? 3.43 : 4.8)
    players[server].pos = Vec(x: x, y: server == 0 ? 24.6 : -0.8)
    players[server].destination = players[server].pos
    players[server].velocity = .zero
    players[server].aim = nil
    let target = ServeGeometry.target(.body, from: players[server].pos,
      receiver: players[1 - server].pos, server: server, fromRight: scoring.serveFromRight)
    servePreparation = ServePreparation(server: server, number: 2, target: target, destination: target, placement: .body)
    phase = .serving
    flight = nil
    serveLanding = nil
    pointResolution = nil
    ball = players[server].pos
    feedback = Coaching(title: "Second serve", reason: "The first serve was a fault. No point was awarded.",
      tip: "Receiver: tap yellow inside the baseline and meet the ball on the rise.")
  }
}
