import Foundation

enum NetStroke: String, Codable {
  case volley, overhead, dive, jump
  var overhead: Bool { self == .overhead || self == .jump }
  var extended: Bool { self == .dive || self == .jump }
  var recovery: Double { self == .dive ? 0.94 : 0.32 }
}

struct NetEffort: Codable {
  let stroke: NetStroke
  let serial: Int
  let startTime, impactTime, progress: Double
  let from, landing: Vec
  let target: CourtPoint3D
  let reachable: Bool
  var afterBounce: Bool?

  func position(at time: Double) -> Vec {
    let duration = impactTime - startTime + 0.10
    let u = StrokeAnimation.ease((time - startTime) / max(0.10, duration))
    return Vec(x: from.x + (landing.x - from.x) * u, y: from.y + (landing.y - from.y) * u)
  }
}

extension BallFlight {
  var isDefensiveLob: Bool { contactQuality == .diving && kind == .lob }
}

/// One contact clock shared by the simulation, swing preparation and drawn ball.
struct BallContactWindow {
  let entry: Double
  var exit: Double
  let volley: Bool
  var overhead = false
  var netStroke: NetStroke?
  var reachable = true

  static func inServiceBox(_ p: Vec, side: Int) -> Bool {
    let depth = (p.y - PracticeEngine.net) * (side == 0 ? 1.0 : -1.0)
    return (0...PracticeEngine.width).contains(p.x) && (0...(PracticeEngine.net - ServeGeometry.serviceLine)).contains(depth)
  }

  /// Search only the nearby section of the airborne trajectory, in metres. Prefer
  /// a shot from planted feet if the same ball will enter comfortable reach.
  static func netOpportunity(flight: BallFlight, player: Vec, side: Int, after: Double) -> Self? {
    guard inServiceBox(player, side: side), flight.hitter != side, !flight.serve,
      flight.fault == nil, flight.power == nil, after < 0.8 else { return nil }
    let origin = flight.worldBall(at: 0)
    let from = Vec(x: Double(origin.x), y: Double(origin.z))
    guard let section = intersection(from: from, to: flight.landing, player: player, radius: 1.95) else { return nil }
    let start = section.lowerBound * 0.8, end = section.upperBound * 0.8
    guard after <= end else { return nil }
    let steps = max(1, Int(ceil((end-start) * from.distance(to: flight.landing) / (0.8 * 0.09))))
    let sign = side == 0 ? 1.0 : -1.0
    var best: Self?, bestCost = Double.infinity
    for i in 0...steps {
      let t = max(after, start + (end - start) * Double(i) / Double(steps))
      let point = flight.worldBall(at: t)
      let h = Double(point.y), z = Double(point.z), dx = Double(point.x) - player.x
      let ahead = (player.y - z) * sign
      guard h >= 0.14, (z - PracticeEngine.net) * sign >= 0.05, ahead >= -0.45 else { continue }
      let gap = hypot(dx, ahead)
      let stroke: NetStroke, cost: Double
      var touch = true
      if h >= 2.13 {
        guard flight.kind != .slice && flight.kind != .drop else { continue }
        let reach = hypot(gap / 1.0, max(0, h - 2.16) / 1.00)
        guard reach <= 1.16 else { continue }
        stroke = h <= 2.66 && gap <= 0.74 ? .overhead : .jump
        touch = reach <= 1
        cost = (stroke == .overhead ? 0 : 2) + reach
      } else if gap <= 0.90 {
        stroke = .volley
        cost = 0.8 + t
      } else {
        let reach = hypot(dx / 1.70, ahead / 1.22)
        guard h <= 1.72, (abs(dx) >= 0.48 || ahead >= 0.85), reach <= 1.14 else { continue }
        stroke = .dive
        touch = reach <= 1
        cost = 3 + reach
      }
      let priority = cost + (touch ? 0 : 6)
      if priority < bestCost {
        bestCost = priority
        best = Self(entry: t, exit: t, volley: true, overhead: stroke.overhead, netStroke: stroke, reachable: touch)
      } else if best?.netStroke == stroke, !stroke.extended, touch, let previous = best,
        t - previous.exit <= max(0.00001, (end-start)/Double(steps) + 0.000001) {
        best?.exit = t
      }
    }
    return best
  }

  static func next(
    flight: BallFlight, player: Vec, side: Int, after progress: Double? = nil
  ) -> BallContactWindow? {
    guard flight.fault == nil, flight.hitter != side else { return nil }
    let current = progress ?? flight.progress
    if inServiceBox(player, side: side) {
      if let air = netOpportunity(flight: flight, player: player, side: side, after: current), air.reachable { return air }
      if let ground = groundstroke(flight: flight, player: player), ground.exit >= current { return ground }
      return nil
    }
    if let window = overhead(flight: flight, player: player, side: side), window.exit >= current {
      return window
    }
    if let window = volley(flight: flight, player: player, side: side), window.exit >= current {
      return window
    }
    if let window = groundstroke(flight: flight, player: player), window.exit >= current {
      return window
    }
    return nil
  }

