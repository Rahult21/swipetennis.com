import Foundation

struct PowerInventory: Codable, Equatable {
  var held: CourtPower?
  var armed: Bool?
  var aceCelebrations: [Bool] = []
}

enum CourtPower: String, Codable, CaseIterable {
  case overhead = "Overhead Smash", rally = "Rally Smash", ace = "On Demand Ace"
  var symbol: String {
    switch self { case .overhead: return "bolt.fill"; case .rally: return "arrow.up.right"; case .ace: return "scope" }
  }
  var hint: String {
    switch self {
    case .overhead: return "Tap once to set up and finish a jumping smash."
    case .rally: return "Tap once to play a power forehand or backhand on the next return."
    case .ace: return "Arm the ace, then swipe toward blue during your toss."
    }
  }
  var contactGain: Double { self == .overhead ? 2 : self == .rally ? 1.5 : 1 }
}

/// A committed assisted stroke tracks a position on the current ball flight.
struct AssistedContact: Codable {
  let power: CourtPower
  let from: Vec
  let feet: Vec
  let impactProgress: Double
  let startProgress: Double
  let travelTime: Double
  var elapsed = 0.0
  var backhand: Bool?
  var setup: Bool?
}

extension PracticeEngine {
  var canUsePower: Bool {
    inventory.held != nil && demo == nil && !settings.local && !settings.tournament && phase.isPlaying
      && inventory.armed != true && queuedPower == nil
  }

  mutating func usePower() {
    guard canUsePower else { return }
    inventory.armed = true
    startArmedPower()
  }

  mutating func startArmedPower() {
    guard inventory.armed == true, let power = inventory.held, queuedPower == nil, demo == nil, !settings.local, !settings.tournament else { return }
    if power == .ace {
      guard phase == .serving, servePreparation?.server == 0 else { return }
      queuedPower = power
      requestServe(0)
      return
    }
    guard phase == .live, let f = flight, f.fault == nil, f.power == nil else { return }
    if f.hitter == 0 && power == .rally { return }
    queuedPower = power
    players[0].netEffort = nil
    if f.hitter == 0 { preparePowerLob() } else { alignForPower(power) }
  }

  private mutating func preparePowerLob() {
    flight?.approachReply = .lob
    flight?.opponentReplyPrepared = true
    flight?.opponentError = nil
    flight?.dropReachable = true
    flight?.missedChaseTarget = nil
    // Give the receiver enough time to lift the feed for the overhead.
    let chase = CourtTactics.travelTime(distance: players[1].pos.distance(to: intercept(1)),
      speed: settings.style.speed * settings.botSpeed)
    if var outgoing = flight {
      let remaining = max(0.000001, 1 - outgoing.progress)
      let fraction = outgoing.progress
      outgoing.duration = max(outgoing.duration, (chase + 0.2) / remaining)
      outgoing.elapsed = outgoing.time(at:fraction)
      flight = outgoing
    }
    reactAt = time
    players[0].destination = CourtTactics.netCoverage(side: 0, opponentContact: players[1].pos)
  }

  mutating func alignForPower(_ power: CourtPower) {
    guard let flight, flight.hitter == 1, flight.fault == nil else { return }
    // A low pass or a serve needs a setup return before there is a real lob to smash.
    var smashAt: Double?
    if power == .overhead && !flight.serve && flight.progress < 0.79 {
      for i in 0...80 {
        let t = 0.79 - Double(i) * 0.008
        guard t >= flight.progress else { break }
        let ball = flight.worldBall(at: t)
        if (2.50...2.94).contains(ball.y), ball.z > Float(Self.net + 0.5),
          ball.z < Float(Self.length - ServeGeometry.serviceLine) {
          smashAt = t
          break
        }
      }
    }
    let setup = power == .overhead && smashAt == nil
    let impact = smashAt ?? max(0.94, flight.progress)
    let ball = flight.worldBall(at: impact)
    let backhand = power == .rally && Double(ball.x) < players[0].pos.x - 0.85
    let offset = smashAt != nil ? 0.31 : backhand ? -0.62 : 0.62
    let feet = Self.own(0, Vec(x: Double(ball.x) - offset, y: Double(ball.z) + 0.26))
    let timeToBall = flight.time(at:impact)-flight.elapsed
    let travel = max(0.30, players[0].pos.distance(to: feet) / 8, timeToBall)
    assist = AssistedContact(power: power, from: players[0].pos, feet: feet,
      impactProgress: impact, startProgress: flight.progress, travelTime: travel, backhand: backhand, setup: setup)
    players[0].destination = feet
  }

