import Foundation

enum ServePlacement: String, Codable, CaseIterable {
  case wide = "Wide"
  case center = "Center / T"
  case body = "Body"
}

enum ServeLevel: Int, CaseIterable, Codable {
  case low, medium, high
  var label: String { ["Low", "Medium", "High"][rawValue] }
}

struct ServeProfile: Codable, Equatable {
  var speed: ServeLevel
  var spin: ServeLevel

  static func standard(_ number: Int) -> Self {
    number == 1 ? Self(speed: .high, spin: .low) : Self(speed: .low, spin: .high)
  }

  var launchSpeedKPH: Double { 75 + 15 * Double(speed.rawValue) }
  var kick: Double { 1 + 0.15 * Double(spin.rawValue) }
}

enum ServeDepth: String, Codable {
  case short, moderate, deep

  init(target: Vec) {
    let metres = abs(target.y - PracticeEngine.net)
    self = metres < 2.8 ? .short : metres >= 5 ? .deep : .moderate
  }

  func faultChance(profile: ServeProfile) -> Double {
    if self == .deep && profile.speed == .high { return 2.0 / 3 }
    let speed = Double(profile.speed.rawValue) / 2
    let flatness = 1 - Double(profile.spin.rawValue) / 2
    let depthRisk = self == .deep ? 0.22 : self == .short ? 0.07 : 0
    return 0.10 + speed * 0.22 + flatness * 0.10 + depthRisk
  }
}

struct ServePreparation: Codable {
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
  // Optional fields allow a serve saved before meters existed to resume with its defaults.
  var tuningDeadline: Double?
  var tossID: UUID?
  var swingCommitted: Bool?
  var swipeStrength: Double?
  var catching: Bool?
  var customProfile: ServeProfile?
  var profile: ServeProfile { customProfile ?? .standard(number) }
  var canTune: Bool { !isTossing }
  var acceptsSwing: Bool { isTossing && catching != true && swingCommitted != true }
  var isTossing: Bool { tossElapsed != nil }
  var tossProgress: Double? { tossElapsed.map { clamp($0 / Self.tossDuration, 0, 1) } }
}

struct ServeLanding: Codable {
  static let duration = 0.42
  let server: Int
  let from: Vec
  let to: Vec
  var elapsed = 0.0
  var progress: Double { clamp(elapsed / Self.duration, 0, 1) }
}

enum ServeMotion {
  static func jumpHeight(tossProgress: Double?, landingProgress: Double?) -> Double {
    // Push against the court through knee extension. Leave the ground late,
    // reach the apex at contact, then land before the front knee absorbs the load.
    if let landingProgress {
      let descent = clamp(landingProgress / 0.82, 0, 1)
      return 10 * (1 - descent * descent)
    }
    guard let tossProgress else { return 0 }
    let ascent = clamp((tossProgress - 0.86) / 0.14, 0, 1)
    return 10 * ascent * (2 - ascent)
  }
}

/// Blue is the bounce in the diagonal service box; yellow is the same trajectory after it bounces.
enum ServeGeometry {
  static let serviceLine = 5.485

  static func receivingBaseline(server: Int) -> Double {
    server == 0 ? 0 : PracticeEngine.length
  }

  static func returnDepth(server: Int, number: Int) -> Double {
    receivingBaseline(server: server) + (number == 2 ? (server == 0 ? 1 : -1) : 0)
  }

  static func returnMark(through landing: Vec, from origin: Vec, server: Int, number: Int) -> Vec {
    landing.projected(from: origin, toDepth: returnDepth(server: server, number: number))
  }

