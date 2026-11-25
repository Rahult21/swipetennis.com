import Foundation

/// One contact clock shared by the simulation, swing preparation and drawn ball.
struct BallContactWindow {
  let entry: Double
  let exit: Double
  let volley: Bool
  var overhead = false

  static func next(
    flight: BallFlight, player: Vec, side: Int, after progress: Double? = nil
  ) -> BallContactWindow? {
    guard flight.fault == nil, flight.hitter != side else { return nil }
    let current = progress ?? flight.progress
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
    let dy = flight.landing.y - flight.from.y
    guard abs(dy) > 0.001,
      let segment = intersection(from: flight.from, to: flight.landing, player: player, radius: 0.9)
    else { return nil }
    let ownSide = ((side == 0 ? 12.685 : 11.085) - flight.from.y) / dy
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
    let fraction = 1 - asin(min(1, 2.65 / (flight.loft * 1.7))) / .pi
    let point = Vec(
      x: flight.from.x + (flight.landing.x - flight.from.x) * fraction,
      y: flight.from.y + (flight.landing.y - flight.from.y) * fraction)
    guard side == 0 ? point.y > PracticeEngine.net + 0.7 : point.y < PracticeEngine.net - 0.7 else {
      return nil
    }
    return (point, fraction * 0.8)
  }

  static func overhead(flight: BallFlight, player: Vec, side: Int) -> BallContactWindow? {
    guard let target = overheadTarget(flight: flight, side: side),
      player.distance(to: target.point) <= PracticeEngine.contactRadius + 0.000001,
      let segment = intersection(
        from: flight.from, to: flight.landing, player: player,
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
    guard
      let segment = intersection(
        from: flight.landing, to: flight.contact, player: player,
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