  static func volley(flight: BallFlight, player: Vec, side: Int) -> BallContactWindow? {
    guard !flight.serve, flight.fault == nil, flight.hitter != side else {
      return nil
    }
    let dy = flight.landing.y - flight.launchPosition.y
    guard abs(dy) > 0.001,
      let segment = intersection(from: flight.launchPosition, to: flight.landing, player: player, radius: 0.9)
    else { return nil }
    let ownSide = ((side == 0 ? 12.685 : 11.085) - flight.launchPosition.y) / dy
    let lowBall =
      flight.loft >= 2
      ? 1 - asin(min(1, 1.7 / (flight.loft * 1.7))) / .pi : 0
    let entry = max(segment.lowerBound, ownSide, lowBall) * 0.8
    let exit = min(segment.upperBound * 0.8, 0.76)
    guard entry < exit else { return nil }
    return BallContactWindow(entry: entry, exit: exit, volley: true)
  }

  static func overheadTarget(flight: BallFlight, side: Int) -> (point: Vec, progress: Double)? {
    guard !flight.serve, flight.kind != .drop, flight.kind != .slice,
      flight.loft >= 2, flight.fault == nil, flight.hitter != side else {
      return nil
    }
    if flight.isDefensiveLob {
      // Use the descending flight from the diving player's actual racket face.
      var high = 0.4, low = 0.8
      guard flight.worldBall(at: high).y >= 2.55 else { return nil }
      for _ in 0..<11 {
        let t = (high + low) / 2
        if flight.worldBall(at: t).y > 2.55 { high = t } else { low = t }
      }
      let ball = flight.worldBall(at: low)
      let point = Vec(x: Double(ball.x), y: Double(ball.z))
      guard (point.y - PracticeEngine.net) * (side == 0 ? 1 : -1) > 0.7 else { return nil }
      return (point, low)
    }
    let fraction = 1 - asin(min(1, 2.65 / (flight.loft * 1.7))) / .pi
    let point = Vec(
      x: flight.launchPosition.x + (flight.landing.x - flight.launchPosition.x) * fraction,
      y: flight.launchPosition.y + (flight.landing.y - flight.launchPosition.y) * fraction)
    guard side == 0 ? point.y > PracticeEngine.net + 0.7 : point.y < PracticeEngine.net - 0.7 else {
      return nil
    }
    return (point, fraction * 0.8)
  }

  static func overhead(flight: BallFlight, player: Vec, side: Int) -> BallContactWindow? {
    guard let target = overheadTarget(flight: flight, side: side),
      player.distance(to: target.point) <= PracticeEngine.contactRadius + 0.000001 else { return nil }
    if flight.isDefensiveLob {
      return Self(entry: target.progress, exit: target.progress, volley: true, overhead: true, netStroke: .overhead)
    }
    guard let segment = intersection(
        from: flight.launchPosition, to: flight.landing, player: player,
        radius: PracticeEngine.contactRadius)
    else { return nil }
    let peak = flight.loft * 1.7
    let high = 1 - asin(min(1, 2.95 / peak)) / .pi
    let low = 1 - asin(min(1, 2.2 / peak)) / .pi
    let entry = max(high, segment.lowerBound) * 0.8
    let exit = min(low, segment.upperBound) * 0.8
    guard entry <= exit else { return nil }
    return BallContactWindow(entry: entry, exit: exit, volley: true, overhead: true)
  }

  private static func groundstroke(flight: BallFlight, player: Vec) -> BallContactWindow? {
    // A moving player may pass close to the ball before reaching the guide. Let that player
    // finish positioning instead of forcing an early, off-balance return outside yellow.
    guard player.distance(to: flight.contact) <= PracticeEngine.contactRadius + 0.000001 else {
      return nil
    }
    let end = flight.reboundEnd
    let hand = Vec(x:player.x+end.x-flight.contact.x,y:player.y+end.y-flight.contact.y)
    guard
      let segment = intersection(
        from: flight.landing, to: end, player: hand,
        radius: PracticeEngine.contactRadius)
    else { return nil }
    // Let the ball rise off the bounce, then strike as soon as it enters racket reach.
    let entry = max(flight.serve && flight.serveNumber == 2 ? 0.84 : 0.86, 0.8 + segment.lowerBound * 0.2)
    let exit = min(1, 0.8 + segment.upperBound * 0.2)
    guard entry <= exit else { return nil }
    return BallContactWindow(entry: entry, exit: exit, volley: false)
  }

  private static func intersection(from: Vec, to: Vec, player: Vec, radius: Double) -> ClosedRange<
    Double
  >? {
    let dx = to.x - from.x
    let dy = to.y - from.y
    let lengthSquared = dx * dx + dy * dy
    if lengthSquared < 0.000001 { return player.distance(to: from) <= radius ? 0...1 : nil }
    let px = player.x - from.x
    let py = player.y - from.y
    let nearest = (px * dx + py * dy) / lengthSquared
    let distanceSquared = max(0, px * px + py * py - nearest * nearest * lengthSquared)
    guard distanceSquared <= radius * radius + 0.000001 else { return nil }
    let halfWindow = sqrt(max(0, radius * radius - distanceSquared) / lengthSquared)
    let entry = max(0, nearest - halfWindow)
    let exit = min(1, nearest + halfWindow)
    return entry <= exit ? entry...exit : nil
  }
}