  static func bounded(_ point: Vec, from: Vec, server: Int, fromRight: Bool) -> Vec {
    let leftBox = (server == 0) == fromRight
    let center = PracticeEngine.width / 2
    let y = server == 0
      ? clamp(point.y, serviceLine + 0.4, PracticeEngine.net - 1.3)
      : clamp(point.y, PracticeEngine.net + 1.3, PracticeEngine.length - serviceLine - 0.4)
    let returnY = receivingBaseline(server: server)
    let origin = serviceImpact(at: from, side: server, explosive: false).courtPosition
    let fraction = (returnY - origin.y) / (y - origin.y)
    // Keep even the most acute custom serve's yellow target within the playable runoff.
    let reachableMin = origin.x + (-1.15 - origin.x) / fraction
    let reachableMax = origin.x + (PracticeEngine.width + 1.15 - origin.x) / fraction
    return Vec(x: clamp(point.x,
      max(leftBox ? 0.4 : center + 0.22, reachableMin),
      min(leftBox ? center - 0.22 : PracticeEngine.width - 0.4, reachableMax)), y: y)
  }

  /// The middle swipe length hits blue. Shorter and longer swipes slide the bounce
  /// along the same bearing, stopping inside the diagonal service box.
  static func swipeLanding(through blue: Vec, from origin: Vec, server: Int, length: Double) -> Vec {
    let strength = 2 * ShotSwipe.strength(length) - 1
    guard strength != 0 else { return blue }
    let direction = server == 0 ? -1.0 : 1.0
    let edgeDepth = strength < 0 ? 1.0 : PracticeEngine.net - serviceLine - 0.05
    let edge = blue.projected(from: origin, toDepth: PracticeEngine.net + direction * edgeDepth)
    let center = PracticeEngine.width / 2
    let bounds = blue.x < center ? 0.05...(center - 0.05) : (center + 0.05)...(PracticeEngine.width - 0.05)
    let dx = edge.x - blue.x
    let limit = dx == 0 ? 1 : min(1, ((dx > 0 ? bounds.upperBound : bounds.lowerBound) - blue.x) / dx)
    return Vec(x: blue.x + dx * limit * abs(strength), y: blue.y + (edge.y - blue.y) * limit * abs(strength))
  }

  static func target(_ placement: ServePlacement, from: Vec, receiver: Vec,
    server: Int, fromRight: Bool, number: Int = 1) -> Vec
  {
    let leftBox = (server == 0) == fromRight
    let center = PracticeEngine.width / 2
    let y = server == 0 ? 6.2 : PracticeEngine.length - 6.2
    let x: Double
    switch placement {
    case .wide: x = leftBox ? 0.8 : PracticeEngine.width - 0.8
    case .center: x = center + (leftBox ? -0.28 : 0.28)
    case .body:
      let contactY = returnDepth(server: server, number: number)
      let origin = serviceImpact(at: from, side: server, explosive: false).courtPosition
      x = Vec(x:receiver.x,y:contactY).projected(from:origin,toDepth:y).x
    }
    return bounded(Vec(x: x, y: y), from: from, server: server, fromRight: fromRight)
  }
}

extension PracticePhase {
  var isPlaying: Bool { self == .serving || self == .live }
}

extension PracticeEngine {
  var displayedServeGauges: ServePreparation? {
    guard phase == .serving, demo == nil, let serve = servePreparation,
      !serve.requested, !serve.isTossing else { return nil }
    return serve
  }

  var humanServing: Bool {
    phase == .serving && (scoring.server == 0 || settings.local)
  }

  func canAimServe(_ side: Int) -> Bool {
    humanServing && servePreparation?.server == side && servePreparation?.isTossing == false
  }

  mutating func chooseServe(_ placement: ServePlacement, side: Int) {
    guard canAimServe(side) else { return }
    let target = ServeGeometry.target(placement, from: players[side].pos,
      receiver: players[1 - side].pos, server: side, fromRight: scoring.serveFromRight, number: servePreparation?.number ?? 1)
    aimServe(at: target, side: side)
    servePreparation?.placement = placement
  }

  mutating func aimServe(at point: Vec, side: Int, finished: Bool = true) {
    guard canAimServe(side), point.x.isFinite, point.y.isFinite else { return }
    guard queuedPower != .ace, let serve = servePreparation else { return }
    let target = ServeGeometry.bounded(point, from: players[side].pos,
      server: side, fromRight: scoring.serveFromRight)
    let moved = target.distance(to: serve.destination) > 0.001
    if moved || !serve.pickedBlue || serve.tuningDeadline == nil {
      servePreparation?.tuningDeadline = serve.elapsed + 0.5
    }
    servePreparation?.pickedBlue = true
    if moved {
      if side == 0 { demo?.serveAdjusted = true }
      servePreparation?.requested = false
      servePreparation?.settled = 0
      servePreparation?.destination = target
      servePreparation?.placement = nil
    }
  }

