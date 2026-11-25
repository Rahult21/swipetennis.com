import Foundation

struct PowerInventory: Codable, Equatable {
  var held: CourtPower?
  var aceCelebrations: [Bool] = []
}

enum CourtPower: String, Codable, CaseIterable {
  case overhead = "Overhead Smash", rally = "Rally Smash", ace = "On Demand Ace"
  var symbol: String {
    switch self { case .overhead: return "bolt.fill"; case .rally: return "arrow.up.right"; case .ace: return "scope" }
  }
  var prompt: String {
    switch self {
    case .overhead: return "Reach the net"
    case .rally: return "Tap green"
    case .ace: return "Aim blue on serve"
    }
  }
  var hint: String {
    switch self {
    case .overhead: return "Come within 3 m of the net, then tap."
    case .rally: return "Tap the green contact circle, then tap the power."
    case .ace: return "On your serve, select blue, then tap the power."
    }
  }
  var contactGain: Double { self == .overhead ? 2 : self == .rally ? 1.5 : 1 }
}

/// A committed assisted stroke tracks a position on the current ball flight.
struct AssistedContact {
  let power: CourtPower
  let from: Vec
  let feet: Vec
  let impactProgress: Double
  let startProgress: Double
  let travelTime: Double
  var elapsed = 0.0
}

extension PracticeEngine {
  var canUsePower: Bool {
    guard let power = inventory.held, demo == nil, !settings.local, queuedPower == nil else { return false }
    switch power {
    case .ace: return canAimServe(0) && servePreparation?.pickedBlue == true
    case .rally: return phase == .live && canChooseShot(0) && dropGestureEpoch[0] == shotGestureEpoch(0)
    case .overhead:
      guard phase == .live, let flight, flight.fault == nil,
        players[0].pos.y <= Self.net + 3 else { return false }
      return true
    }
  }

  mutating func usePower() {
    guard canUsePower, let power = inventory.held else { return }
    queuedPower = power
    if power == .overhead && flight?.hitter == 0 {
      flight?.approachReply = .lob
      flight?.opponentReplyPrepared = true
      flight?.opponentError = nil
      flight?.dropReachable = true
      flight?.missedChaseTarget = nil
      // Give the receiver enough time to lift the feed for the overhead.
      let chase = CourtTactics.travelTime(distance: players[1].pos.distance(to: intercept(1)),
        speed: settings.style.speed * settings.difficulty.speed)
      if var outgoing = flight {
        let remaining = max(0.01, 1 - outgoing.progress)
        let fraction = outgoing.progress
        outgoing.duration = max(outgoing.duration, (chase + 0.2) / remaining)
        outgoing.elapsed = fraction * outgoing.duration
        flight = outgoing
      }
      reactAt = time
    }
    if power == .ace { requestServe(0) }
    else if flight?.hitter == 1 { alignForPower(power) }
  }

  mutating func alignForPower(_ power: CourtPower) {
    guard let flight, flight.hitter == 1, flight.fault == nil else { return }
    let impact: Double
    var feet: Vec
    if power == .overhead && flight.progress < 0.79 && !flight.serve {
      let y = min(players[0].pos.y + 0.65, Self.net + 3.2)
      let t = clamp((y - flight.from.y) / max(0.1, flight.landing.y - flight.from.y), 0, 0.98)
      impact = min(0.799, max(flight.progress + 0.001, 0.8 * t))
      feet = Vec(x: flight.from.x + (flight.landing.x - flight.from.x) * impact / 0.8,
        y: flight.from.y + (flight.landing.y - flight.from.y) * impact / 0.8)
    } else {
      impact = max(0.94, flight.progress)
      var sample = flight
      sample.elapsed = impact * flight.duration
      feet = sample.position
    }
    // Run around the contact point to strike from the forehand side.
    let openRight = players[1].pos.x < Self.width / 2
    let runAround = openRight ? 0.52 : -0.52
    feet.x -= power == .rally ? runAround : 0.18
    feet = Self.own(0, feet)
    let timeToBall = (impact - flight.progress) * flight.duration
    let travel = max(0.15, players[0].pos.distance(to: feet) / 10, timeToBall)
    assist = AssistedContact(power: power, from: players[0].pos, feet: feet,
      impactProgress: impact, startProgress: flight.progress, travelTime: travel)
    players[0].destination = feet
  }

  mutating func stepAssistedContact(_ dt: Double, random: () -> Double) {
    guard var alignment = assist, var incoming = flight else { return }
    alignment.elapsed += dt
    let t = min(1, alignment.elapsed / alignment.travelTime)
    let eased = StrokeAnimation.ease(t)
    let previous = players[0].pos
    players[0].pos = Vec(x: alignment.from.x + (alignment.feet.x - alignment.from.x) * eased,
      y: alignment.from.y + (alignment.feet.y - alignment.from.y) * eased)
    players[0].velocity = Vec(x: (players[0].pos.x - previous.x) / max(0.00001, dt),
      y: (players[0].pos.y - previous.y) / max(0.00001, dt))
    let progress = alignment.startProgress + (alignment.impactProgress - alignment.startProgress) * t
    if incoming.progress < 0.8 && progress >= 0.8 { bounceSerial += 1 }
    incoming.elapsed = incoming.duration * progress
    flight = incoming
    ball = incoming.position
    assist = alignment
    guard t >= 1 else { return }
    players[0].velocity = .zero
    let overhead = alignment.power == .overhead
    let aim = overhead ? Vec(x: Self.width / 2, y: Self.net / 2)
      : Vec(x: players[1].pos.x < Self.width / 2 ? Self.width - 0.45 : 0.45, y: 0.75)
    assessCoachReturn(incoming: incoming, aim: aim, kind: .cross, clean: true, explicit: true)
    attempts[0] += 1
    if overhead { tactics[0].overheads += 1 }
    launch(0, aim: aim, kind: .cross, stroke: overhead ? .overhead : .groundstroke)
    commitPowerFlight(alignment.power, random: random)
  }

  mutating func commitPowerFlight(_ power: CourtPower, random: () -> Double) {
    guard var shot = flight else { return }
    shot.power = power
    shot.duration /= 1.5
    if power == .overhead {
      // The rebound clears the receiver before continuing behind the baseline.
      let forward = max(1, shot.landing.y - players[1].pos.y)
      shot.contact = Vec(x: clamp(shot.landing.x + (players[1].pos.x - shot.landing.x) *
        (shot.landing.y + 3) / forward, -1.5, Self.width + 1.5), y: -3)
    } else if power == .rally {
      shot.contact = Vec(x: shot.landing.x + (shot.landing.x - shot.from.x) * 0.12, y: -2)
    } else {
      if inventory.aceCelebrations.isEmpty {
        inventory.aceCelebrations = Array(repeating: false, count: 4)
        inventory.aceCelebrations[Int(clamp(random(), 0, 0.999999) * 4)] = true
      }
      shot.acknowledge = inventory.aceCelebrations.removeFirst()
    }
    flight = shot
    players[1].destination = players[1].pos
    inventory.held = nil
    queuedPower = nil
    assist = nil
  }

  mutating func awardPowerIfDue(random: () -> Double) {
    guard demo == nil, !settings.local, inventory.held == nil, momentum.winsInRow > 0,
      momentum.winsInRow.isMultiple(of: 2) else { return }
    let choices = CourtPower.allCases
    inventory.held = choices[Int(clamp(random(), 0, 0.999999) * Double(choices.count))]
    powerEarnedThisPoint = inventory.held
  }
}