  mutating func stepAssistedContact(_ dt: Double, random: () -> Double) {
    guard var alignment = assist, var incoming = flight else { return }
    alignment.elapsed += dt
    let t = min(1, alignment.elapsed / alignment.travelTime)
    let eased = StrokeAnimation.ease(t)
    let previous = players[0].pos
    // Loop around the ball on the forehand, then step through the inside-out drive.
    let loop = alignment.power == .rally && alignment.backhand != true
      ? min(0.55, alignment.travelTime * 0.75) * pow(sin(.pi * t), 2) : 0
    players[0].pos = Self.own(0, Vec(x: alignment.from.x + (alignment.feet.x - alignment.from.x) * eased - loop,
      y: alignment.from.y + (alignment.feet.y - alignment.from.y) * eased + 0.65 * loop))
    players[0].velocity = Vec(x: (players[0].pos.x - previous.x) / max(0.00001, dt),
      y: (players[0].pos.y - previous.y) / max(0.00001, dt))
    let progress = alignment.startProgress + (alignment.impactProgress - alignment.startProgress) * t
    if incoming.progress < 0.8 && progress >= 0.8 { bounceSerial += 1 }
    incoming.elapsed = incoming.time(at:progress)
    flight = incoming
    ball = incoming.position
    assist = alignment
    guard t >= 1 else { return }
    players[0].velocity = .zero
    if alignment.setup == true {
      launch(0, aim: Vec(x: Self.width/2, y: 2.5), kind: .cross)
      assist = nil
      preparePowerLob()
      return
    }
    let overhead = alignment.power == .overhead
    let aim = overhead ? Vec(x: Self.width / 2, y: Self.net / 2)
      : Vec(x: alignment.backhand == true && players[1].pos.x > Self.width / 2 ? 0.45 : Self.width - 0.45, y: 0.75)
    assessCoachReturn(incoming: incoming, aim: aim, kind: .cross, clean: true, explicit: true)
    players[0].lastReturn = ReturnDecision(shot: .cross, redirected: false, shorterSide: false,
      split: players[0].splitForReturn == contactSerial, baseAccuracy: 1)
    attempts[0] += 1
    if overhead { tactics[0].overheads += 1 }
    launch(0, aim: aim, kind: .cross, stroke: overhead ? .overhead : .groundstroke)
    flight?.powerBackhand = alignment.backhand
    commitPowerFlight(alignment.power, random: random)
  }

  mutating func commitPowerFlight(_ power: CourtPower, random: () -> Double) {
    guard var shot = flight else { return }
    shot.power = power
    if power != .ace { shot.duration /= 1.5 }
    if power == .overhead {
      // The rebound clears the receiver before continuing behind the baseline.
      shot.contact = shot.landing.projected(from:shot.launchPosition,toDepth:-3)
    } else if power == .rally {
      shot.contact = shot.landing.projected(from:shot.launchPosition,toDepth:-2)
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
    inventory.armed = nil
    queuedPower = nil
    assist = nil
  }

  mutating func awardPowerIfDue(random: () -> Double) {
    guard demo == nil, !settings.local, !settings.tournament, inventory.held == nil, momentum.winsInRow > 0,
      momentum.winsInRow.isMultiple(of: 2) else { return }
    let choices = CourtPower.allCases
    inventory.held = choices[Int(clamp(random(), 0, 0.999999) * Double(choices.count))]
    powerEarnedThisPoint = inventory.held
  }
}