  mutating func adjustServe(speed: ServeLevel? = nil, spin: ServeLevel? = nil, side: Int) {
    guard canAimServe(side), queuedPower == nil, let serve = servePreparation, serve.canTune else { return }
    let profile = ServeProfile(speed: speed ?? serve.profile.speed, spin: spin ?? serve.profile.spin)
    guard profile != serve.profile else { return }
    servePreparation?.customProfile = profile
    if serve.pickedBlue { servePreparation?.tuningDeadline = serve.elapsed + 0.5 }
  }

  mutating func nudgeServe(_ delta: Vec, side: Int) {
    guard let servePreparation else { return }
    let direction = side == 0 ? 1.0 : -1.0
    aimServe(at: Vec(x: servePreparation.destination.x + delta.x * direction * 0.025,
      y: servePreparation.destination.y + delta.y * direction * 0.025), side: side)
  }

  /// Confirm the current blue placement without authorizing racket contact.
  mutating func requestServe(_ side: Int) {
    guard canAimServe(side), let serve = servePreparation else { return }
    servePreparation?.pickedBlue = true
    if serve.tuningDeadline == nil { servePreparation?.tuningDeadline = serve.elapsed + 0.5 }
  }

  /// Screen points in a frame whose positive y-axis points along the projected blue line.
  mutating func swingServe(_ swipe: Vec, side: Int, tossID: UUID?) {
    guard humanServing, let serve = servePreparation, serve.server == side, serve.acceptsSwing,
          let tossID, tossID == serve.tossID, swipe.length.isFinite, swipe.length >= 16,
          swipe.y >= swipe.length * 0.8660254 else { return }
    let origin = serviceImpact(at: players[side].pos, side: side, explosive: queuedPower == .ace)
    let bounce = ServeGeometry.swipeLanding(through: serve.target, from: origin.courtPosition,
      server: side, length: swipe.length)
    servePreparation?.target = bounce
    servePreparation?.destination = bounce
    servePreparation?.swipeStrength = ShotSwipe.strength(swipe.length)
    servePreparation?.swingCommitted = true
  }

  func serveDirection(viewer: Int?) -> ShotDirection? {
    if phase == .serving, let serve = servePreparation {
      guard serve.swingCommitted == true, let strength = serve.swipeStrength,
        !(settings.tournament && settings.local) || viewer == serve.server else { return nil }
      let origin = serviceImpact(at: players[serve.server].pos, side: serve.server, explosive: queuedPower == .ace)
      return ShotDirection(serveTarget: serve.target, origin: origin.courtPosition,
        strength: strength, side: serve.server, serial: contactSerial, time: time)
    }
    guard phase == .live, let flight, flight.serve, let strength = flight.serveSwipeStrength else { return nil }
    return ShotDirection(serveTarget: flight.serveAim ?? flight.landing, origin: flight.launchPosition,
      strength: strength, side: flight.hitter, serial: contactSerial - 1,
      time: flight.serveReleaseTime ?? time - flight.elapsed)
  }

  func serveReceiveTarget(_ side: Int) -> Vec? {
    // Human rivals get a prediction only once the racket has contacted the ball.
    // The live BallFlight then provides the same contact guide for both ends.
    guard !(settings.tournament && settings.local) else { return nil }
    guard phase == .serving, let servePreparation, servePreparation.server != side else { return nil }
    let server = servePreparation.server
    let origin = serviceImpact(at: players[server].pos, side: server, explosive: false).courtPosition
    return ServeGeometry.returnMark(through: servePreparation.target, from: origin, server: server, number: servePreparation.number)
  }

  mutating func stepServe(_ dt: Double, random: () -> Double = { Double.random(in: 0..<1) }) {
    guard var serve = servePreparation else { return }
    serve.elapsed += dt
    if let toss = serve.tossElapsed {
      if humanServing && serve.tossID == nil { serve.tossID = UUID() }
      let next = toss + dt * (queuedPower == .ace ? 1.25 : 1)
      if serve.catching == true {
        serve.tossElapsed = max(0, toss - dt)
        if serve.tossElapsed == 0 {
          serve.tossElapsed = nil
          serve.catching = nil
          serve.tossID = nil
          serve.requested = false
          serve.tuningDeadline = serve.elapsed + 0.5
        }
      } else if humanServing && serve.swingCommitted != true && next >= ServePreparation.tossDuration * 0.82 {
        // Catch an unstruck toss before the racket accelerates. Play the
        // release back into the hand, then allow another toss at the same mark.
        serve.tossElapsed = ServePreparation.tossDuration * 0.82
        serve.catching = true
      } else { serve.tossElapsed = next }
    } else {
      let distance = serve.target.distance(to: serve.destination)
      let travel = distance > 0 ? 3.2 * dt / distance : 1
      let untilToss = humanServing ? serve.tuningDeadline.map { max(dt, $0 - serve.elapsed + dt) } : nil
      let fraction = min(1, max(travel, untilToss.map { dt / max(0.000001, $0) } ?? 0))
      serve.target.x += (serve.destination.x - serve.target.x) * fraction
      serve.target.y += (serve.destination.y - serve.target.y) * fraction
      serve.settled = serve.target.distance(to: serve.destination) < 0.001 ? serve.settled + dt : 0
      if !humanServing && serve.elapsed >= ServePreparation.opponentAimDuration && serve.settled >= 0.7 {
        serve.tossElapsed = 0
      } else if humanServing && (serve.pickedBlue || serve.requested),
                serve.elapsed + 0.000001 >= (serve.tuningDeadline ?? 0.5) {
        serve.target = serve.destination
        serve.tossID = UUID()
        serve.requested = true
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
    if (serve.tossElapsed ?? 0) + 0.000001 >= ServePreparation.tossDuration,
       !humanServing || serve.swingCommitted == true {
      phase = .live
      servePreparation = nil
      let depth = ServeDepth(target: serve.target)
      let chance = depth.faultChance(profile: serve.profile)
      let miss = demo == nil && queuedPower != .ace && random() < chance
      let odds = abs(chance - 2.0/3) < 0.000001 ? "2 in 3 fault risk"
        : abs(chance - 0.10) < 0.000001 ? "9 in 10 land in" : "\(Int((100 * (1 - chance)).rounded()))% land in"
      serveExplanation = queuedPower == .ace ? "The on-demand ace guaranteed this serve."
        : "\(name(serve.server)) served \(depth.rawValue) with \(serve.profile.speed.label.lowercased()) speed and \(serve.profile.spin.label.lowercased()) spin (\(odds))."
      let fault = miss ? ["net", "wide", "long"][Int(clamp(random(), 0, 0.999999) * 3)] : nil
      launch(serve.server, aim: serve.target, kind: .cross, fault: fault, serve: true,
        serveNumber: serve.number, serveProfile: serve.profile)
      if queuedPower == .ace { commitPowerFlight(.ace, random: random) }
      flight?.serveAim = serve.target
      flight?.serveSwipeStrength = serve.swipeStrength
      flight?.serveReleaseTime = time
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
    let receiver = 1 - server
    players[receiver].swipeDepth = nil
    players[receiver].swingStrength = nil
    players[receiver].aim = nil
    let target = ServeGeometry.target(.body, from: players[server].pos,
      receiver: players[1 - server].pos, server: server, fromRight: scoring.serveFromRight, number: 2)
    servePreparation = ServePreparation(server: server, number: 2, target: target, destination: target, placement: .body)
    phase = .serving
    flight = nil
    serveLanding = nil
    pointResolution = nil
    ball = players[server].pos
    feedback = Coaching(title: "Second serve", reason: "The first serve was a fault. No point was awarded.",
      tip: "Take two steps in to yellow and meet the second serve on the rise.")
  }
}
